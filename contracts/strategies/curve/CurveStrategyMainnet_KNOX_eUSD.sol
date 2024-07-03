//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_KNOX_eUSD is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6f33daF91d2aCAe10F5CD7BbE3f31716Ed123F1D);
    address gauge = address(0x63254954b617493bB9311C9f89B50425943B05F6);
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
      1,
      2,
      true
    );
    rewardTokens = [rsr, arb];
  }
}
