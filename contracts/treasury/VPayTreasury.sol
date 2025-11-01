// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VPayTreasury
 * @notice Manages protocol revenue and liquidity
 * @dev Handles fee collection, distribution, and treasury operations
 */
contract VPayTreasury is
    Initializable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Revenue allocation enumeration
    enum RevenueAllocation {
        STAKERS, // 40%
        DEVELOPMENT, // 20%
        INSURANCE, // 20%
        LIQUIDITY, // 10%
        BUYBACK // 10%
    }

    /// @notice Staking position structure
    struct StakingPosition {
        uint256 amount;
        uint256 lockPeriod;
        uint256 startTime;
        uint256 rewardsAccumulated;
        bool active;
    }

    /// @notice Revenue source tracking
    struct RevenueSource {
        uint256 paymentFees;
        uint256 bridgeFees;
        uint256 fxSpread;
        uint256 merchantFees;
        uint256 interestIncome;
    }

    /// @notice Roles
    bytes32 public constant TREASURY_MANAGER_ROLE = keccak256("TREASURY_MANAGER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice VPUSD token
    IERC20 public vpusd;

    /// @notice Revenue sources
    RevenueSource public revenueSource;

    /// @notice Allocation percentages (in basis points)
    mapping(RevenueAllocation => uint256) public allocationBps;

    /// @notice Allocation wallets
    mapping(RevenueAllocation => address) public allocationWallets;

    /// @notice Staking positions
    mapping(address => mapping(uint256 => StakingPosition)) public stakingPositions;
    mapping(address => uint256) public userStakeCount;

    /// @notice Total staked amount
    uint256 public totalStaked;

    /// @notice Reward pool
    uint256 public rewardPool;

    /// @notice Lock periods (in seconds)
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    /// @notice APY rates per lock period (in basis points)
    mapping(uint256 => uint256) public apyRates;

    /// @notice Events
    event RevenueCollected(RevenueAllocation indexed allocation, uint256 amount);
    event RevenueDistributed(uint256 totalAmount, uint256 timestamp);
    event Staked(address indexed user, uint256 stakingId, uint256 amount, uint256 lockPeriod);
    event Unstaked(address indexed user, uint256 stakingId, uint256 amount, uint256 rewards);
    event RewardsClaimed(address indexed user, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Admin address
     * @param _vpusd VPUSD token address
     */
    function initialize(address admin, address _vpusd) external initializer {
        require(admin != address(0), "Invalid admin");
        require(_vpusd != address(0), "Invalid VPUSD");

        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(TREASURY_MANAGER_ROLE, admin);

        vpusd = IERC20(_vpusd);

        // Set default allocations
        allocationBps[RevenueAllocation.STAKERS] = 4000; // 40%
        allocationBps[RevenueAllocation.DEVELOPMENT] = 2000; // 20%
        allocationBps[RevenueAllocation.INSURANCE] = 2000; // 20%
        allocationBps[RevenueAllocation.LIQUIDITY] = 1000; // 10%
        allocationBps[RevenueAllocation.BUYBACK] = 1000; // 10%

        // Set default APY rates
        apyRates[LOCK_30_DAYS] = 500; // 5%
        apyRates[LOCK_90_DAYS] = 1000; // 10%
        apyRates[LOCK_180_DAYS] = 1500; // 15%
        apyRates[LOCK_365_DAYS] = 2500; // 25%
    }

    /**
     * @notice Stake VPUSD for rewards
     * @param amount Amount to stake
     * @param lockPeriod Lock period in seconds
     * @return stakingId Staking position ID
     */
    function stakeVPUSD(uint256 amount, uint256 lockPeriod) external nonReentrant returns (uint256 stakingId) {
        require(amount > 0, "Invalid amount");
        require(apyRates[lockPeriod] > 0, "Invalid lock period");

        // Transfer VPUSD to treasury
        vpusd.safeTransferFrom(msg.sender, address(this), amount);

        // Create staking position
        stakingId = userStakeCount[msg.sender]++;
        stakingPositions[msg.sender][stakingId] = StakingPosition({
            amount: amount,
            lockPeriod: lockPeriod,
            startTime: block.timestamp,
            rewardsAccumulated: 0,
            active: true
        });

        totalStaked += amount;

        emit Staked(msg.sender, stakingId, amount, lockPeriod);
    }

    /**
     * @notice Unstake VPUSD and claim rewards
     * @param stakingId Staking position ID
     */
    function unstake(uint256 stakingId) external nonReentrant {
        StakingPosition storage position = stakingPositions[msg.sender][stakingId];
        require(position.active, "Invalid position");
        require(block.timestamp >= position.startTime + position.lockPeriod, "Still locked");

        // Calculate rewards
        uint256 rewards = _calculateRewards(position);
        uint256 totalAmount = position.amount + rewards;

        // Mark as inactive
        position.active = false;
        totalStaked -= position.amount;

        // Transfer back
        vpusd.safeTransfer(msg.sender, totalAmount);

        emit Unstaked(msg.sender, stakingId, position.amount, rewards);
    }

    /**
     * @notice Claim accumulated rewards without unstaking
     * @param stakingId Staking position ID
     */
    function claimRewards(uint256 stakingId) external nonReentrant {
        StakingPosition storage position = stakingPositions[msg.sender][stakingId];
        require(position.active, "Invalid position");

        uint256 rewards = _calculateRewards(position);
        require(rewards > 0, "No rewards");

        position.rewardsAccumulated = 0;
        position.startTime = block.timestamp; // Reset for next reward period

        vpusd.safeTransfer(msg.sender, rewards);

        emit RewardsClaimed(msg.sender, rewards);
    }

    /**
     * @notice Calculate rewards for a staking position
     */
    function _calculateRewards(StakingPosition memory position) private view returns (uint256 rewards) {
        uint256 stakingDuration = block.timestamp - position.startTime;
        uint256 apy = apyRates[position.lockPeriod];

        // Calculate pro-rata rewards
        rewards = (position.amount * apy * stakingDuration) / (10000 * 365 days);
    }

    /**
     * @notice Get APY for a lock period
     * @param lockPeriod Lock period in seconds
     * @return apy APY in basis points
     */
    function getAPY(uint256 lockPeriod) external view returns (uint256 apy) {
        return apyRates[lockPeriod];
    }

    /**
     * @notice Collect revenue from fees
     * @param allocation Revenue allocation type
     * @param amount Amount collected
     */
    function collectRevenue(RevenueAllocation allocation, uint256 amount) external onlyRole(TREASURY_MANAGER_ROLE) {
        vpusd.safeTransferFrom(msg.sender, address(this), amount);

        if (allocation == RevenueAllocation.STAKERS) {
            rewardPool += amount;
        }

        emit RevenueCollected(allocation, amount);
    }

    /**
     * @notice Distribute revenue to allocations
     */
    function distributeRevenue() external onlyRole(TREASURY_MANAGER_ROLE) nonReentrant {
        uint256 totalRevenue = _calculateTotalRevenue();
        require(totalRevenue > 0, "No revenue");

        // Distribute to each allocation
        for (uint8 i = 0; i < 5; i++) {
            RevenueAllocation allocation = RevenueAllocation(i);
            uint256 allocationAmount = (totalRevenue * allocationBps[allocation]) / 10000;

            if (allocation == RevenueAllocation.STAKERS) {
                rewardPool += allocationAmount;
            } else if (allocationWallets[allocation] != address(0)) {
                vpusd.safeTransfer(allocationWallets[allocation], allocationAmount);
            }
        }

        emit RevenueDistributed(totalRevenue, block.timestamp);
    }

    /**
     * @notice Calculate total revenue
     */
    function _calculateTotalRevenue() private view returns (uint256) {
        return revenueSource.paymentFees + revenueSource.bridgeFees + revenueSource.fxSpread
            + revenueSource.merchantFees + revenueSource.interestIncome;
    }

    /**
     * @notice Get total revenue
     */
    function getTotalRevenue() external view returns (uint256) {
        return _calculateTotalRevenue();
    }

    /**
     * @notice Set allocation percentage
     * @param allocation Revenue allocation type
     * @param bps Basis points
     */
    function setAllocation(RevenueAllocation allocation, uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(bps <= 10000, "Invalid bps");
        allocationBps[allocation] = bps;
    }

    /**
     * @notice Set allocation wallet
     * @param allocation Revenue allocation type
     * @param wallet Wallet address
     */
    function setAllocationWallet(RevenueAllocation allocation, address wallet)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(wallet != address(0), "Invalid wallet");
        allocationWallets[allocation] = wallet;
    }

    /**
     * @notice Update APY rate
     * @param lockPeriod Lock period
     * @param apy APY in basis points
     */
    function setAPY(uint256 lockPeriod, uint256 apy) external onlyRole(DEFAULT_ADMIN_ROLE) {
        apyRates[lockPeriod] = apy;
    }

    /**
     * @notice Record payment fee revenue
     * @param amount Amount
     */
    function recordPaymentFees(uint256 amount) external onlyRole(TREASURY_MANAGER_ROLE) {
        revenueSource.paymentFees += amount;
    }

    /**
     * @notice Record bridge fee revenue
     * @param amount Amount
     */
    function recordBridgeFees(uint256 amount) external onlyRole(TREASURY_MANAGER_ROLE) {
        revenueSource.bridgeFees += amount;
    }

    /**
     * @notice Authorize contract upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
