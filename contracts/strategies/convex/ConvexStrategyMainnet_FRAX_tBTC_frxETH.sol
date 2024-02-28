//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_FRAX_tBTC_frxETH is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3c64d44Ab19D63F09ebaD38fd7b913Ab7E15e341); // Info -> LP Token address
    address rewardPool = address(0x08dd3db3905cd0348DC66691a1cF96071c035355); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address cvx = address(0xb952A807345991BD529FDded05009F5e80Fe8F45);
    address frax = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      24,  // Pool id: Info -> Rewards contract address -> read -> pid
      frax, // depositToken
      0, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      3, //nTokens -> total number of deposit tokens
      false //metaPool -> if LP token address == pool address (at curve)
    );
    rewardTokens = [crv, cvx, arb];
    reward2WETH[crv] = [crv, weth];
    reward2WETH[cvx] = [cvx, weth];
    reward2WETH[arb] = [cvx, weth];
    WETH2deposit = [weth, frax];
  }
}