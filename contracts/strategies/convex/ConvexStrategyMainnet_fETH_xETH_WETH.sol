//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_fETH_xETH_WETH is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xF7Fed8Ae0c5B78c19Aadd68b700696933B0Cefd9); // Info -> LP Token address
    address rewardPool = address(0xaCb744c7e7C95586DB83Eda3209e6483Fb1FCbA4); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address cvx = address(0xb952A807345991BD529FDded05009F5e80Fe8F45);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      15,  // Pool id: Info -> Rewards contract address -> read -> pid
      weth, // depositToken
      2, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      3, //nTokens -> total number of deposit tokens
      false //NG -> new version Curve Pool
    );
    rewardTokens = [crv, cvx];
  }
}