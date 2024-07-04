//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IBalDex {
    function setFee(address token0, address token1, uint24 fee) external;
    function setPool(address token0, address token1, bytes32 pool) external;
}