//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IRadpieReceiptToken {
    function underlying() external view returns (address);
    function masterRadpie() external view returns (address);
    function balanceOf(address _account) external view returns (uint256);
}