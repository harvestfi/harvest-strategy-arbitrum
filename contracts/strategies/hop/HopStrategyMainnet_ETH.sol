//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./HopStrategy.sol";

contract HopStrategyMainnet_ETH is HopStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x59745774Ed5EfF903e615F5A2282Cae03484985a); //WETH-LP
    address rewardPool = address(0x00001fcF29c5Fd7846E4332AfBFaA48701D727f5);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    HopStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      arb,
      weth
    );
    rewardTokens = [arb];
  }
}
