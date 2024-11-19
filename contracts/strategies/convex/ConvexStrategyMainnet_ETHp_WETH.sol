//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./base/ConvexStrategy.sol";

contract ConvexStrategyMainnet_ETHp_WETH is ConvexStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x1Fb84Fa6D252762e8367eA607A6586E09dceBe3D); // Info -> LP Token address
    address rewardPool = address(0x55cDf25202DFe4C59515dE3FdD7b46A306CE827c); // Info -> Rewards contract address
    address crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
    ConvexStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool, // rewardPool
      37,  // Pool id: Info -> Rewards contract address -> read -> pid
      weth, // depositToken
      1, //depositArrayPosition. Find deposit transaction -> input params
      underlying, // deposit contract: usually underlying. Find deposit transaction -> interacted contract
      2, //nTokens -> total number of deposit tokens
      false //NG -> new version Curve Pool
    );
    rewardTokens = [crv];
  }
}