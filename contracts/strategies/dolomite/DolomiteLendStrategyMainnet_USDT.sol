//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./DolomiteLendStrategy.sol";

contract DolomiteLendStrategyMainnet_USDT is DolomiteLendStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    DolomiteLendStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      address(0x6Bd780E7fDf01D77e4d475c821f1e7AE05409072),
      address(0xAdB9D68c613df4AA363B42161E1282117C7B9594),
      5,
      weth
    );
  }
}