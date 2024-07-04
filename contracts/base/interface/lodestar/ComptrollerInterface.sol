// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.6.12;

interface ComptrollerInterface {
    /*** Assets You Are In ***/

    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);

    function claimComp(address holder) external;
    function borrowCaps(address cToken) external view returns (uint256);
    function supplyCaps(address cToken) external view returns (uint256);
}