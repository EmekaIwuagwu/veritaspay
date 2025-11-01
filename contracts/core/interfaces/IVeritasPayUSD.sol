// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IVeritasPayUSD
 * @notice Interface for the VeritasPay USD stablecoin with payment extensions
 * @dev Extends ERC-20 with payment-specific functionality
 */
interface IVeritasPayUSD is IERC20 {
    /**
     * @notice Payment status enumeration
     */
    enum PaymentStatus {
        PENDING,
        COMPLETED,
        FAILED,
        REFUNDED
    }

    /**
     * @notice Payment structure for tracking cross-border transactions
     */
    struct Payment {
        address sender;
        address recipient;
        uint256 amount;
        uint256 timestamp;
        bytes32 invoiceId;
        string currency;
        PaymentStatus status;
    }

    /**
     * @notice Emitted when a payment is processed with metadata
     */
    event PaymentProcessed(
        bytes32 indexed paymentId,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        bytes32 invoiceId,
        string currency
    );

    /**
     * @notice Emitted when a batch payment is executed
     */
    event BatchPayment(address indexed sender, uint256 recipientCount, uint256 totalAmount);

    /**
     * @notice Emitted when a scheduled payment is created
     */
    event ScheduledPayment(bytes32 indexed paymentId, address indexed recipient, uint256 amount, uint256 executeAt);

    /**
     * @notice Emitted when an account is frozen for compliance
     */
    event AccountFrozen(address indexed account, string reason);

    /**
     * @notice Emitted when an account is unfrozen
     */
    event AccountUnfrozen(address indexed account);

    /**
     * @notice Transfer tokens with payment metadata
     * @param to Recipient address
     * @param amount Amount to transfer
     * @param invoiceData Invoice metadata
     * @return paymentId Unique payment identifier
     */
    function payWithMetadata(address to, uint256 amount, bytes calldata invoiceData)
        external
        returns (bytes32 paymentId);

    /**
     * @notice Batch transfer to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts (must match recipients length)
     */
    function batchPay(address[] calldata recipients, uint256[] calldata amounts) external;

    /**
     * @notice Schedule a payment for future execution
     * @param to Recipient address
     * @param amount Amount to transfer
     * @param executeAt Timestamp when payment should execute
     * @return paymentId Unique payment identifier
     */
    function scheduledPayment(address to, uint256 amount, uint256 executeAt) external returns (bytes32 paymentId);

    /**
     * @notice Execute a scheduled payment
     * @param paymentId Payment identifier
     */
    function executeScheduledPayment(bytes32 paymentId) external;

    /**
     * @notice Mint new tokens (only callable by vault)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn tokens
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Check if an address is compliant (KYC/AML)
     * @param user Address to check
     * @return compliant True if compliant
     */
    function isAddressCompliant(address user) external view returns (bool compliant);

    /**
     * @notice Freeze an account for regulatory compliance
     * @param user Address to freeze
     * @param reason Reason for freezing
     */
    function freezeAccount(address user, string calldata reason) external;

    /**
     * @notice Unfreeze a previously frozen account
     * @param user Address to unfreeze
     */
    function unfreezeAccount(address user) external;

    /**
     * @notice Check if an account is frozen
     * @param user Address to check
     * @return frozen True if frozen
     */
    function isFrozen(address user) external view returns (bool frozen);

    /**
     * @notice Get payment details
     * @param paymentId Payment identifier
     * @return payment Payment structure
     */
    function getPayment(bytes32 paymentId) external view returns (Payment memory payment);

    /**
     * @notice Calculate payment fee based on amount
     * @param amount Payment amount
     * @return fee Fee amount
     */
    function calculatePaymentFee(uint256 amount) external view returns (uint256 fee);
}
