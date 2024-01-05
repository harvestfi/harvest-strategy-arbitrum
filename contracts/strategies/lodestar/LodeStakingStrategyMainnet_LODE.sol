//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./LodeStakingStrategy.sol";

contract LodeStakingStrategyMainnet_LODE is LodeStakingStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address rewardPool = address(0x8ab1774A6FC5eE51559964e13ECD54155340c116);
    LodeStakingStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      weth
    );
    rewardTokens = [weth];
  }
}
