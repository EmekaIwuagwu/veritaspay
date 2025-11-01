// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IVeritasPayUSD.sol";
import "./interfaces/IVPayCompliance.sol";

/**
 * @title VeritasPayUSD
 * @notice Cross-border payment stablecoin with hybrid collateralization
 * @dev Implements ERC-20, ERC-2612 (Permit), and payment-specific extensions
 *
 * Features:
 * - Payment tracking with metadata
 * - Batch payments for payroll/remittances
 * - Scheduled payments
 * - Compliance integration (KYC/AML)
 * - Account freezing for regulatory compliance
 * - Tiered fee structure
 * - Upgradeable via UUPS proxy
 */
contract VeritasPayUSD is
    Initializable,
    ERC20Upgradeable,
    ERC20PermitUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    IVeritasPayUSD
{
    /// @notice Role for minting and burning (vault contract)
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role for compliance operations (freezing accounts)
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Compliance oracle contract
    IVPayCompliance public complianceOracle;

    /// @notice Payment tracking
    mapping(bytes32 => Payment) private payments;

    /// @notice Scheduled payments
    mapping(bytes32 => Payment) private scheduledPayments;

    /// @notice Frozen accounts
    mapping(address => bool) private frozenAccounts;

    /// @notice Payment counter for generating unique IDs
    uint256 private paymentCounter;

    /// @notice Fee configuration (in basis points)
    uint256 public basePaymentFeeBps; // 0.1% = 10 bps
    uint256 public constant MAX_FEE_BPS = 100; // 1% maximum

    /// @notice Fee collector address
    address public feeCollector;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Admin address
     * @param _feeCollector Fee collector address
     * @param _basePaymentFeeBps Base payment fee in basis points
     */
    function initialize(address admin, address _feeCollector, uint256 _basePaymentFeeBps) external initializer {
        require(admin != address(0), "Invalid admin");
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_basePaymentFeeBps <= MAX_FEE_BPS, "Fee too high");

        __ERC20_init("VeritasPay USD", "VPUSD");
        __ERC20Permit_init("VeritasPay USD");
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);

        feeCollector = _feeCollector;
        basePaymentFeeBps = _basePaymentFeeBps;
    }

    /**
     * @notice Transfer tokens with payment metadata
     * @param to Recipient address
     * @param amount Amount to transfer
     * @param invoiceData Invoice metadata
     * @return paymentId Unique payment identifier
     */
    function payWithMetadata(address to, uint256 amount, bytes calldata invoiceData)
        external
        whenNotPaused
        returns (bytes32 paymentId)
    {
        require(!isFrozen(msg.sender), "Sender frozen");
        require(!isFrozen(to), "Recipient frozen");
        require(isAddressCompliant(msg.sender), "Sender not compliant");
        require(isAddressCompliant(to), "Recipient not compliant");

        // Generate unique payment ID
        paymentCounter++;
        paymentId = keccak256(abi.encodePacked(msg.sender, to, amount, block.timestamp, paymentCounter));

        // Decode invoice data
        (bytes32 invoiceId, string memory currency) = abi.decode(invoiceData, (bytes32, string));

        // Calculate and collect fee
        uint256 fee = calculatePaymentFee(amount);
        uint256 netAmount = amount - fee;

        // Transfer tokens
        _transfer(msg.sender, to, netAmount);
        if (fee > 0) {
            _transfer(msg.sender, feeCollector, fee);
        }

        // Store payment data
        payments[paymentId] = Payment({
            sender: msg.sender,
            recipient: to,
            amount: amount,
            timestamp: block.timestamp,
            invoiceId: invoiceId,
            currency: currency,
            status: PaymentStatus.COMPLETED
        });

        emit PaymentProcessed(paymentId, msg.sender, to, amount, invoiceId, currency);
    }

    /**
     * @notice Batch transfer to multiple recipients
     * @param recipients Array of recipient addresses
     * @param amounts Array of amounts (must match recipients length)
     */
    function batchPay(address[] calldata recipients, uint256[] calldata amounts) external whenNotPaused {
        require(recipients.length == amounts.length, "Length mismatch");
        require(recipients.length > 0, "Empty arrays");
        require(!isFrozen(msg.sender), "Sender frozen");
        require(isAddressCompliant(msg.sender), "Sender not compliant");

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "Invalid recipient");
            require(amounts[i] > 0, "Invalid amount");
            require(!isFrozen(recipients[i]), "Recipient frozen");
            require(isAddressCompliant(recipients[i]), "Recipient not compliant");

            uint256 fee = calculatePaymentFee(amounts[i]);
            uint256 netAmount = amounts[i] - fee;

            _transfer(msg.sender, recipients[i], netAmount);
            if (fee > 0) {
                _transfer(msg.sender, feeCollector, fee);
            }

            totalAmount += amounts[i];
        }

        emit BatchPayment(msg.sender, recipients.length, totalAmount);
    }

    /**
     * @notice Schedule a payment for future execution
     * @param to Recipient address
     * @param amount Amount to transfer
     * @param executeAt Timestamp when payment should execute
     * @return paymentId Unique payment identifier
     */
    function scheduledPayment(address to, uint256 amount, uint256 executeAt)
        external
        whenNotPaused
        returns (bytes32 paymentId)
    {
        require(executeAt > block.timestamp, "Invalid execution time");
        require(!isFrozen(msg.sender), "Sender frozen");
        require(!isFrozen(to), "Recipient frozen");
        require(isAddressCompliant(msg.sender), "Sender not compliant");
        require(isAddressCompliant(to), "Recipient not compliant");

        // Lock the funds by transferring to this contract
        _transfer(msg.sender, address(this), amount);

        // Generate unique payment ID
        paymentCounter++;
        paymentId = keccak256(abi.encodePacked(msg.sender, to, amount, executeAt, paymentCounter));

        // Store scheduled payment
        scheduledPayments[paymentId] = Payment({
            sender: msg.sender,
            recipient: to,
            amount: amount,
            timestamp: executeAt,
            invoiceId: bytes32(0),
            currency: "",
            status: PaymentStatus.PENDING
        });

        emit ScheduledPayment(paymentId, to, amount, executeAt);
    }

    /**
     * @notice Execute a scheduled payment
     * @param paymentId Payment identifier
     */
    function executeScheduledPayment(bytes32 paymentId) external whenNotPaused {
        Payment storage payment = scheduledPayments[paymentId];
        require(payment.status == PaymentStatus.PENDING, "Invalid payment");
        require(block.timestamp >= payment.timestamp, "Too early");
        require(!isFrozen(payment.sender), "Sender frozen");
        require(!isFrozen(payment.recipient), "Recipient frozen");

        payment.status = PaymentStatus.COMPLETED;

        uint256 fee = calculatePaymentFee(payment.amount);
        uint256 netAmount = payment.amount - fee;

        _transfer(address(this), payment.recipient, netAmount);
        if (fee > 0) {
            _transfer(address(this), feeCollector, fee);
        }

        emit PaymentProcessed(
            paymentId, payment.sender, payment.recipient, payment.amount, payment.invoiceId, payment.currency
        );
    }

    /**
     * @notice Mint new tokens (only callable by vault)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        require(!isFrozen(to), "Recipient frozen");
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burn(address from, uint256 amount) external {
        require(
            msg.sender == from || hasRole(MINTER_ROLE, msg.sender) || allowance(from, msg.sender) >= amount,
            "Unauthorized"
        );
        _burn(from, amount);
    }

    /**
     * @notice Check if an address is compliant (KYC/AML)
     * @param user Address to check
     * @return compliant True if compliant
     */
    function isAddressCompliant(address user) public view returns (bool compliant) {
        if (address(complianceOracle) == address(0)) {
            return true; // No compliance check if oracle not set
        }
        return complianceOracle.isVerified(user) && !complianceOracle.isSanctioned(user);
    }

    /**
     * @notice Freeze an account for regulatory compliance
     * @param user Address to freeze
     * @param reason Reason for freezing
     */
    function freezeAccount(address user, string calldata reason) external onlyRole(COMPLIANCE_ROLE) {
        frozenAccounts[user] = true;
        emit AccountFrozen(user, reason);
    }

    /**
     * @notice Unfreeze a previously frozen account
     * @param user Address to unfreeze
     */
    function unfreezeAccount(address user) external onlyRole(COMPLIANCE_ROLE) {
        frozenAccounts[user] = false;
        emit AccountUnfrozen(user);
    }

    /**
     * @notice Check if an account is frozen
     * @param user Address to check
     * @return frozen True if frozen
     */
    function isFrozen(address user) public view returns (bool frozen) {
        return frozenAccounts[user];
    }

    /**
     * @notice Get payment details
     * @param paymentId Payment identifier
     * @return payment Payment structure
     */
    function getPayment(bytes32 paymentId) external view returns (Payment memory payment) {
        payment = payments[paymentId];
        if (payment.sender == address(0)) {
            payment = scheduledPayments[paymentId];
        }
    }

    /**
     * @notice Calculate payment fee based on amount (tiered structure)
     * @param amount Payment amount
     * @return fee Fee amount
     */
    function calculatePaymentFee(uint256 amount) public view returns (uint256 fee) {
        // Tiered fee structure:
        // < $100: 0.1%
        // $100 - $10,000: 0.05%
        // > $10,000: 0.03%

        if (amount < 100e18) {
            return (amount * basePaymentFeeBps) / 10000;
        } else if (amount < 10000e18) {
            return (amount * (basePaymentFeeBps / 2)) / 10000;
        } else {
            return (amount * (basePaymentFeeBps * 3 / 10)) / 10000;
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
     * @notice Update fee collector
     * @param _feeCollector New fee collector address
     */
    function setFeeCollector(address _feeCollector) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feeCollector != address(0), "Invalid address");
        feeCollector = _feeCollector;
    }

    /**
     * @notice Update base payment fee
     * @param _basePaymentFeeBps New base payment fee in basis points
     */
    function setBasePaymentFee(uint256 _basePaymentFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_basePaymentFeeBps <= MAX_FEE_BPS, "Fee too high");
        basePaymentFeeBps = _basePaymentFeeBps;
    }

    /**
     * @notice Pause all operations
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause all operations
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Override transfer to enforce frozen account checks
     */
    function _update(address from, address to, uint256 amount) internal override {
        require(!isFrozen(from), "Sender frozen");
        require(!isFrozen(to), "Recipient frozen");
        super._update(from, to, amount);
    }

    /**
     * @notice Authorize contract upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
