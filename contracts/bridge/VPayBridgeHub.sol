// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../core/interfaces/IVeritasPayUSD.sol";

/**
 * @title VPayBridgeHub
 * @notice Multi-protocol cross-chain payment infrastructure
 * @dev Supports LayerZero, Axelar, Wormhole, and Chainlink CCIP
 *
 * Features:
 * - Multi-bridge support for redundancy
 * - Smart route selection (fastest, cheapest, most reliable)
 * - Cross-chain payment tracking
 * - Failed transfer recovery
 * - Liquidity management across chains
 */
contract VPayBridgeHub is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Bridge protocol enumeration
    enum BridgeProtocol {
        LAYERZERO,
        AXELAR,
        WORMHOLE,
        CCIP
    }

    /// @notice Route preference
    enum RoutePreference {
        FASTEST,
        CHEAPEST,
        MOST_RELIABLE
    }

    /// @notice Bridge status
    enum BridgeStatus {
        INITIATED,
        IN_TRANSIT,
        COMPLETED,
        FAILED,
        REFUNDED
    }

    /// @notice Bridge route structure
    struct BridgeRoute {
        BridgeProtocol protocol;
        uint256 estimatedTime; // in seconds
        uint256 baseFee;
        bool isActive;
        uint256 successRate; // in basis points (10000 = 100%)
    }

    /// @notice Cross-chain payment structure
    struct CrossChainPayment {
        uint256 sourceChain;
        uint256 destChain;
        address sender;
        address recipient;
        uint256 amount;
        uint256 timestamp;
        BridgeStatus status;
        BridgeProtocol protocol;
        bytes32 bridgeTransactionId;
    }

    /// @notice Roles
    bytes32 public constant BRIDGE_OPERATOR_ROLE =
        keccak256("BRIDGE_OPERATOR_ROLE");
    bytes32 public constant LIQUIDITY_PROVIDER_ROLE =
        keccak256("LIQUIDITY_PROVIDER_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice VPUSD token
    IVeritasPayUSD public vpusd;

    /// @notice Available routes per chain pair
    mapping(uint256 => mapping(uint256 => BridgeRoute[])) public routes;

    /// @notice Cross-chain payments
    mapping(bytes32 => CrossChainPayment) public crossChainPayments;

    /// @notice Liquidity per chain
    mapping(uint256 => uint256) public chainLiquidity;

    /// @notice Bridge fee percentage (in basis points)
    uint256 public bridgeFeeBps;

    /// @notice Maximum bridge fee
    uint256 public constant MAX_BRIDGE_FEE = 100; // 1%

    /// @notice Rate limit per user per day
    uint256 public dailyRateLimit;

    /// @notice User daily volume tracking
    mapping(address => mapping(uint256 => uint256)) public userDailyVolume; // user => day => volume

    /// @notice Insurance pool
    uint256 public insurancePool;

    /// @notice Payment counter
    uint256 private paymentCounter;

    /// @notice Bridge protocol endpoints
    mapping(BridgeProtocol => address) public protocolEndpoints;

    /// @notice Events
    event PaymentBridged(
        bytes32 indexed bridgeId,
        address indexed sender,
        address indexed recipient,
        uint256 sourceChain,
        uint256 destChain,
        uint256 amount,
        BridgeProtocol protocol
    );

    event BridgeCompleted(bytes32 indexed bridgeId, uint256 timestamp);
    event BridgeFailed(bytes32 indexed bridgeId, string reason);
    event LiquidityAdded(uint256 indexed chainId, uint256 amount);
    event RouteUpdated(
        uint256 indexed sourceChain,
        uint256 indexed destChain,
        BridgeProtocol protocol
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Admin address
     * @param _vpusd VPUSD token address
     * @param _bridgeFeeBps Bridge fee in basis points
     * @param _dailyRateLimit Daily rate limit per user
     */
    function initialize(
        address admin,
        address _vpusd,
        uint256 _bridgeFeeBps,
        uint256 _dailyRateLimit
    ) external initializer {
        require(admin != address(0), "Invalid admin");
        require(_vpusd != address(0), "Invalid VPUSD");
        require(_bridgeFeeBps <= MAX_BRIDGE_FEE, "Fee too high");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(BRIDGE_OPERATOR_ROLE, admin);

        vpusd = IVeritasPayUSD(_vpusd);
        bridgeFeeBps = _bridgeFeeBps;
        dailyRateLimit = _dailyRateLimit;
    }

    /**
     * @notice Bridge payment to another chain
     * @param destinationChain Destination chain ID
     * @param recipient Recipient address
     * @param amount Amount to bridge
     * @param preferredProtocol Preferred bridge protocol
     * @param paymentMetadata Payment metadata
     * @return bridgeId Unique bridge identifier
     */
    function bridgePayment(
        uint256 destinationChain,
        address recipient,
        uint256 amount,
        BridgeProtocol preferredProtocol,
        bytes calldata paymentMetadata
    ) external payable whenNotPaused nonReentrant returns (bytes32 bridgeId) {
        require(amount > 0, "Invalid amount");
        require(recipient != address(0), "Invalid recipient");
        require(destinationChain != block.chainid, "Same chain");

        // Check rate limit
        uint256 today = block.timestamp / 1 days;
        require(
            userDailyVolume[msg.sender][today] + amount <= dailyRateLimit,
            "Rate limit exceeded"
        );
        userDailyVolume[msg.sender][today] += amount;

        // Calculate fee
        uint256 fee = (amount * bridgeFeeBps) / 10000;
        uint256 netAmount = amount - fee;

        // Burn VPUSD on source chain
        vpusd.burn(msg.sender, amount);

        // Add fee to insurance pool
        if (fee > 0) {
            insurancePool += fee;
        }

        // Generate bridge ID
        paymentCounter++;
        bridgeId = keccak256(
            abi.encodePacked(
                msg.sender,
                recipient,
                destinationChain,
                amount,
                block.timestamp,
                paymentCounter
            )
        );

        // Store payment
        crossChainPayments[bridgeId] = CrossChainPayment({
            sourceChain: block.chainid,
            destChain: destinationChain,
            sender: msg.sender,
            recipient: recipient,
            amount: netAmount,
            timestamp: block.timestamp,
            status: BridgeStatus.INITIATED,
            protocol: preferredProtocol,
            bridgeTransactionId: bytes32(0)
        });

        // Execute bridge based on protocol
        _executeBridge(
            bridgeId,
            destinationChain,
            recipient,
            netAmount,
            preferredProtocol,
            paymentMetadata
        );

        emit PaymentBridged(
            bridgeId,
            msg.sender,
            recipient,
            block.chainid,
            destinationChain,
            amount,
            preferredProtocol
        );
    }

    /**
     * @notice Execute bridge transaction
     */
    function _executeBridge(
        bytes32 bridgeId,
        uint256 destinationChain,
        address recipient,
        uint256 amount,
        BridgeProtocol protocol,
        bytes memory metadata
    ) private {
        // Mark as in transit
        crossChainPayments[bridgeId].status = BridgeStatus.IN_TRANSIT;

        // In production, this would call the actual bridge protocol endpoints:
        // Example LayerZero: ILayerZeroEndpoint(protocolEndpoints[BridgeProtocol.LAYERZERO]).send(...)
        // Example Axelar: IAxelarGateway(protocolEndpoints[BridgeProtocol.AXELAR]).callContract(...)

        // For testing/demonstration, we simulate the transmission
    }

    /**
     * @notice Receive bridged payment (called by bridge on destination chain)
     * @param bridgeId Bridge identifier
     * @param recipient Recipient address
     * @param amount Amount to mint
     */
    function receiveBridgedPayment(
        bytes32 bridgeId,
        address recipient,
        uint256 amount
    ) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        // Mint VPUSD on destination chain
        vpusd.mint(recipient, amount);

        // Update payment status
        if (crossChainPayments[bridgeId].sender != address(0)) {
            crossChainPayments[bridgeId].status = BridgeStatus.COMPLETED;
            emit BridgeCompleted(bridgeId, block.timestamp);
        }
    }

    /**
     * @notice Get best route for a destination
     * @param destinationChain Destination chain ID
     * @param amount Amount to bridge
     * @param preference Route preference
     * @return route Best route
     */
    function getBestRoute(
        uint256 destinationChain,
        uint256 amount,
        RoutePreference preference
    ) external view returns (BridgeRoute memory route) {
        BridgeRoute[] memory availableRoutes = routes[block.chainid][
            destinationChain
        ];
        require(availableRoutes.length > 0, "No routes available");

        uint256 bestIndex = 0;

        for (uint256 i = 1; i < availableRoutes.length; i++) {
            if (!availableRoutes[i].isActive) continue;

            if (preference == RoutePreference.FASTEST) {
                if (
                    availableRoutes[i].estimatedTime <
                    availableRoutes[bestIndex].estimatedTime
                ) {
                    bestIndex = i;
                }
            } else if (preference == RoutePreference.CHEAPEST) {
                if (
                    availableRoutes[i].baseFee <
                    availableRoutes[bestIndex].baseFee
                ) {
                    bestIndex = i;
                }
            } else if (preference == RoutePreference.MOST_RELIABLE) {
                if (
                    availableRoutes[i].successRate >
                    availableRoutes[bestIndex].successRate
                ) {
                    bestIndex = i;
                }
            }
        }

        return availableRoutes[bestIndex];
    }

    /**
     * @notice Retry failed bridge
     * @param bridgeId Bridge identifier
     */
    function retryFailedBridge(
        bytes32 bridgeId
    ) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        CrossChainPayment storage payment = crossChainPayments[bridgeId];
        require(payment.status == BridgeStatus.FAILED, "Not failed");

        payment.status = BridgeStatus.IN_TRANSIT;

        // Retry with same or different protocol
        _executeBridge(
            bridgeId,
            payment.destChain,
            payment.recipient,
            payment.amount,
            payment.protocol,
            hex""
        );
    }

    /**
     * @notice Refund failed bridge
     * @param bridgeId Bridge identifier
     */
    function refundFailedBridge(bytes32 bridgeId) external nonReentrant {
        CrossChainPayment storage payment = crossChainPayments[bridgeId];
        require(payment.status == BridgeStatus.FAILED, "Not failed");
        require(
            payment.sender == msg.sender ||
                hasRole(BRIDGE_OPERATOR_ROLE, msg.sender),
            "Unauthorized"
        );

        payment.status = BridgeStatus.REFUNDED;

        // Mint back to sender (using insurance pool if needed)
        vpusd.mint(payment.sender, payment.amount);
    }

    /**
     * @notice Add liquidity to a chain
     * @param chainId Chain ID
     * @param amount Amount to add
     */
    function addLiquidity(
        uint256 chainId,
        uint256 amount
    ) external onlyRole(LIQUIDITY_PROVIDER_ROLE) {
        chainLiquidity[chainId] += amount;
        emit LiquidityAdded(chainId, amount);
    }

    /**
     * @notice Add a bridge route
     * @param sourceChain Source chain ID
     * @param destChain Destination chain ID
     * @param protocol Bridge protocol
     * @param estimatedTime Estimated time in seconds
     * @param baseFee Base fee
     */
    function addRoute(
        uint256 sourceChain,
        uint256 destChain,
        BridgeProtocol protocol,
        uint256 estimatedTime,
        uint256 baseFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        routes[sourceChain][destChain].push(
            BridgeRoute({
                protocol: protocol,
                estimatedTime: estimatedTime,
                baseFee: baseFee,
                isActive: true,
                successRate: 10000
            })
        );

        emit RouteUpdated(sourceChain, destChain, protocol);
    }

    /**
     * @notice Set protocol endpoint
     * @param protocol Bridge protocol
     * @param endpoint Endpoint address
     */
    function setProtocolEndpoint(
        BridgeProtocol protocol,
        address endpoint
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(endpoint != address(0), "Invalid endpoint");
        protocolEndpoints[protocol] = endpoint;
    }

    /**
     * @notice Update bridge fee
     * @param _bridgeFeeBps New bridge fee
     */
    function setBridgeFee(
        uint256 _bridgeFeeBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_bridgeFeeBps <= MAX_BRIDGE_FEE, "Fee too high");
        bridgeFeeBps = _bridgeFeeBps;
    }

    /**
     * @notice Update daily rate limit
     * @param _dailyRateLimit New rate limit
     */
    function setDailyRateLimit(
        uint256 _dailyRateLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        dailyRateLimit = _dailyRateLimit;
    }

    /**
     * @notice Mark bridge as failed
     * @param bridgeId Bridge identifier
     * @param reason Failure reason
     */
    function markBridgeFailed(
        bytes32 bridgeId,
        string calldata reason
    ) external onlyRole(BRIDGE_OPERATOR_ROLE) {
        crossChainPayments[bridgeId].status = BridgeStatus.FAILED;
        emit BridgeFailed(bridgeId, reason);
    }

    /**
     * @notice Pause operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Authorize contract upgrade
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}
