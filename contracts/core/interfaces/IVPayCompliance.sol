// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVPayCompliance
 * @notice Interface for KYC/AML compliance and regulatory features
 */
interface IVPayCompliance {
    /**
     * @notice Transaction risk assessment structure
     */
    struct TransactionRisk {
        uint8 riskScore; // 0-100
        bool requiresReview;
        string[] flags;
    }

    /**
     * @notice User verification status
     */
    enum VerificationStatus {
        NONE,
        PENDING,
        VERIFIED,
        REJECTED
    }

    /**
     * @notice Emitted when a user is verified
     */
    event UserVerified(address indexed user, uint256 timestamp);

    /**
     * @notice Emitted when a transaction is flagged
     */
    event TransactionFlagged(bytes32 indexed txId, address indexed user, string reason, uint8 riskScore);

    /**
     * @notice Emitted when an address is added to sanction list
     */
    event AddressSanctioned(address indexed user, string reason);

    /**
     * @notice Emitted when an address is removed from sanction list
     */
    event AddressUnsanctioned(address indexed user);

    /**
     * @notice Verify a user (KYC)
     * @param user User address to verify
     * @return success True if verification successful
     */
    function verifyUser(address user) external returns (bool success);

    /**
     * @notice Get user's risk score
     * @param user User address
     * @return riskScore Risk score (0-100)
     */
    function getRiskScore(address user) external view returns (uint8 riskScore);

    /**
     * @notice Flag a transaction for review
     * @param txId Transaction identifier
     * @param reason Reason for flagging
     */
    function flagTransaction(bytes32 txId, string calldata reason) external;

    /**
     * @notice Check if user is verified
     * @param user User address
     * @return verified True if verified
     */
    function isVerified(address user) external view returns (bool verified);

    /**
     * @notice Check if address is sanctioned
     * @param user User address
     * @return sanctioned True if sanctioned
     */
    function isSanctioned(address user) external view returns (bool sanctioned);

    /**
     * @notice Add address to sanction list
     * @param user User address
     * @param reason Reason for sanction
     */
    function addToSanctionList(address user, string calldata reason) external;

    /**
     * @notice Remove address from sanction list
     * @param user User address
     */
    function removeFromSanctionList(address user) external;

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
        returns (TransactionRisk memory risk);

    /**
     * @notice Generate audit report for a time period
     * @param startTime Start timestamp
     * @param endTime End timestamp
     * @return reportData Encoded report data
     */
    function generateAuditReport(uint256 startTime, uint256 endTime) external view returns (bytes memory reportData);
}
