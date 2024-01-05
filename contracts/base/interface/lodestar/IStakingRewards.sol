// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.6.12;

interface IStakingRewards {
    function stakeLODE(uint256 amount, uint256 lockTime) external;
    function unstakeLODE(uint256 amount) external;
    function emergencyStakerWithdrawal() external;
    function claimRewards() external;
    function userInfo(address) external view returns(uint96, int128);
    function LODE() external view returns(address);
}