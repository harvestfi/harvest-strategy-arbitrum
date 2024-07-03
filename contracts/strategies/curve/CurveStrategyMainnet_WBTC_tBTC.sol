//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_WBTC_tBTC is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x186cF879186986A20aADFb7eAD50e3C20cb26CeC);
    address gauge = address(0xB7e23A438C9cad2575d3C048248A943a7a03f3fA);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address wbtc = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      arb,
      wbtc,
      underlying,
      0,
      2,
      true
    );
    rewardTokens = [arb];
  }
}
