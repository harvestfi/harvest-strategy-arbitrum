//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_TriCRV_ARB is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x845C8bc94610807fCbaB5dd2bc7aC9DAbaFf3c55);
    address gauge = address(0xB08FEf57bFcc5f7bF0EF69C0c090849d497C8F8A);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      arb,
      arb,
      underlying,
      1,
      3,
      false
    );
    rewardTokens = [arb];
  }
}
