//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_WBTC_tBTC is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x186cF879186986A20aADFb7eAD50e3C20cb26CeC); // Info -> LP Token address
    address rewardPool = address(0xa4Ed1e1Db18d65A36B3Ef179AaFB549b45a635A4); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address wbtc = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      33,  // Pool id: Info -> Rewards contract address -> read -> pid
      wbtc, // depositToken
      0, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      true //NG -> new version Curve Pool
    );
    rewardTokens = [crv, arb];
  }
}