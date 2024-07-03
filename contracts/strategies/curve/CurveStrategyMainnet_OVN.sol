//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_OVN is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xb34a7d1444a707349Bc7b981B7F2E1f20F81F013);
    address gauge = address(0x4645e6476D3A5595Be9Efd39426cc10586a8393D);
    address ovn = address(0xA3d1a8DEB97B111454B294E2324EfAD13a9d8396);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address usdp = address(0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      weth,
      usdp,
      underlying,
      0,
      2,
      false
    );
    rewardTokens = [ovn, arb, crv];
  }
}
