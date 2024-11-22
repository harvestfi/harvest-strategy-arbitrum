//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./AaveSupplyStrategy.sol";

contract AaveSupplyStrategyMainnet_ETH is AaveSupplyStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address aToken = address(0xe50fA9b3c56FfB159cB0FCA61F5c9D750e8128c8);
    AaveSupplyStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken
    );
  }
}
