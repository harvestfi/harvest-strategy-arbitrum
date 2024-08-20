//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./AaveRewardStrategy.sol";

contract AaveRewardStrategyMainnet_GHO is AaveRewardStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7dfF72693f6A4149b17e7C6314655f6A9F7c8B33);
    address aToken = address(0xeBe517846d0F36eCEd99C735cbF6131e1fEB775D);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    AaveRewardStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken,
      arb
    );
    rewardTokens = [arb];
  }
}
