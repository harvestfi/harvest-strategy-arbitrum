//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_OVN_stable is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x1446999B0b0E4f7aDA6Ee73f2Ae12a2cfdc5D9E7);
    address rewardPool = address(0x25844114856617F739E3f175Db0edC46e00e1847); // Info -> Rewards contract address
    address ovn = address(0xA3d1a8DEB97B111454B294E2324EfAD13a9d8396);
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address usdp = address(0xe80772Eaf6e2E18B651F160Bc9158b2A5caFCA65);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      31,
      usdp,
      0,
      underlying,
      2,
      true
    );
    rewardTokens = [crv, ovn];
  }
}
