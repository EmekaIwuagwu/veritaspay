// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import "./interfaces/IHybridVault.sol";
import "./interfaces/IVeritasPayUSD.sol";

/**
 * @title HybridVault
 * @notice Manages collateral and executes hybrid stability mechanism
 * @dev Combines over-collateralization with algorithmic stabilization
 *
 * Three-Pillar Stability Model:
 * 1. Over-collateralization (150%+ reserve ratio)
 * 2. Algorithmic supply adjustment (when price deviates)
 * 3. Incentive mechanisms (stability pool, arbitrage)
 */
contract HybridVault is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IHybridVault
{
    using SafeERC20 for IERC20;

    /// @notice Role for executing stabilization mechanisms
    bytes32 public constant STABILIZER_ROLE = keccak256("STABILIZER_ROLE");

    /// @notice Role for managing collateral configuration
    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice VeritasPay USD token
    IVeritasPayUSD public vpusd;

    /// @notice Collateral tier configuration
    mapping(CollateralTier => CollateralInfo) public tierInfo;

    /// @notice Supported collateral tokens per tier
    mapping(CollateralTier => address[]) public tierTokens;

    /// @notice Token to oracle mapping
    mapping(address => AggregatorV3Interface) public oracles;

    /// @notice Token to tier mapping
    mapping(address => CollateralTier) public tokenTier;

    /// @notice VPUSD price oracle
    AggregatorV3Interface public vpusdOracle;

    /// @notice User positions
    mapping(uint256 => Position) public positions;

    /// @notice Position counter
    uint256 public positionCounter;

    /// @notice User position IDs
    mapping(address => uint256[]) public userPositions;

    /// @notice Stability parameters
    uint256 public minReserveRatio; // 150% = 15000 bps
    uint256 public targetReserveRatio; // 175% = 17500 bps
    uint256 public liquidationThreshold; // 130% = 13000 bps
    uint256 public deviationThreshold; // 2% = 200 bps
    uint256 public maxDailyMintCap; // 5% of supply
    uint256 public maxDailyBurnCap; // 5% of supply

    /// @notice Daily mint/burn tracking
    uint256 public dailyMinted;
    uint256 public dailyBurned;
    uint256 public lastResetTimestamp;

    /// @notice Circuit breaker
    bool public circuitBreakerActive;
    uint256 public constant CIRCUIT_BREAKER_THRESHOLD = 1000; // 10% depeg

    /// @notice DEX router for stabilization operations
    address public dexRouter;

    /// @notice Constants
    uint256 private constant BPS_DENOMINATOR = 10000;
    uint256 private constant PRICE_PRECISION = 1e18;
    uint256 private constant ORACLE_TIMEOUT = 1 hours;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the vault
     * @param admin Admin address
     * @param _vpusd VPUSD token address
     * @param _minReserveRatio Minimum reserve ratio in bps
     * @param _targetReserveRatio Target reserve ratio in bps
     */
    function initialize(
        address admin,
        address _vpusd,
        uint256 _minReserveRatio,
        uint256 _targetReserveRatio
    ) external initializer {
        require(admin != address(0), "Invalid admin");
        require(_vpusd != address(0), "Invalid VPUSD");
        require(_minReserveRatio >= 10000, "Reserve ratio too low");
        require(_targetReserveRatio > _minReserveRatio, "Invalid target ratio");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(KEEPER_ROLE, admin);
        _grantRole(STABILIZER_ROLE, admin);

        vpusd = IVeritasPayUSD(_vpusd);
        minReserveRatio = _minReserveRatio;
        targetReserveRatio = _targetReserveRatio;
        liquidationThreshold = 13000; // 130%
        deviationThreshold = 200; // 2%
        maxDailyMintCap = 500; // 5%
        maxDailyBurnCap = 500; // 5%
        lastResetTimestamp = block.timestamp;

        // Initialize tier weights (in bps)
        tierInfo[CollateralTier.TIER1] = CollateralInfo({
            weight: 7000,
            minCollateralRatio: 15000,
            isActive: true
        }); // 70%, 150% CR

        tierInfo[CollateralTier.TIER2] = CollateralInfo({
            weight: 2000,
            minCollateralRatio: 20000,
            isActive: true
        }); // 20%, 200% CR

        tierInfo[CollateralTier.TIER3] = CollateralInfo({
            weight: 1000,
            minCollateralRatio: 15000,
            isActive: true
        }); // 10%, 150% CR
    }

    /**
     * @notice Deposit collateral and mint VPUSD
     * @param collateralToken Address of collateral token
     * @param collateralAmount Amount of collateral to deposit
     * @param vpusdAmount Amount of VPUSD to mint
     * @return positionId Unique position identifier
     */
    function deposit(
        address collateralToken,
        uint256 collateralAmount,
        uint256 vpusdAmount
    ) external whenNotPaused nonReentrant returns (uint256 positionId) {
        require(collateralAmount > 0, "Invalid collateral amount");
        require(vpusdAmount > 0, "Invalid VPUSD amount");
        require(
            oracles[collateralToken] != AggregatorV3Interface(address(0)),
            "Unsupported collateral"
        );

        CollateralTier tier = tokenTier[collateralToken];
        require(tierInfo[tier].isActive, "Tier inactive");

        // Check collateralization ratio
        uint256 collateralValue = getCollateralValue(
            collateralToken,
            collateralAmount
        );
        uint256 requiredCollateral = (vpusdAmount *
            tierInfo[tier].minCollateralRatio) / BPS_DENOMINATOR;
        require(
            collateralValue >= requiredCollateral,
            "Insufficient collateral"
        );

        // Transfer collateral
        IERC20(collateralToken).safeTransferFrom(
            msg.sender,
            address(this),
            collateralAmount
        );

        // Mint VPUSD
        vpusd.mint(msg.sender, vpusdAmount);

        // Create position
        positionCounter++;
        positionId = positionCounter;

        positions[positionId] = Position({
            collateralAmount: collateralAmount,
            vpusdMinted: vpusdAmount,
            lastUpdateTime: block.timestamp,
            collateralToken: collateralToken,
            tier: tier
        });

        userPositions[msg.sender].push(positionId);

        emit CollateralDeposited(
            msg.sender,
            collateralToken,
            collateralAmount,
            vpusdAmount,
            positionId
        );
    }

    /**
     * @notice Withdraw collateral and burn VPUSD
     * @param positionId Position identifier
     * @param collateralAmount Amount of collateral to withdraw
     * @param vpusdAmount Amount of VPUSD to burn
     */
    function withdraw(
        uint256 positionId,
        uint256 collateralAmount,
        uint256 vpusdAmount
    ) external whenNotPaused nonReentrant {
        Position storage position = positions[positionId];
        require(position.collateralAmount > 0, "Invalid position");
        require(
            collateralAmount <= position.collateralAmount,
            "Insufficient collateral"
        );
        require(vpusdAmount <= position.vpusdMinted, "Insufficient debt");

        // Burn VPUSD
        vpusd.burn(msg.sender, vpusdAmount);

        // Update position
        position.collateralAmount -= collateralAmount;
        position.vpusdMinted -= vpusdAmount;
        position.lastUpdateTime = block.timestamp;

        // Check remaining position is healthy
        if (position.vpusdMinted > 0) {
            require(
                isPositionHealthy(positionId),
                "Position undercollateralized"
            );
        }

        // Transfer collateral back
        IERC20(position.collateralToken).safeTransfer(
            msg.sender,
            collateralAmount
        );

        emit CollateralWithdrawn(msg.sender, positionId, collateralAmount);
    }

    /**
     * @notice Execute algorithmic stabilization mechanism
     */
    function executeStabilization()
        external
        onlyRole(STABILIZER_ROLE)
        whenNotPaused
    {
        require(!circuitBreakerActive, "Circuit breaker active");

        // Reset daily caps if needed
        if (block.timestamp >= lastResetTimestamp + 1 days) {
            dailyMinted = 0;
            dailyBurned = 0;
            lastResetTimestamp = block.timestamp;
        }

        uint256 currentPrice = getVPUSDPrice();
        uint256 targetPrice = PRICE_PRECISION; // $1.00

        // Calculate deviation
        int256 deviation = int256(currentPrice) - int256(targetPrice);
        uint256 absDeviation = deviation >= 0
            ? uint256(deviation)
            : uint256(-deviation);

        // Check if stabilization needed
        uint256 deviationBps = (absDeviation * BPS_DENOMINATOR) / targetPrice;
        if (deviationBps < deviationThreshold) {
            return; // Price is stable
        }

        // Check for circuit breaker
        if (deviationBps >= CIRCUIT_BREAKER_THRESHOLD) {
            circuitBreakerActive = true;
            emit CircuitBreakerActivated(currentPrice, block.timestamp);
            return;
        }

        int256 supplyChange = 0;

        if (
            currentPrice >
            targetPrice + ((targetPrice * deviationThreshold) / BPS_DENOMINATOR)
        ) {
            // Price too high: expand supply
            supplyChange = _expandSupply(currentPrice, targetPrice);
        } else if (
            currentPrice <
            targetPrice - ((targetPrice * deviationThreshold) / BPS_DENOMINATOR)
        ) {
            // Price too low: contract supply
            supplyChange = _contractSupply(currentPrice, targetPrice);
        }

        emit StabilizationExecuted(
            currentPrice,
            targetPrice,
            supplyChange,
            block.timestamp
        );
    }

    /**
     * @notice Expand supply to decrease price
     * @param currentPrice Current VPUSD price
     * @param targetPrice Target price ($1.00)
     * @return supplyChange Amount of supply added
     */
    function _expandSupply(
        uint256 currentPrice,
        uint256 targetPrice
    ) private returns (int256 supplyChange) {
        uint256 totalSupply = vpusd.totalSupply();
        uint256 priceDeviation = currentPrice - targetPrice;

        // Calculate optimal mint amount (proportional to deviation)
        uint256 mintAmount = (totalSupply * priceDeviation) /
            (currentPrice * 10);

        // Apply daily cap
        uint256 dailyCap = (totalSupply * maxDailyMintCap) / BPS_DENOMINATOR;
        if (dailyMinted + mintAmount > dailyCap) {
            mintAmount = dailyCap - dailyMinted;
        }

        if (mintAmount > 0) {
            // Mint to this contract
            vpusd.mint(address(this), mintAmount);
            dailyMinted += mintAmount;

            // TODO: Sell on DEX to acquire more collateral
            // This would require DEX integration (Uniswap, Curve, etc.)

            supplyChange = int256(mintAmount);
        }
    }

    /**
     * @notice Contract supply to increase price
     * @param currentPrice Current VPUSD price
     * @param targetPrice Target price ($1.00)
     * @return supplyChange Amount of supply removed
     */
    function _contractSupply(
        uint256 currentPrice,
        uint256 targetPrice
    ) private returns (int256 supplyChange) {
        uint256 totalSupply = vpusd.totalSupply();
        uint256 priceDeviation = targetPrice - currentPrice;

        // Calculate optimal burn amount
        uint256 burnAmount = (totalSupply * priceDeviation) /
            (targetPrice * 10);

        // Apply daily cap
        uint256 dailyCap = (totalSupply * maxDailyBurnCap) / BPS_DENOMINATOR;
        if (dailyBurned + burnAmount > dailyCap) {
            burnAmount = dailyCap - dailyBurned;
        }

        if (burnAmount > 0) {
            // TODO: Buy from DEX using collateral
            // Then burn the acquired VPUSD

            // For now, burn from this contract if available
            uint256 balance = vpusd.balanceOf(address(this));
            if (balance >= burnAmount) {
                vpusd.burn(address(this), burnAmount);
                dailyBurned += burnAmount;
                supplyChange = -int256(burnAmount);
            }
        }
    }

    /**
     * @notice Rebalance reserves across tiers
     */
    function rebalanceReserves() external onlyRole(KEEPER_ROLE) {
        uint256 totalValue = _calculateTotalCollateralValue();
        if (totalValue == 0) return;

        for (uint8 i = 0; i < 3; i++) {
            CollateralTier tier = CollateralTier(i);
            uint256 tierValue = 0;
            address[] memory tokens = tierTokens[tier];
            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 balance = IERC20(tokens[j]).balanceOf(address(this));
                tierValue += getCollateralValue(tokens[j], balance);
            }

            uint256 currentWeight = (tierValue * BPS_DENOMINATOR) / totalValue;
            uint256 targetWeight = tierInfo[tier].weight;

            emit TierWeightStatus(tier, currentWeight, targetWeight);
        }

        emit ReservesRebalanced(block.timestamp);
    }

    /**
     * @notice Liquidate an undercollateralized position
     * @param positionId Position to liquidate
     */
    function liquidate(uint256 positionId) external nonReentrant {
        Position storage position = positions[positionId];
        require(position.collateralAmount > 0, "Invalid position");
        require(!isPositionHealthy(positionId), "Position healthy");

        uint256 collateralValue = getCollateralValue(
            position.collateralToken,
            position.collateralAmount
        );
        uint256 debtValue = position.vpusdMinted;

        // Liquidator must repay the debt
        vpusd.burn(msg.sender, debtValue);

        // Calculate collateral to transfer: (debtValue + 5% bonus) converted to collateral units
        // Since debtValue is in USD (18 decimals) and collateralValue is in USD (18 decimals)
        // Amount to transfer = (debtValue * 1.05) / collateralPrice

        AggregatorV3Interface oracle = oracles[position.collateralToken];
        uint8 decimals = oracle.decimals();
        (, int256 price, , uint256 updatedAt, ) = oracle.latestRoundData();
        require(updatedAt >= block.timestamp - ORACLE_TIMEOUT, "Stale price");
        uint256 priceScaled = uint256(price) * (10 ** (18 - decimals));

        uint256 totalValueToLiquidator = (debtValue * 10500) / BPS_DENOMINATOR;
        uint256 amountToTransfer = (totalValueToLiquidator * PRICE_PRECISION) /
            priceScaled;

        // Cap at available collateral
        if (amountToTransfer > position.collateralAmount) {
            amountToTransfer = position.collateralAmount;
        }

        IERC20(position.collateralToken).safeTransfer(
            msg.sender,
            amountToTransfer
        );

        // Clear position
        position.collateralAmount = 0;
        position.vpusdMinted = 0;

        emit PositionLiquidated(
            msg.sender,
            positionId,
            amountToTransfer,
            debtValue
        );
    }

    /**
     * @notice Get current reserve ratio
     * @return ratio Reserve ratio in basis points
     */
    function getReserveRatio() public view returns (uint256 ratio) {
        uint256 totalCollateralValue = _calculateTotalCollateralValue();
        uint256 totalVPUSDSupply = vpusd.totalSupply();

        if (totalVPUSDSupply == 0) {
            return 0;
        }

        ratio = (totalCollateralValue * BPS_DENOMINATOR) / totalVPUSDSupply;
    }

    /**
     * @notice Calculate total collateral value across all tiers
     */
    function _calculateTotalCollateralValue()
        private
        view
        returns (uint256 totalValue)
    {
        for (uint8 i = 0; i < 3; i++) {
            CollateralTier tier = CollateralTier(i);
            address[] memory tokens = tierTokens[tier];

            for (uint256 j = 0; j < tokens.length; j++) {
                uint256 balance = IERC20(tokens[j]).balanceOf(address(this));
                totalValue += getCollateralValue(tokens[j], balance);
            }
        }
    }

    /**
     * @notice Get VPUSD price from oracles
     * @return price Current price in USD (18 decimals)
     */
    function getVPUSDPrice() public view returns (uint256 price) {
        if (address(vpusdOracle) != address(0)) {
            (, int256 p, , uint256 updatedAt, ) = vpusdOracle.latestRoundData();
            require(
                updatedAt >= block.timestamp - ORACLE_TIMEOUT,
                "Stale price"
            );
            require(p > 0, "Invalid price");
            uint8 decimals = vpusdOracle.decimals();
            return uint256(p) * (10 ** (18 - decimals));
        }
        return PRICE_PRECISION; // Fallback to $1.00
    }

    /**
     * @notice Calculate collateral value in USD
     * @param token Collateral token address
     * @param amount Amount of collateral
     * @return value Value in USD
     */
    function getCollateralValue(
        address token,
        uint256 amount
    ) public view returns (uint256 value) {
        AggregatorV3Interface oracle = oracles[token];
        require(address(oracle) != address(0), "No oracle");

        (, int256 price, , uint256 updatedAt, ) = oracle.latestRoundData();
        require(updatedAt >= block.timestamp - ORACLE_TIMEOUT, "Stale price");
        require(price > 0, "Invalid price");

        uint8 decimals = oracle.decimals();
        uint256 priceScaled = uint256(price) * (10 ** (18 - decimals));

        value = (amount * priceScaled) / PRICE_PRECISION;
    }

    /**
     * @notice Get user's position details
     * @param positionId Position identifier
     * @return position Position structure
     */
    function getPosition(
        uint256 positionId
    ) external view returns (Position memory position) {
        return positions[positionId];
    }

    /**
     * @notice Check if position is healthy
     * @param positionId Position identifier
     * @return healthy True if position is healthy
     */
    function isPositionHealthy(
        uint256 positionId
    ) public view returns (bool healthy) {
        Position memory position = positions[positionId];
        if (position.vpusdMinted == 0) {
            return true;
        }

        uint256 collateralValue = getCollateralValue(
            position.collateralToken,
            position.collateralAmount
        );
        uint256 requiredCollateral = (position.vpusdMinted *
            liquidationThreshold) / BPS_DENOMINATOR;

        return collateralValue >= requiredCollateral;
    }

    /**
     * @notice Add supported collateral token
     * @param token Token address
     * @param tier Collateral tier
     * @param oracle Price oracle address
     */
    function addCollateralToken(
        address token,
        CollateralTier tier,
        address oracle
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(token != address(0), "Invalid token");
        require(oracle != address(0), "Invalid oracle");

        oracles[token] = AggregatorV3Interface(oracle);
        tokenTier[token] = tier;
        tierTokens[tier].push(token);
    }

    /**
     * @notice Emergency pause all operations
     */
    function emergencyPause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Activate circuit breaker
     */
    function activateCircuitBreaker() external onlyRole(DEFAULT_ADMIN_ROLE) {
        circuitBreakerActive = true;
        emit CircuitBreakerActivated(getVPUSDPrice(), block.timestamp);
    }

    /**
     * @notice Deactivate circuit breaker
     */
    function deactivateCircuitBreaker() external onlyRole(DEFAULT_ADMIN_ROLE) {
        circuitBreakerActive = false;
    }

    /**
     * @notice Set DEX router for stabilization operations
     * @param _dexRouter DEX router address
     */
    function setDEXRouter(
        address _dexRouter
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dexRouter = _dexRouter;
    }

    /**
     * @notice Set VPUSD price oracle
     * @param _vpusdOracle Oracle address
     */
    function setVPUSDOracle(
        address _vpusdOracle
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_vpusdOracle != address(0), "Invalid oracle");
        vpusdOracle = AggregatorV3Interface(_vpusdOracle);
    }

    /**
     * @notice Update stability parameters
     */
    function updateStabilityParams(
        uint256 _minReserveRatio,
        uint256 _targetReserveRatio,
        uint256 _deviationThreshold,
        uint256 _maxDailyMintCap,
        uint256 _maxDailyBurnCap
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_minReserveRatio >= 10000, "Reserve ratio too low");
        require(_targetReserveRatio > _minReserveRatio, "Invalid target");

        minReserveRatio = _minReserveRatio;
        targetReserveRatio = _targetReserveRatio;
        deviationThreshold = _deviationThreshold;
        maxDailyMintCap = _maxDailyMintCap;
        maxDailyBurnCap = _maxDailyBurnCap;
    }

    /**
     * @notice Authorize contract upgrade
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
