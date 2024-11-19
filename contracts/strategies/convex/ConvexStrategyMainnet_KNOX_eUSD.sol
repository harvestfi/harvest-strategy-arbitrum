//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_KNOX_eUSD is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x86EA1191a219989d2dA3a85c949a12A92f8ED3Db); // Info -> LP Token address
    address rewardPool = address(0xbA2c194f2215Af833Aa24C5a0A87492bfD224A51); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    address eusd = address(0x12275DCB9048680c4Be40942eA4D92c74C63b844);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      35,  // Pool id: Info -> Rewards contract address -> read -> pid
      eusd, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false //NG -> new version Curve Pool
    );
    rewardTokens = [crv];
  }
}