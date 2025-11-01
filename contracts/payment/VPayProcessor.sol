// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../core/interfaces/IVPayProcessor.sol";
import "../core/interfaces/IVeritasPayUSD.sol";
import "../core/interfaces/IVPayCompliance.sol";

/**
 * @title VPayProcessor
 * @notice Handles merchant payment processing and settlement
 * @dev Supports multiple settlement options including instant fiat conversion
 */
contract VPayProcessor is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    IVPayProcessor
{
    using SafeERC20 for IERC20;

    /// @notice Role for managing merchant operations
    bytes32 public constant MERCHANT_MANAGER_ROLE = keccak256("MERCHANT_MANAGER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice VeritasPay USD token
    IVeritasPayUSD public vpusd;

    /// @notice Compliance oracle
    IVPayCompliance public complianceOracle;

    /// @notice Merchant registry
    mapping(address => Merchant) public merchants;

    /// @notice Invoice registry
    mapping(bytes32 => Invoice) public invoices;

    /// @notice Payment tracking
    mapping(bytes32 => bool) public processedPayments;

    /// @notice Payment counter
    uint256 private paymentCounter;

    /// @notice Invoice counter
    uint256 private invoiceCounter;

    /// @notice Fee configuration (in basis points)
    uint256 public merchantFeeBps; // 0.3% = 30 bps
    uint256 public constant MAX_MERCHANT_FEE = 500; // 5% maximum

    /// @notice Fee collector
    address public feeCollector;

    /// @notice Fiat offramp provider (for settlements)
    address public fiatOfframpProvider;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Admin address
     * @param _vpusd VPUSD token address
     * @param _feeCollector Fee collector address
     * @param _merchantFeeBps Merchant fee in basis points
     */
    function initialize(address admin, address _vpusd, address _feeCollector, uint256 _merchantFeeBps)
        external
        initializer
    {
        require(admin != address(0), "Invalid admin");
        require(_vpusd != address(0), "Invalid VPUSD");
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_merchantFeeBps <= MAX_MERCHANT_FEE, "Fee too high");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(MERCHANT_MANAGER_ROLE, admin);

        vpusd = IVeritasPayUSD(_vpusd);
        feeCollector = _feeCollector;
        merchantFeeBps = _merchantFeeBps;
    }

    /**
     * @notice Register as a merchant
     * @param businessName Business name
     * @param country Country code
     * @param settlement Settlement preference
     */
    function registerMerchant(string calldata businessName, string calldata country, FiatSettlementPreference settlement)
        external
        whenNotPaused
    {
        require(merchants[msg.sender].wallet == address(0), "Already registered");
        require(bytes(businessName).length > 0, "Invalid business name");
        require(bytes(country).length > 0, "Invalid country");

        // Check compliance
        if (address(complianceOracle) != address(0)) {
            require(complianceOracle.isVerified(msg.sender), "Not KYC verified");
            require(!complianceOracle.isSanctioned(msg.sender), "Sanctioned address");
        }

        merchants[msg.sender] = Merchant({
            wallet: msg.sender,
            businessName: businessName,
            country: country,
            verified: true,
            totalVolume: 0,
            transactionCount: 0,
            settlement: settlement
        });

        emit MerchantRegistered(msg.sender, businessName, country);
    }

    /**
     * @notice Process a payment to a merchant
     * @param merchant Merchant address
     * @param amount Payment amount
     * @param invoiceId Invoice identifier
     * @param currency Destination currency
     * @return paymentId Unique payment identifier
     */
    function processPayment(address merchant, uint256 amount, bytes32 invoiceId, string calldata currency)
        external
        whenNotPaused
        nonReentrant
        returns (bytes32 paymentId)
    {
        require(amount > 0, "Invalid amount");
        require(merchants[merchant].wallet != address(0), "Merchant not registered");

        // Check compliance
        if (address(complianceOracle) != address(0)) {
            require(complianceOracle.isVerified(msg.sender), "Payer not verified");
            require(complianceOracle.isVerified(merchant), "Merchant not verified");
            require(!complianceOracle.isSanctioned(msg.sender), "Payer sanctioned");
            require(!complianceOracle.isSanctioned(merchant), "Merchant sanctioned");
        }

        // Generate unique payment ID
        paymentCounter++;
        paymentId = keccak256(abi.encodePacked(msg.sender, merchant, amount, block.timestamp, paymentCounter));

        require(!processedPayments[paymentId], "Payment already processed");
        processedPayments[paymentId] = true;

        // Calculate fees
        uint256 fee = calculateMerchantFee(amount);
        uint256 netAmount = amount - fee;

        // Transfer VPUSD from payer
        IERC20(address(vpusd)).safeTransferFrom(msg.sender, address(this), amount);

        // Collect fee
        if (fee > 0) {
            IERC20(address(vpusd)).safeTransfer(feeCollector, fee);
        }

        // Settle to merchant based on preference
        Merchant storage merchantData = merchants[merchant];
        if (merchantData.settlement == FiatSettlementPreference.CRYPTO) {
            // Direct VPUSD transfer
            IERC20(address(vpusd)).safeTransfer(merchant, netAmount);
        } else {
            // Initiate fiat offramp
            _initiateFiatOfframp(merchant, netAmount, currency, merchantData.settlement);
        }

        // Update merchant stats
        merchantData.totalVolume += amount;
        merchantData.transactionCount += 1;

        emit PaymentProcessed(paymentId, msg.sender, merchant, amount, invoiceId, fee);
    }

    /**
     * @notice Execute batch payments (payroll/remittances)
     * @param recipients Array of recipient addresses
     * @param amounts Array of payment amounts
     * @param purpose Payment purpose
     * @return paymentIds Array of payment identifiers
     */
    function batchPayments(address[] calldata recipients, uint256[] calldata amounts, string calldata purpose)
        external
        whenNotPaused
        nonReentrant
        returns (bytes32[] memory paymentIds)
    {
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length > 0, "Empty arrays");
        require(recipients.length <= 100, "Too many recipients");

        // Check compliance for sender
        if (address(complianceOracle) != address(0)) {
            require(complianceOracle.isVerified(msg.sender), "Sender not verified");
            require(!complianceOracle.isSanctioned(msg.sender), "Sender sanctioned");
        }

        paymentIds = new bytes32[](recipients.length);
        uint256 totalAmount = 0;

        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(amounts[i] > 0, "Invalid amount");

            // Check recipient compliance
            if (address(complianceOracle) != address(0)) {
                require(complianceOracle.isVerified(recipients[i]), "Recipient not verified");
                require(!complianceOracle.isSanctioned(recipients[i]), "Recipient sanctioned");
            }

            // Generate payment ID
            paymentCounter++;
            paymentIds[i] =
                keccak256(abi.encodePacked(msg.sender, recipients[i], amounts[i], block.timestamp, paymentCounter));

            totalAmount += amounts[i];
        }

        // Transfer total amount from sender
        IERC20(address(vpusd)).safeTransferFrom(msg.sender, address(this), totalAmount);

        // Distribute to recipients
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 fee = calculateMerchantFee(amounts[i]);
            uint256 netAmount = amounts[i] - fee;

            IERC20(address(vpusd)).safeTransfer(recipients[i], netAmount);

            if (fee > 0) {
                IERC20(address(vpusd)).safeTransfer(feeCollector, fee);
            }
        }

        emit BatchPaymentsExecuted(msg.sender, recipients.length, totalAmount, purpose);
    }

    /**
     * @notice Create an invoice
     * @param amount Invoice amount
     * @param currency Currency code
     * @param expiresAt Expiration timestamp
     * @return invoiceId Unique invoice identifier
     */
    function createInvoice(uint256 amount, string calldata currency, uint256 expiresAt)
        external
        whenNotPaused
        returns (bytes32 invoiceId)
    {
        require(merchants[msg.sender].wallet != address(0), "Not a merchant");
        require(amount > 0, "Invalid amount");
        require(expiresAt > block.timestamp, "Invalid expiration");

        invoiceCounter++;
        invoiceId = keccak256(abi.encodePacked(msg.sender, amount, currency, block.timestamp, invoiceCounter));

        invoices[invoiceId] = Invoice({
            merchant: msg.sender,
            amount: amount,
            currency: currency,
            createdAt: block.timestamp,
            expiresAt: expiresAt,
            status: InvoiceStatus.PENDING
        });

        emit InvoiceCreated(invoiceId, msg.sender, amount, currency);
    }

    /**
     * @notice Pay an invoice
     * @param invoiceId Invoice identifier
     */
    function payInvoice(bytes32 invoiceId) external whenNotPaused nonReentrant {
        Invoice storage invoice = invoices[invoiceId];
        require(invoice.status == InvoiceStatus.PENDING, "Invalid invoice");
        require(block.timestamp <= invoice.expiresAt, "Invoice expired");

        // Check compliance
        if (address(complianceOracle) != address(0)) {
            require(complianceOracle.isVerified(msg.sender), "Payer not verified");
            require(!complianceOracle.isSanctioned(msg.sender), "Payer sanctioned");
        }

        invoice.status = InvoiceStatus.PAID;

        // Process payment
        uint256 fee = calculateMerchantFee(invoice.amount);
        uint256 netAmount = invoice.amount - fee;

        IERC20(address(vpusd)).safeTransferFrom(msg.sender, invoice.merchant, netAmount);

        if (fee > 0) {
            IERC20(address(vpusd)).safeTransferFrom(msg.sender, feeCollector, fee);
        }

        // Update merchant stats
        Merchant storage merchantData = merchants[invoice.merchant];
        merchantData.totalVolume += invoice.amount;
        merchantData.transactionCount += 1;

        emit InvoicePaid(invoiceId, msg.sender, invoice.amount);
    }

    /**
     * @notice Update settlement preference
     * @param preference New settlement preference
     */
    function updateSettlementPreference(FiatSettlementPreference preference) external {
        require(merchants[msg.sender].wallet != address(0), "Not a merchant");
        merchants[msg.sender].settlement = preference;
    }

    /**
     * @notice Get merchant information
     * @param merchant Merchant address
     * @return merchantInfo Merchant structure
     */
    function getMerchant(address merchant) external view returns (Merchant memory merchantInfo) {
        return merchants[merchant];
    }

    /**
     * @notice Get merchant statistics
     * @param merchant Merchant address
     * @return stats Merchant statistics
     */
    function getMerchantStats(address merchant) external view returns (MerchantStats memory stats) {
        Merchant memory merchantData = merchants[merchant];
        stats.totalVolume = merchantData.totalVolume;
        stats.transactionCount = merchantData.transactionCount;
        stats.averageTransaction =
            merchantData.transactionCount > 0 ? merchantData.totalVolume / merchantData.transactionCount : 0;
        stats.feesGenerated = (merchantData.totalVolume * merchantFeeBps) / 10000;
    }

    /**
     * @notice Get invoice details
     * @param invoiceId Invoice identifier
     * @return invoice Invoice structure
     */
    function getInvoice(bytes32 invoiceId) external view returns (Invoice memory invoice) {
        return invoices[invoiceId];
    }

    /**
     * @notice Calculate merchant fee
     * @param amount Payment amount
     * @return fee Fee amount
     */
    function calculateMerchantFee(uint256 amount) public view returns (uint256 fee) {
        return (amount * merchantFeeBps) / 10000;
    }

    /**
     * @notice Initiate fiat offramp for merchant settlement
     * @param merchant Merchant address
     * @param amount Amount to convert
     * @param currency Destination currency
     * @param settlement Settlement preference
     */
    function _initiateFiatOfframp(
        address merchant,
        uint256 amount,
        string memory currency,
        FiatSettlementPreference settlement
    ) private {
        // TODO: Integrate with fiat offramp provider
        // For now, hold VPUSD for manual settlement
        // In production, this would call external API to convert to fiat

        // Temporary: Transfer to offramp provider or hold
        if (fiatOfframpProvider != address(0)) {
            IERC20(address(vpusd)).safeTransfer(fiatOfframpProvider, amount);
        } else {
            // Hold in contract for manual processing
            // Merchant can withdraw later
        }
    }

    /**
     * @notice Set compliance oracle
     * @param _complianceOracle Compliance oracle address
     */
    function setComplianceOracle(address _complianceOracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        complianceOracle = IVPayCompliance(_complianceOracle);
    }

    /**
     * @notice Set fiat offramp provider
     * @param _fiatOfframpProvider Offramp provider address
     */
    function setFiatOfframpProvider(address _fiatOfframpProvider) external onlyRole(DEFAULT_ADMIN_ROLE) {
        fiatOfframpProvider = _fiatOfframpProvider;
    }

    /**
     * @notice Update merchant fee
     * @param _merchantFeeBps New merchant fee in basis points
     */
    function setMerchantFee(uint256 _merchantFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_merchantFeeBps <= MAX_MERCHANT_FEE, "Fee too high");
        merchantFeeBps = _merchantFeeBps;
    }

    /**
     * @notice Verify a merchant manually
     * @param merchant Merchant address
     * @param verified Verification status
     */
    function setMerchantVerification(address merchant, bool verified) external onlyRole(MERCHANT_MANAGER_ROLE) {
        require(merchants[merchant].wallet != address(0), "Merchant not found");
        merchants[merchant].verified = verified;
    }

    /**
     * @notice Pause all operations
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
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
