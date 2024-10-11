// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./IMarket.sol";

interface IReader {
    function getMarket(address dataStore, address key) external view returns (IMarket.Props memory);
}