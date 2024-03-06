//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IPendleStaking {
    function harvestMarketReward(address _market, address _caller, uint256 _minEthRecive) external;
}