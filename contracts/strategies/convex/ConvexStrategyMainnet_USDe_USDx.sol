//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_USDe_USDx is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x096A8865367686290639bc50bF8D85C0110d9Fea); // Info -> LP Token address
    address rewardPool = address(0xe062e302091f44d7483d9D6e0Da9881a0817E2be); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address usde = address(0x5d3a1Ff2b6BAb83b63cd9AD0787074081a52ef34);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      34,  // Pool id: Info -> Rewards contract address -> read -> pid
      usde, // depositToken
      0, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      true //NG -> new version Curve Pool
    );
    rewardTokens = [crv];
  }
}