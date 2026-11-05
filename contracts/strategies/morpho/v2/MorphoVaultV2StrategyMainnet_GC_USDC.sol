//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultV2Strategy.sol";

contract MorphoVaultStrategyMainnet_GC_USDC_V2 is MorphoVaultV2Strategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address morphoVault = address(0x55a2B207b0074E13AdCb858950a81B7a04775E0F);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    MorphoVaultV2Strategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth
    );
    rewardTokens = [arb];
    _setDistributionTime(arb, 172_800); // 48 hours
  }

  // The deployed strategy lists MORPHO as a reward as well. It is no longer handed out
  // here, and it cannot be sold on Arbitrum any more: every swap of it reverts, and takes
  // the hard work with it. An upgrade onto this implementation drops it and leaves the
  // other rewards and their streams as they are. It does so on every upgrade that runs
  // this, so take the override out before MORPHO is ever listed again.
  function finalizeUpgrade() external override onlyGovernance {
    _finalizeUpgrade();
    _removeRewardToken(address(0x40BD670A58238e6E230c430BBb5cE6ec0d40df48));
  }
}
