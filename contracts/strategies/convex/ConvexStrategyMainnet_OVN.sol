//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_OVN is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xb34a7d1444a707349Bc7b981B7F2E1f20F81F013);
    address rewardPool = address(0x11F2217fa1D5c44Eae310b9b985E2964FC47D8f9); // Info -> Rewards contract address
    address ovn = address(0xA3d1a8DEB97B111454B294E2324EfAD13a9d8396);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address usdp = address(0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      13,
      usdp,
      0,
      underlying,
      2,
      false
    );
    rewardTokens = [ovn, arb, crv];
  }
}
