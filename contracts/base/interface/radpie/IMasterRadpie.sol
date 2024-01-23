//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IMasterRadpie {
    function multiclaim(address[] calldata _stakingTokens) external;
}