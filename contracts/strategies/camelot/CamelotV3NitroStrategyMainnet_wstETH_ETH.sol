//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotV3NitroStrategy.sol";

contract CamelotV3NitroStrategyMainnet_wstETH_ETH is CamelotV3NitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x3D53aC3Abec01827cAaE5Bc934d46b171cEa2206);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address nftPool = address(0x9B65AbBB9Ce32f44232bb2eA21d1fa7d8bc0E1c5);
    address nitroPool = address(0xd505758A31cBfBDeCc1DE616086C2696e970a7cD);
    CamelotV3NitroStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      grail,
      nftPool,
      nitroPool,
      address(0xFA10759780304c2B8d34B051C039899dFBbcad7f), //xGrail vault
      address(0), //PotPool
      address(0x1F1Ca4e8236CD13032653391dB7e9544a6ad123E) //UniProxy
    );
    rewardTokens = [grail, arb];
  }
}
