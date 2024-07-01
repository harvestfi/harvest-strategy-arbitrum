//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./HopStrategy.sol";

contract HopStrategyMainnet_DAI is HopStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x68f5d998F00bB2460511021741D098c05721d8fF); //DAI-LP
    address rewardPool = address(0xBB9D66F7a7744C11550079045A177090E0015364);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address dai = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1);
    HopStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      arb,
      dai
    );
    rewardTokens = [arb];
  }
}
