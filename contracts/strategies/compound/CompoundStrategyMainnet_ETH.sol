//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_ETH is CompoundStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address market = address(0x6f7D514bbD4aFf3BcD1140B7344b32f063dEe486);
    address rewards = address(0x88730d254A2f7e6AC8388c3198aFd694bA9f7fae);
    address comp = address(0x354A6dA3fcde098F8389cad84b0182725c6C91dE);
    CompoundStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      market,
      rewards,
      comp
    );
  }
}
