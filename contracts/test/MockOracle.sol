// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title MockOracle
 * @notice Simplified Chainlink oracle for testing
 */
contract MockOracle is AggregatorV3Interface {
    int256 private _price;
    uint8 private _decimals;
    string private _description;
    uint256 private _version;

    constructor(
        string memory description_,
        uint8 decimals_,
        int256 initialPrice
    ) {
        _description = description_;
        _decimals = decimals_;
        _price = initialPrice;
        _version = 1;
    }

    function setPrice(int256 price) external {
        _price = price;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external view override returns (uint256) {
        return _version;
    }

    function getRoundData(
        uint80 _roundId
    )
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, block.timestamp, block.timestamp, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }
}
