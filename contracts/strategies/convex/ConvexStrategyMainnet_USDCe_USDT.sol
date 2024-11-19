//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_USDCe_USDT is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x7f90122BF0700F9E7e1F688fe926940E8839F353); // Info -> LP Token address
    address rewardPool = address(0x971E732B5c91A59AEa8aa5B0c763E6d648362CF8); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address cvx = address(0xb952A807345991BD529FDded05009F5e80Fe8F45);
    address usdce = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      7,  // Pool id: Info -> Rewards contract address -> read -> pid
      usdce, // depositToken
      0, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false //NG -> new version Curve Pool
    );
    rewardTokens = [crv, cvx, arb];
  }
}