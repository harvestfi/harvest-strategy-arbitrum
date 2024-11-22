//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CompoundStrategy.sol";

contract CompoundStrategyMainnet_USDT is CompoundStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address market = address(0xd98Be00b5D27fc98112BdE293e487f8D4cA57d07);
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
