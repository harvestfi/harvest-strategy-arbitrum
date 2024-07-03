//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_eUSD_USDC is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x93a416206B4ae3204cFE539edfeE6BC05a62963e);
    address gauge = address(0xad85FB8A5eD9E2f338d2798A9eEF176D31cA6A57);
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
