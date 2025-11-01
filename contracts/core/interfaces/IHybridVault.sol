// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IHybridVault
 * @notice Interface for the hybrid collateral vault with algorithmic stabilization
 */
interface IHybridVault {
    /**
     * @notice Collateral tier enumeration
     */
    enum CollateralTier {
        TIER1, // Stablecoins (70%)
        TIER2, // Crypto assets (20%)
        TIER3 // RWAs (10%)
    }

    /**
     * @notice Collateral information structure
     */
    struct CollateralInfo {
        uint256 weight; // Allocation percentage (in basis points)
        uint256 minCollateralRatio; // Minimum CR for this tier
        bool isActive;
    }

    /**
     * @notice User position structure
     */
    struct Position {
        uint256 collateralAmount;
        uint256 vpusdMinted;
        uint256 lastUpdateTime;
        address collateralToken;
        CollateralTier tier;
    }

    /**
     * @notice Emitted when collateral is deposited
     */
    event CollateralDeposited(
        address indexed user, address indexed token, uint256 amount, uint256 vpusdMinted, uint256 positionId
    );

    /**
     * @notice Emitted when collateral is withdrawn
     */
    event CollateralWithdrawn(address indexed user, uint256 positionId, uint256 amount);

    /**
     * @notice Emitted when algorithmic stabilization is executed
     */
    event StabilizationExecuted(uint256 price, uint256 targetPrice, int256 supplyChange, uint256 timestamp);

    /**
     * @notice Emitted when reserves are rebalanced
     */
    event ReservesRebalanced(uint256 timestamp);

    /**
     * @notice Emitted when a position is liquidated
     */
    event PositionLiquidated(address indexed user, uint256 positionId, uint256 collateralSeized, uint256 debtRepaid);

    /**
     * @notice Emitted when circuit breaker is activated
     */
    event CircuitBreakerActivated(uint256 price, uint256 timestamp);

    /**
     * @notice Deposit collateral and mint VPUSD
     * @param collateralToken Address of collateral token
     * @param collateralAmount Amount of collateral to deposit
     * @param vpusdAmount Amount of VPUSD to mint
     * @return positionId Unique position identifier
     */
    function deposit(address collateralToken, uint256 collateralAmount, uint256 vpusdAmount)
        external
        returns (uint256 positionId);

    /**
     * @notice Withdraw collateral and burn VPUSD
     * @param positionId Position identifier
     * @param collateralAmount Amount of collateral to withdraw
     * @param vpusdAmount Amount of VPUSD to burn
     */
    function withdraw(uint256 positionId, uint256 collateralAmount, uint256 vpusdAmount) external;

    /**
     * @notice Execute algorithmic stabilization mechanism
     */
    function executeStabilization() external;

    /**
     * @notice Rebalance reserves across tiers
     */
    function rebalanceReserves() external;

    /**
     * @notice Liquidate an undercollateralized position
     * @param positionId Position to liquidate
     */
    function liquidate(uint256 positionId) external;

    /**
     * @notice Get current reserve ratio
     * @return ratio Reserve ratio in basis points
     */
    function getReserveRatio() external view returns (uint256 ratio);

    /**
     * @notice Get VPUSD price from oracles
     * @return price Current price in USD (18 decimals)
     */
    function getVPUSDPrice() external view returns (uint256 price);

    /**
     * @notice Calculate collateral value in USD
     * @param token Collateral token address
     * @param amount Amount of collateral
     * @return value Value in USD
     */
    function getCollateralValue(address token, uint256 amount) external view returns (uint256 value);

    /**
     * @notice Get user's position details
     * @param positionId Position identifier
     * @return position Position structure
     */
    function getPosition(uint256 positionId) external view returns (Position memory position);

    /**
     * @notice Check if position is healthy (adequately collateralized)
     * @param positionId Position identifier
     * @return healthy True if position is healthy
     */
    function isPositionHealthy(uint256 positionId) external view returns (bool healthy);

    /**
     * @notice Add supported collateral token
     * @param token Token address
     * @param tier Collateral tier
     * @param oracle Price oracle address
     */
    function addCollateralToken(address token, CollateralTier tier, address oracle) external;

    /**
     * @notice Emergency pause all operations
     */
    function emergencyPause() external;

    /**
     * @notice Activate circuit breaker
     */
    function activateCircuitBreaker() external;
}
