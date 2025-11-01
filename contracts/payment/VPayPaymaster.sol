// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title VPayPaymaster
 * @notice ERC-4337 Paymaster for gasless VPUSD transactions
 * @dev Allows users to pay gas fees in VPUSD instead of native tokens
 *
 * Features:
 * - Pay gas in VPUSD
 * - Dynamic fee calculation based on gas price
 * - Merchant-sponsored transactions
 * - Multi-chain gas management
 */
contract VPayPaymaster is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Sponsorship types
    enum SponsorshipType {
        FULL, // Sponsor pays all gas
        PARTIAL, // User pays in VPUSD
        MERCHANT_SUBSIDIZED // Merchant covers gas for customer
    }

    /// @notice ERC-4337 EntryPoint contract
    address public immutable entryPoint;

    /// @notice VPUSD token
    IERC20 public immutable vpusd;

    /// @notice Native token price oracle (ETH/USD, MATIC/USD, etc.)
    AggregatorV3Interface public nativeTokenOracle;

    /// @notice Gas tank balance (native token)
    uint256 public gasTankBalance;

    /// @notice Service fee markup (in basis points)
    uint256 public serviceFeeBps;

    /// @notice Maximum service fee
    uint256 public constant MAX_SERVICE_FEE = 2000; // 20%

    /// @notice Sponsored accounts
    mapping(address => SponsorshipType) public sponsorships;

    /// @notice Merchant gas subsidies
    mapping(address => uint256) public merchantGasBudgets;

    /// @notice Per-chain gas tanks
    mapping(uint256 => uint256) public chainGasTanks;

    /// @notice Events
    event GasSponsored(address indexed user, uint256 vpusdAmount, uint256 gasAmount, SponsorshipType sponsorshipType);
    event GasTankRefilled(uint256 amount);
    event MerchantSubsidyAdded(address indexed merchant, uint256 amount);
    event ServiceFeeUpdated(uint256 oldFee, uint256 newFee);

    /**
     * @notice Constructor
     * @param _entryPoint ERC-4337 EntryPoint address
     * @param _vpusd VPUSD token address
     * @param _nativeTokenOracle Native token price oracle
     * @param _serviceFeeBps Service fee in basis points
     */
    constructor(address _entryPoint, address _vpusd, address _nativeTokenOracle, uint256 _serviceFeeBps)
        Ownable(msg.sender)
    {
        require(_entryPoint != address(0), "Invalid entrypoint");
        require(_vpusd != address(0), "Invalid VPUSD");
        require(_nativeTokenOracle != address(0), "Invalid oracle");
        require(_serviceFeeBps <= MAX_SERVICE_FEE, "Fee too high");

        entryPoint = _entryPoint;
        vpusd = IERC20(_vpusd);
        nativeTokenOracle = AggregatorV3Interface(_nativeTokenOracle);
        serviceFeeBps = _serviceFeeBps;
    }

    /**
     * @notice Validate paymaster user operation (ERC-4337)
     * @dev Called by EntryPoint to validate and pay for a user operation
     */
    function validatePaymasterUserOp(
        bytes calldata /* userOp */,
        bytes32 /* userOpHash */,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        require(msg.sender == entryPoint, "Only EntryPoint");
        require(gasTankBalance >= maxCost, "Insufficient gas tank");

        // Reserve gas for this operation
        gasTankBalance -= maxCost;

        // Return context for postOp
        context = abi.encode(maxCost);
        validationData = 0; // Valid signature
    }

    /**
     * @notice Post-operation handler (ERC-4337)
     * @dev Called after user operation to settle actual gas cost
     */
    function postOp(PostOpMode /* mode */, bytes calldata context, uint256 actualGasCost) external {
        require(msg.sender == entryPoint, "Only EntryPoint");

        uint256 maxCost = abi.decode(context, (uint256));

        // Refund unused gas to tank
        if (actualGasCost < maxCost) {
            gasTankBalance += (maxCost - actualGasCost);
        }
    }

    /**
     * @notice Calculate VPUSD fee for gas sponsorship
     * @param estimatedGas Estimated gas units
     * @param gasPrice Gas price in wei
     * @return vpusdFee Fee amount in VPUSD
     */
    function calculateVPUSDFee(uint256 estimatedGas, uint256 gasPrice) public view returns (uint256 vpusdFee) {
        // Get native token price (ETH, MATIC, etc.)
        (, int256 nativePrice,, uint256 updatedAt,) = nativeTokenOracle.latestRoundData();
        require(updatedAt >= block.timestamp - 1 hours, "Stale price");
        require(nativePrice > 0, "Invalid price");

        uint8 decimals = nativeTokenOracle.decimals();

        // Calculate gas cost in native token
        uint256 gasCostWei = estimatedGas * gasPrice;

        // Convert to USD (18 decimals)
        uint256 gasCostUSD = (gasCostWei * uint256(nativePrice) * 1e18) / (10 ** decimals) / 1e18;

        // Add service fee
        vpusdFee = (gasCostUSD * (10000 + serviceFeeBps)) / 10000;
    }

    /**
     * @notice Sponsor a transaction with VPUSD
     * @param user User address
     * @param estimatedGas Estimated gas
     * @param gasPrice Gas price
     */
    function sponsorWithVPUSD(address user, uint256 estimatedGas, uint256 gasPrice) external {
        uint256 vpusdFee = calculateVPUSDFee(estimatedGas, gasPrice);

        // Collect VPUSD from user
        vpusd.safeTransferFrom(user, address(this), vpusdFee);

        emit GasSponsored(user, vpusdFee, estimatedGas * gasPrice, SponsorshipType.PARTIAL);
    }

    /**
     * @notice Merchant sponsors customer transaction
     * @param merchant Merchant address
     * @param customer Customer address
     * @param estimatedGas Estimated gas
     * @param gasPrice Gas price
     */
    function merchantSponsor(address merchant, address customer, uint256 estimatedGas, uint256 gasPrice) external {
        require(merchantGasBudgets[merchant] > 0, "No budget");

        uint256 vpusdFee = calculateVPUSDFee(estimatedGas, gasPrice);
        require(merchantGasBudgets[merchant] >= vpusdFee, "Insufficient budget");

        merchantGasBudgets[merchant] -= vpusdFee;

        emit GasSponsored(customer, vpusdFee, estimatedGas * gasPrice, SponsorshipType.MERCHANT_SUBSIDIZED);
    }

    /**
     * @notice Add merchant gas subsidy budget
     * @param merchant Merchant address
     * @param vpusdAmount Amount of VPUSD to add
     */
    function addMerchantSubsidy(address merchant, uint256 vpusdAmount) external {
        vpusd.safeTransferFrom(msg.sender, address(this), vpusdAmount);
        merchantGasBudgets[merchant] += vpusdAmount;

        emit MerchantSubsidyAdded(merchant, vpusdAmount);
    }

    /**
     * @notice Refill gas tank with native tokens
     */
    function refillGasTank() external payable onlyOwner {
        gasTankBalance += msg.value;
        emit GasTankRefilled(msg.value);
    }

    /**
     * @notice Get gas tank balance
     */
    function getGasTankBalance() external view returns (uint256) {
        return gasTankBalance;
    }

    /**
     * @notice Withdraw gas tank (emergency)
     * @param amount Amount to withdraw
     */
    function withdrawGasTank(uint256 amount) external onlyOwner {
        require(amount <= gasTankBalance, "Insufficient balance");
        gasTankBalance -= amount;

        (bool success,) = owner().call{value: amount}("");
        require(success, "Transfer failed");
    }

    /**
     * @notice Withdraw VPUSD (for converting to native token)
     * @param amount Amount to withdraw
     */
    function withdrawVPUSD(uint256 amount) external onlyOwner {
        vpusd.safeTransfer(owner(), amount);
    }

    /**
     * @notice Update service fee
     * @param _serviceFeeBps New service fee in basis points
     */
    function setServiceFee(uint256 _serviceFeeBps) external onlyOwner {
        require(_serviceFeeBps <= MAX_SERVICE_FEE, "Fee too high");
        emit ServiceFeeUpdated(serviceFeeBps, _serviceFeeBps);
        serviceFeeBps = _serviceFeeBps;
    }

    /**
     * @notice Update native token oracle
     * @param _oracle New oracle address
     */
    function setNativeTokenOracle(address _oracle) external onlyOwner {
        require(_oracle != address(0), "Invalid oracle");
        nativeTokenOracle = AggregatorV3Interface(_oracle);
    }

    /**
     * @notice Set sponsorship for an account
     * @param account Account address
     * @param sponsorshipType Type of sponsorship
     */
    function setSponsorship(address account, SponsorshipType sponsorshipType) external onlyOwner {
        sponsorships[account] = sponsorshipType;
    }

    /**
     * @notice Receive native tokens
     */
    receive() external payable {
        gasTankBalance += msg.value;
        emit GasTankRefilled(msg.value);
    }
}

/// @notice ERC-4337 PostOpMode enum
enum PostOpMode {
    opSucceeded,
    opReverted,
    postOpReverted
}
