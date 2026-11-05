//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultV2Strategy.sol";

contract MorphoVaultStrategyMainnet_GPREM_USDG_V2 is MorphoVaultV2Strategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x004B506865409877C9fA29bfb1ebA929984B9bbC);
    address morphoVault = address(0x390c1bb01F3F627144a40617e287d4cE3D5aBCfa);
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
}
