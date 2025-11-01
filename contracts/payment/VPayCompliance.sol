// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../core/interfaces/IVPayCompliance.sol";

/**
 * @title VPayCompliance
 * @notice KYC/AML compliance and regulatory features
 * @dev Integrates with external compliance providers and maintains sanction lists
 */
contract VPayCompliance is Initializable, AccessControlUpgradeable, UUPSUpgradeable, IVPayCompliance {
    /// @notice Role for compliance operations
    bytes32 public constant COMPLIANCE_OFFICER_ROLE = keccak256("COMPLIANCE_OFFICER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice User verification status
    mapping(address => VerificationStatus) public verificationStatus;

    /// @notice User risk scores (0-100)
    mapping(address => uint8) public riskScores;

    /// @notice Sanctioned addresses
    mapping(address => bool) public sanctionedAddresses;

    /// @notice Sanction reasons
    mapping(address => string) public sanctionReasons;

    /// @notice Flagged transactions
    mapping(bytes32 => string) public flaggedTransactions;

    /// @notice Transaction history for reporting
    struct TransactionRecord {
        address sender;
        address recipient;
        uint256 amount;
        uint256 timestamp;
        uint8 riskScore;
    }

    TransactionRecord[] public transactionHistory;

    /// @notice Risk thresholds
    uint8 public constant HIGH_RISK_THRESHOLD = 70;
    uint8 public constant MEDIUM_RISK_THRESHOLD = 40;

    /// @notice Large transaction threshold (for monitoring)
    uint256 public largeTransactionThreshold;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Admin address
     * @param _largeTransactionThreshold Large transaction threshold
     */
    function initialize(address admin, uint256 _largeTransactionThreshold) external initializer {
        require(admin != address(0), "Invalid admin");

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(COMPLIANCE_OFFICER_ROLE, admin);

        largeTransactionThreshold = _largeTransactionThreshold;
    }

    /**
     * @notice Verify a user (KYC)
     * @param user User address to verify
     * @return success True if verification successful
     */
    function verifyUser(address user) external onlyRole(COMPLIANCE_OFFICER_ROLE) returns (bool success) {
        require(user != address(0), "Invalid address");
        require(!sanctionedAddresses[user], "User is sanctioned");

        verificationStatus[user] = VerificationStatus.VERIFIED;
        riskScores[user] = 20; // Low risk for verified users

        emit UserVerified(user, block.timestamp);
        return true;
    }

    /**
     * @notice Get user's risk score
     * @param user User address
     * @return riskScore Risk score (0-100)
     */
    function getRiskScore(address user) external view returns (uint8 riskScore) {
        return riskScores[user];
    }

    /**
     * @notice Flag a transaction for review
     * @param txId Transaction identifier
     * @param reason Reason for flagging
     */
    function flagTransaction(bytes32 txId, string calldata reason) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        flaggedTransactions[txId] = reason;
        emit TransactionFlagged(txId, address(0), reason, 0);
    }

    /**
     * @notice Check if user is verified
     * @param user User address
     * @return verified True if verified
     */
    function isVerified(address user) external view returns (bool verified) {
        return verificationStatus[user] == VerificationStatus.VERIFIED;
    }

    /**
     * @notice Check if address is sanctioned
     * @param user User address
     * @return sanctioned True if sanctioned
     */
    function isSanctioned(address user) external view returns (bool sanctioned) {
        return sanctionedAddresses[user];
    }

    /**
     * @notice Add address to sanction list
     * @param user User address
     * @param reason Reason for sanction
     */
    function addToSanctionList(address user, string calldata reason) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        require(user != address(0), "Invalid address");

        sanctionedAddresses[user] = true;
        sanctionReasons[user] = reason;

        emit AddressSanctioned(user, reason);
    }

    /**
     * @notice Batch add addresses to sanction list
     * @param users Array of user addresses
     * @param reason Reason for sanctions
     */
    function batchAddToSanctionList(address[] calldata users, string calldata reason)
        external
        onlyRole(COMPLIANCE_OFFICER_ROLE)
    {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Invalid address");
            sanctionedAddresses[users[i]] = true;
            sanctionReasons[users[i]] = reason;
            emit AddressSanctioned(users[i], reason);
        }
    }

    /**
     * @notice Remove address from sanction list
     * @param user User address
     */
    function removeFromSanctionList(address user) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        sanctionedAddresses[user] = false;
        delete sanctionReasons[user];

        emit AddressUnsanctioned(user);
    }

    /**
     * @notice Analyze transaction risk
     * @param sender Sender address
     * @param recipient Recipient address
     * @param amount Transaction amount
     * @return risk Transaction risk assessment
     */
    function analyzeTransaction(address sender, address recipient, uint256 amount)
        external
        view
        returns (TransactionRisk memory risk)
    {
        uint8 riskScore = 0;
        string[] memory flags = new string[](5);
        uint256 flagCount = 0;

        // Check if sender/recipient are sanctioned
        if (sanctionedAddresses[sender]) {
            riskScore += 50;
            flags[flagCount++] = "sender_sanctioned";
        }
        if (sanctionedAddresses[recipient]) {
            riskScore += 50;
            flags[flagCount++] = "recipient_sanctioned";
        }

        // Check if sender/recipient are verified
        if (verificationStatus[sender] != VerificationStatus.VERIFIED) {
            riskScore += 20;
            flags[flagCount++] = "sender_unverified";
        }
        if (verificationStatus[recipient] != VerificationStatus.VERIFIED) {
            riskScore += 20;
            flags[flagCount++] = "recipient_unverified";
        }

        // Check transaction amount
        if (amount >= largeTransactionThreshold) {
            riskScore += 15;
            flags[flagCount++] = "large_transaction";
        }

        // Use existing risk scores
        riskScore += riskScores[sender] / 4;
        riskScore += riskScores[recipient] / 4;

        // Cap at 100
        if (riskScore > 100) {
            riskScore = 100;
        }

        // Resize flags array
        string[] memory finalFlags = new string[](flagCount);
        for (uint256 i = 0; i < flagCount; i++) {
            finalFlags[i] = flags[i];
        }

        risk = TransactionRisk({
            riskScore: riskScore,
            requiresReview: riskScore >= HIGH_RISK_THRESHOLD,
            flags: finalFlags
        });
    }

    /**
     * @notice Record a transaction for audit trail
     * @param sender Sender address
     * @param recipient Recipient address
     * @param amount Transaction amount
     */
    function recordTransaction(address sender, address recipient, uint256 amount) external {
        TransactionRisk memory risk = this.analyzeTransaction(sender, recipient, amount);

        transactionHistory.push(
            TransactionRecord({
                sender: sender,
                recipient: recipient,
                amount: amount,
                timestamp: block.timestamp,
                riskScore: risk.riskScore
            })
        );

        // Flag high-risk transactions
        if (risk.requiresReview) {
            bytes32 txId = keccak256(abi.encodePacked(sender, recipient, amount, block.timestamp));
            flaggedTransactions[txId] = "High risk transaction";
            emit TransactionFlagged(txId, sender, "High risk score", risk.riskScore);
        }
    }

    /**
     * @notice Generate audit report for a time period
     * @param startTime Start timestamp
     * @param endTime End timestamp
     * @return reportData Encoded report data
     */
    function generateAuditReport(uint256 startTime, uint256 endTime) external view returns (bytes memory reportData) {
        uint256 totalTransactions = 0;
        uint256 highRiskCount = 0;
        uint256 totalVolume = 0;

        for (uint256 i = 0; i < transactionHistory.length; i++) {
            TransactionRecord memory record = transactionHistory[i];

            if (record.timestamp >= startTime && record.timestamp <= endTime) {
                totalTransactions++;
                totalVolume += record.amount;

                if (record.riskScore >= HIGH_RISK_THRESHOLD) {
                    highRiskCount++;
                }
            }
        }

        reportData = abi.encode(totalTransactions, highRiskCount, totalVolume, startTime, endTime);
    }

    /**
     * @notice Get transaction history count
     */
    function getTransactionHistoryCount() external view returns (uint256) {
        return transactionHistory.length;
    }

    /**
     * @notice Update user risk score
     * @param user User address
     * @param score Risk score (0-100)
     */
    function updateRiskScore(address user, uint8 score) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        require(score <= 100, "Invalid score");
        riskScores[user] = score;
    }

    /**
     * @notice Update large transaction threshold
     * @param threshold New threshold
     */
    function setLargeTransactionThreshold(uint256 threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        largeTransactionThreshold = threshold;
    }

    /**
     * @notice Batch verify users
     * @param users Array of user addresses
     */
    function batchVerifyUsers(address[] calldata users) external onlyRole(COMPLIANCE_OFFICER_ROLE) {
        for (uint256 i = 0; i < users.length; i++) {
            require(users[i] != address(0), "Invalid address");
            require(!sanctionedAddresses[users[i]], "User is sanctioned");

            verificationStatus[users[i]] = VerificationStatus.VERIFIED;
            riskScores[users[i]] = 20;

            emit UserVerified(users[i], block.timestamp);
        }
    }

    /**
     * @notice Authorize contract upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
