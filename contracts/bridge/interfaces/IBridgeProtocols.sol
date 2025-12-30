// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ILayerZeroEndpoint
 * @notice Minimal interface for LayerZero cross-chain messaging
 */
interface ILayerZeroEndpoint {
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;

    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint256 nativeFee, uint256 zroFee);
}

/**
 * @title IAxelarGateway
 * @notice Minimal interface for Axelar cross-chain messaging
 */
interface IAxelarGateway {
    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external;

    function callContractWithToken(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload,
        string calldata symbol,
        uint256 amount
    ) external;
}

/**
 * @title IWormholeRelayer
 * @notice Minimal interface for Wormhole cross-chain messaging
 */
interface IWormholeRelayer {
    function sendPayloadToEvm(
        uint16 targetChain,
        address targetAddress,
        bytes memory payload,
        uint256 receiverValue,
        uint256 gasLimit
    ) external payable returns (uint64 sequence);

    function quoteDeliveryPrice(
        uint16 targetChain,
        uint256 receiverValue,
        uint256 gasLimit
    ) external view returns (uint256 nativePriceQuote);
}

/**
 * @title ICCIPRouter
 * @notice Minimal interface for Chainlink CCIP
 */
interface ICCIPRouter {
    struct EVM2AnyMessage {
        bytes receiver;
        bytes data;
        address[] tokenAmounts;
        address feeToken;
        bytes extraArgs;
    }

    function ccipSend(
        uint64 destinationChainSelector,
        EVM2AnyMessage calldata message
    ) external payable returns (bytes32 messageId);

    function getFee(
        uint64 destinationChainSelector,
        EVM2AnyMessage calldata message
    ) external view returns (uint256 fee);
}
