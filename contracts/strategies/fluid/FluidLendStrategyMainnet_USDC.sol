//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./FluidLendStrategy.sol";

contract FluidLendStrategyMainnet_USDC is FluidLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address fToken = address(0x1A996cb54bb95462040408C06122D45D6Cdb6096);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    FluidLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      fToken,
      weth
    );
  }

  function finalizeUpgrade() override external onlyGovernance {
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    _setRewardToken(arb);
    rewardTokens = [arb];
    distributionTime[arb] = 86400;
    _finalizeUpgrade();
  }
}