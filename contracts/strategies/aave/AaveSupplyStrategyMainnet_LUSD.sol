//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./AaveSupplyStrategy.sol";

contract AaveSupplyStrategyMainnet_LUSD is AaveSupplyStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x93b346b6BC2548dA6A1E7d98E9a421B42541425b);
    address aToken = address(0x8ffDf2DE812095b1D19CB146E4c004587C0A0692);
    AaveSupplyStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      aToken
    );
  }
}
