//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_eUSD_crvUSD is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x67D11005AF05Bb1e9fDb1CFc261C23DE3E1055a1);
    address gauge = address(0x71D97aEEEfe4715E05354D009B8B7a77c325CC2d);
    address rsr = address(0xCa5Ca9083702c56b481D1eec86F1776FDbd2e594);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address eusd = address(0x12275DCB9048680c4Be40942eA4D92c74C63b844);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      rsr,
      eusd,
      underlying,
      0,
      2,
      true
    );
    rewardTokens = [rsr, arb];
  }
}
