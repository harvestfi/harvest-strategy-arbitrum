//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_TriRSR is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x45B47fE1bed067de6B4b89e0285E6B571A64c57C);
    address gauge = address(0xF7205c995b7E5f8F755ecbe7eEbb92eC742633C9);
    address rsr = address(0xCa5Ca9083702c56b481D1eec86F1776FDbd2e594);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      rsr,
      rsr,
      underlying,
      2,
      3,
      false
    );
    rewardTokens = [rsr, arb];
  }
}
