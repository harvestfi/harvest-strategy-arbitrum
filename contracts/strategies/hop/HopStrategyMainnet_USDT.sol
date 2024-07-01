//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./HopStrategy.sol";

contract HopStrategyMainnet_USDT is HopStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xCe3B19D820CB8B9ae370E423B0a329c4314335fE); //USDT-LP
    address rewardPool = address(0xB8f90e115499082747Ba5DA94732863b12cB1F25);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address usdt = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    HopStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      arb,
      usdt
    );
    rewardTokens = [arb];
  }
}
