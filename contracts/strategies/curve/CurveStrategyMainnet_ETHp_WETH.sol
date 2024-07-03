//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_ETHp_WETH is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x95F425c7d730Eb7673fca272c2c305f48Ed546c3);
    address gauge = address(0xB224cf7c17dB373EceF550CF957B8a4dD40C8109);
    address rsr = address(0xCa5Ca9083702c56b481D1eec86F1776FDbd2e594);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      weth,
      weth,
      underlying,
      1,
      2,
      true
    );
    rewardTokens = [rsr, arb];
  }
}
