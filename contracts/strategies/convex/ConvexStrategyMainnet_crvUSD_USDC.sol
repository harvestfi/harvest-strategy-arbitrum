//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_crvUSD_USDC is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xec090cf6DD891D2d014beA6edAda6e05E025D93d); // Info -> LP Token address
    address rewardPool = address(0xBFEE9F3E015adC754066424AEd535313dc764116); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address cvx = address(0xb952A807345991BD529FDded05009F5e80Fe8F45);
    address usdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      16,  // Pool id: Info -> Rewards contract address -> read -> pid
      usdc, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false //metaPool -> if LP token address == pool address (at curve)
    );
    rewardTokens = [crv, cvx, arb];
    reward2WETH[crv] = [crv, weth];
    reward2WETH[cvx] = [cvx, weth];
    reward2WETH[arb] = [arb, weth];
    WETH2deposit = [weth, usdc];
  }
}