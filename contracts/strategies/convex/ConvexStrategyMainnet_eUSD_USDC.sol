//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_eUSD_USDC is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x93a416206B4ae3204cFE539edfeE6BC05a62963e); // Info -> LP Token address
    address rewardPool = address(0xD4f9bCc2e0e920e23763FA8e37eCbC4135959dB4); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address usdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      36,  // Pool id: Info -> Rewards contract address -> read -> pid
      usdc, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      true //NG -> new version Curve Pool
    );
    rewardTokens = [crv, arb];
  }
}