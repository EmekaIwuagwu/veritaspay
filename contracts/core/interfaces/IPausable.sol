// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IPausable
 * @notice Interface for contracts that can be paused
 */
interface IPausable {
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);
}
