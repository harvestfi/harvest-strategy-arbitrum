//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./GMXStrategy.sol";

contract GMXStrategyMainnet_WBTC is GMXStrategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    GMXStrategy.initializeBaseStrategy(
      _storage,
      address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f), //underlying
      _vault,
      address(0x69C527fC77291722b52649E45c838e41be8Bf5d5), //exchangeRouter
      address(0x7C11F78Ce78768518D743E81Fdfa2F860C6b9A77), //market
      address(0xF89e77e8Dc11691C9e8757e84aaFbCD8A67d7A55), //depositVault
      address(0x0628D46b5D145f183AdB6Ef1f2c97eD1C4701C55), //withdrawVault
      address(0xC5d323907696C513842a1ce4B48125cD8918f0b5)  //viewer
    );
  }
}