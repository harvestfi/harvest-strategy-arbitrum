//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_crvUSD_FRAX is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x2FE7AE43591E534C256A1594D326e5779E302Ff4); // Info -> LP Token address
    address rewardPool = address(0xDD27101D5370a3BBF3Aa65B5AD24b23e191309B4); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address cvx = address(0xb952A807345991BD529FDded05009F5e80Fe8F45);
    address frax = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      19,  // Pool id: Info -> Rewards contract address -> read -> pid
      frax, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      true //NG -> new version Curve Pool
    );
    rewardTokens = [crv, cvx, arb];
  }
}