//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_zunUSD_crvUSD is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8958AE46De6b33293DDdc6cDfbe36900f4631851); // Info -> LP Token address
    address rewardPool = address(0x08d521633b5Ac825556d156E147Fc4968a8Bb3D2); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address crvusd = address(0x498Bf2B1e120FeD3ad3D42EA2165E9b73f99C1e5);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      27,  // Pool id: Info -> Rewards contract address -> read -> pid
      crvusd, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      true //NG -> new version Curve Pool
    );
    rewardTokens = [crv];
  }
}