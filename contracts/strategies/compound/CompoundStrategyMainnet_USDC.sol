//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDC is CompoundStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address market = address(0x9c4ec768c28520B50860ea7a15bd7213a9fF58bf);
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
