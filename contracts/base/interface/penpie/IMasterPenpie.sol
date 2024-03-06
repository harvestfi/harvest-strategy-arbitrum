//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IMasterPenpie {
    function multiclaim(address[] calldata _stakingTokens) external;
}