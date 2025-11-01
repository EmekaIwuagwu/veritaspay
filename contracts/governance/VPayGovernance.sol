// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title VPayGovernance
 * @notice Governance and parameter management for VeritasPay protocol
 * @dev Manages system parameters and multi-signature operations
 */
contract VPayGovernance is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    /// @notice Proposal status
    enum ProposalStatus {
        PENDING,
        ACTIVE,
        EXECUTED,
        CANCELLED,
        DEFEATED
    }

    /// @notice Proposal type
    enum ProposalType {
        PARAMETER_CHANGE,
        EMERGENCY_ACTION,
        UPGRADE,
        GENERAL
    }

    /// @notice Proposal structure
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        ProposalType proposalType;
        bytes callData;
        address target;
        uint256 createdAt;
        uint256 votingEndTime;
        uint256 forVotes;
        uint256 againstVotes;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
    }

    /// @notice System parameters
    struct SystemParameters {
        uint256 minReserveRatio;
        uint256 targetReserveRatio;
        uint256 maxDailyMintCap;
        uint256 maxDailyBurnCap;
        uint256 deviationThreshold;
        uint256 basePaymentFee;
        uint256 bridgeFeePercentage;
        uint256 merchantFee;
    }

    /// @notice Roles
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice System parameters
    SystemParameters public systemParameters;

    /// @notice Proposals
    mapping(uint256 => Proposal) public proposals;
    uint256 public proposalCount;

    /// @notice Multi-signature configuration
    uint256 public requiredSignatures;
    uint256 public totalSigners;
    mapping(address => bool) public isValidSigner;

    /// @notice Voting period
    uint256 public votingPeriod;

    /// @notice Proposal threshold (percentage of total supply needed)
    uint256 public proposalThreshold;

    /// @notice Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        ProposalType proposalType,
        uint256 votingEndTime
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event ParameterChanged(string parameterName, uint256 oldValue, uint256 newValue);
    event EmergencyActionExecuted(string action, address executor);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param admin Admin address
     * @param signers Array of multi-sig signers
     * @param _requiredSignatures Required signatures for emergency actions
     */
    function initialize(address admin, address[] memory signers, uint256 _requiredSignatures) external initializer {
        require(admin != address(0), "Invalid admin");
        require(signers.length >= _requiredSignatures, "Invalid signer count");
        require(_requiredSignatures > 0, "Invalid required signatures");

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(UPGRADER_ROLE, admin);
        _grantRole(PROPOSER_ROLE, admin);
        _grantRole(EXECUTOR_ROLE, admin);

        // Set up multi-sig
        requiredSignatures = _requiredSignatures;
        totalSigners = signers.length;
        for (uint256 i = 0; i < signers.length; i++) {
            isValidSigner[signers[i]] = true;
        }

        // Default parameters
        votingPeriod = 3 days;
        proposalThreshold = 100; // 1%

        // Initialize system parameters with defaults
        systemParameters = SystemParameters({
            minReserveRatio: 15000, // 150%
            targetReserveRatio: 17500, // 175%
            maxDailyMintCap: 500, // 5%
            maxDailyBurnCap: 500, // 5%
            deviationThreshold: 200, // 2%
            basePaymentFee: 10, // 0.1%
            bridgeFeePercentage: 5, // 0.05%
            merchantFee: 30 // 0.3%
        });
    }

    /**
     * @notice Create a proposal
     * @param description Proposal description
     * @param proposalType Type of proposal
     * @param target Target contract address
     * @param callData Encoded function call
     * @return proposalId Proposal ID
     */
    function propose(string calldata description, ProposalType proposalType, address target, bytes calldata callData)
        external
        onlyRole(PROPOSER_ROLE)
        returns (uint256 proposalId)
    {
        proposalId = ++proposalCount;

        Proposal storage proposal = proposals[proposalId];
        proposal.id = proposalId;
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.proposalType = proposalType;
        proposal.callData = callData;
        proposal.target = target;
        proposal.createdAt = block.timestamp;
        proposal.votingEndTime = block.timestamp + votingPeriod;
        proposal.status = ProposalStatus.ACTIVE;

        emit ProposalCreated(proposalId, msg.sender, description, proposalType, proposal.votingEndTime);
    }

    /**
     * @notice Cast a vote on a proposal
     * @param proposalId Proposal ID
     * @param support True for yes, false for no
     */
    function castVote(uint256 proposalId, bool support) external {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.ACTIVE, "Proposal not active");
        require(block.timestamp <= proposal.votingEndTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");
        require(isValidSigner[msg.sender], "Not a valid voter");

        proposal.hasVoted[msg.sender] = true;

        if (support) {
            proposal.forVotes += 1;
        } else {
            proposal.againstVotes += 1;
        }

        emit VoteCast(proposalId, msg.sender, support, 1);
    }

    /**
     * @notice Execute a proposal
     * @param proposalId Proposal ID
     */
    function executeProposal(uint256 proposalId) external onlyRole(EXECUTOR_ROLE) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.ACTIVE, "Proposal not active");
        require(block.timestamp > proposal.votingEndTime, "Voting not ended");

        // Check if proposal passed (simple majority)
        if (proposal.forVotes > proposal.againstVotes && proposal.forVotes >= requiredSignatures) {
            proposal.status = ProposalStatus.EXECUTED;

            // Execute the proposal
            if (proposal.target != address(0)) {
                (bool success,) = proposal.target.call(proposal.callData);
                require(success, "Execution failed");
            }

            emit ProposalExecuted(proposalId);
        } else {
            proposal.status = ProposalStatus.DEFEATED;
        }
    }

    /**
     * @notice Cancel a proposal
     * @param proposalId Proposal ID
     */
    function cancelProposal(uint256 proposalId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.ACTIVE, "Proposal not active");

        proposal.status = ProposalStatus.CANCELLED;
        emit ProposalCancelled(proposalId);
    }

    /**
     * @notice Update a system parameter
     * @param paramName Parameter name
     * @param newValue New value
     */
    function updateParameter(string calldata paramName, uint256 newValue) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldValue;

        if (keccak256(bytes(paramName)) == keccak256(bytes("minReserveRatio"))) {
            oldValue = systemParameters.minReserveRatio;
            systemParameters.minReserveRatio = newValue;
        } else if (keccak256(bytes(paramName)) == keccak256(bytes("targetReserveRatio"))) {
            oldValue = systemParameters.targetReserveRatio;
            systemParameters.targetReserveRatio = newValue;
        } else if (keccak256(bytes(paramName)) == keccak256(bytes("maxDailyMintCap"))) {
            oldValue = systemParameters.maxDailyMintCap;
            systemParameters.maxDailyMintCap = newValue;
        } else if (keccak256(bytes(paramName)) == keccak256(bytes("maxDailyBurnCap"))) {
            oldValue = systemParameters.maxDailyBurnCap;
            systemParameters.maxDailyBurnCap = newValue;
        } else if (keccak256(bytes(paramName)) == keccak256(bytes("deviationThreshold"))) {
            oldValue = systemParameters.deviationThreshold;
            systemParameters.deviationThreshold = newValue;
        } else if (keccak256(bytes(paramName)) == keccak256(bytes("basePaymentFee"))) {
            oldValue = systemParameters.basePaymentFee;
            systemParameters.basePaymentFee = newValue;
        } else if (keccak256(bytes(paramName)) == keccak256(bytes("bridgeFeePercentage"))) {
            oldValue = systemParameters.bridgeFeePercentage;
            systemParameters.bridgeFeePercentage = newValue;
        } else if (keccak256(bytes(paramName)) == keccak256(bytes("merchantFee"))) {
            oldValue = systemParameters.merchantFee;
            systemParameters.merchantFee = newValue;
        } else {
            revert("Invalid parameter");
        }

        emit ParameterChanged(paramName, oldValue, newValue);
    }

    /**
     * @notice Emergency pause (requires multi-sig)
     * @param target Target contract to pause
     */
    function emergencyPause(address target) external {
        require(isValidSigner[msg.sender], "Not a signer");
        // In production, this would require multi-sig confirmation
        emit EmergencyActionExecuted("pause", msg.sender);
    }

    /**
     * @notice Add a signer to multi-sig
     * @param signer Signer address
     */
    function addSigner(address signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!isValidSigner[signer], "Already signer");
        isValidSigner[signer] = true;
        totalSigners++;
    }

    /**
     * @notice Remove a signer from multi-sig
     * @param signer Signer address
     */
    function removeSigner(address signer) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isValidSigner[signer], "Not a signer");
        require(totalSigners > requiredSignatures, "Cannot remove, would break multi-sig");
        isValidSigner[signer] = false;
        totalSigners--;
    }

    /**
     * @notice Update required signatures
     * @param _requiredSignatures New required signatures
     */
    function updateRequiredSignatures(uint256 _requiredSignatures) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_requiredSignatures > 0 && _requiredSignatures <= totalSigners, "Invalid required signatures");
        requiredSignatures = _requiredSignatures;
    }

    /**
     * @notice Update voting period
     * @param _votingPeriod New voting period
     */
    function updateVotingPeriod(uint256 _votingPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_votingPeriod > 0, "Invalid voting period");
        votingPeriod = _votingPeriod;
    }

    /**
     * @notice Get proposal details
     * @param proposalId Proposal ID
     */
    function getProposal(uint256 proposalId)
        external
        view
        returns (
            uint256 id,
            address proposer,
            string memory description,
            ProposalType proposalType,
            uint256 forVotes,
            uint256 againstVotes,
            ProposalStatus status
        )
    {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.description,
            proposal.proposalType,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.status
        );
    }

    /**
     * @notice Authorize contract upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}
