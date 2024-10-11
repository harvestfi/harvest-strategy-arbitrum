//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./GMXStrategy.sol";

contract GMXStrategyMainnet_WBTC is GMXStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    address exchangeRouter = address(0x69C527fC77291722b52649E45c838e41be8Bf5d5);
    address market = address(0x7C11F78Ce78768518D743E81Fdfa2F860C6b9A77);
    address reader = address(0x23D4Da5C7C6902D4C86d551CaE60d5755820df9E);
    address depositVault = address(0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55);
    address withdrawVault = address(0x7C11F78Ce78768518D743E81Fdfa2F860C6b9A77);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    GMXStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      exchangeRouter,
      market,
      reader,
      depositVault,
      withdrawVault,
      weth
    );
  }
}