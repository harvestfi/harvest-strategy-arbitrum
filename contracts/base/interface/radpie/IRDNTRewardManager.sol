//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IRDNTRewardManager {
    function entitledRDNT(address _account) external view returns (uint256);

    function redeemEntitledRDNT() external;
}