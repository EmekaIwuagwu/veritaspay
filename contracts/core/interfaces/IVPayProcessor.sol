// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVPayProcessor
 * @notice Interface for merchant payment processing and settlement
 */
interface IVPayProcessor {
    /**
     * @notice Fiat settlement preference enumeration
     */
    enum FiatSettlementPreference {
        CRYPTO, // Receive in VPUSD
        FIAT_INSTANT, // Convert to fiat immediately
        FIAT_DAILY, // Batch daily settlement
        FIAT_WEEKLY // Batch weekly settlement
    }

    /**
     * @notice Invoice status enumeration
     */
    enum InvoiceStatus {
        PENDING,
        PAID,
        EXPIRED,
        CANCELLED
    }

    /**
     * @notice Merchant information structure
     */
    struct Merchant {
        address wallet;
        string businessName;
        string country;
        bool verified;
        uint256 totalVolume;
        uint256 transactionCount;
        FiatSettlementPreference settlement;
    }

    /**
     * @notice Invoice structure
     */
    struct Invoice {
        address merchant;
        uint256 amount;
        string currency;
        uint256 createdAt;
        uint256 expiresAt;
        InvoiceStatus status;
    }

    /**
     * @notice Merchant statistics structure
     */
    struct MerchantStats {
        uint256 totalVolume;
        uint256 transactionCount;
        uint256 averageTransaction;
        uint256 feesGenerated;
    }

    /**
     * @notice Emitted when a merchant is registered
     */
    event MerchantRegistered(
        address indexed merchant,
        string businessName,
        string country
    );

    /**
     * @notice Emitted when a payment is processed
     */
    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed payer,
        address indexed merchant,
        uint256 amount,
        bytes32 invoiceId,
        uint256 fee
    );

    /**
     * @notice Emitted when batch payments are executed
     */
    event BatchPaymentsExecuted(
        address indexed sender,
        uint256 recipientCount,
        uint256 totalAmount,
        string purpose
    );

    /**
     * @notice Emitted when an invoice is created
     */
    event InvoiceCreated(
        bytes32 indexed invoiceId,
        address indexed merchant,
        uint256 amount,
        string currency
    );

    /**
     * @notice Emitted when an invoice is paid
     */
    event InvoicePaid(
        bytes32 indexed invoiceId,
        address indexed payer,
        uint256 amount
    );

    /**
     * @notice Emitted when a fiat settlement is initiated
     */
    event SettlementInitiated(
        address indexed merchant,
        uint256 amount,
        string currency,
        FiatSettlementPreference settlement
    );

    /**
     * @notice Register as a merchant
     * @param businessName Business name
     * @param country Country code
     * @param settlement Settlement preference
     */
    function registerMerchant(
        string calldata businessName,
        string calldata country,
        FiatSettlementPreference settlement
    ) external;

    /**
     * @notice Process a payment to a merchant
     * @param merchant Merchant address
     * @param amount Payment amount
     * @param invoiceId Invoice identifier
     * @param currency Destination currency
     * @return paymentId Unique payment identifier
     */
    function processPayment(
        address merchant,
        uint256 amount,
        bytes32 invoiceId,
        string calldata currency
    ) external returns (bytes32 paymentId);

    /**
     * @notice Execute batch payments (payroll/remittances)
     * @param recipients Array of recipient addresses
     * @param amounts Array of payment amounts
     * @param purpose Payment purpose
     * @return paymentIds Array of payment identifiers
     */
    function batchPayments(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string calldata purpose
    ) external returns (bytes32[] memory paymentIds);

    /**
     * @notice Create an invoice
     * @param amount Invoice amount
     * @param currency Currency code
     * @param expiresAt Expiration timestamp
     * @return invoiceId Unique invoice identifier
     */
    function createInvoice(
        uint256 amount,
        string calldata currency,
        uint256 expiresAt
    ) external returns (bytes32 invoiceId);

    /**
     * @notice Pay an invoice
     * @param invoiceId Invoice identifier
     */
    function payInvoice(bytes32 invoiceId) external;

    /**
     * @notice Update settlement preference
     * @param preference New settlement preference
     */
    function updateSettlementPreference(
        FiatSettlementPreference preference
    ) external;

    /**
     * @notice Get merchant information
     * @param merchant Merchant address
     * @return merchantInfo Merchant structure
     */
    function getMerchant(
        address merchant
    ) external view returns (Merchant memory merchantInfo);

    /**
     * @notice Get merchant statistics
     * @param merchant Merchant address
     * @return stats Merchant statistics
     */
    function getMerchantStats(
        address merchant
    ) external view returns (MerchantStats memory stats);

    /**
     * @notice Get invoice details
     * @param invoiceId Invoice identifier
     * @return invoice Invoice structure
     */
    function getInvoice(
        bytes32 invoiceId
    ) external view returns (Invoice memory invoice);

    /**
     * @notice Calculate merchant fee
     * @param amount Payment amount
     * @return fee Fee amount
     */
    function calculateMerchantFee(
        uint256 amount
    ) external view returns (uint256 fee);
}
