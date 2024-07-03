//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_OVN_stable is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x1446999B0b0E4f7aDA6Ee73f2Ae12a2cfdc5D9E7);
    address gauge = address(0xd68089D9dAa2da7888B7Ef54158480e09ecC3580);
    address ovn = address(0xA3d1a8DEB97B111454B294E2324EfAD13a9d8396);
    address usdp = address(0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      ovn,
      usdp,
      underlying,
      0,
      2,
      true
    );
    rewardTokens = [ovn];
  }
}
