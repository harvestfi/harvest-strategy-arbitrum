//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CamelotV3NitroStrategy.sol";

contract CamelotV3NitroStrategyMainnet_LINK_ETH is CamelotV3NitroStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xF3557102C0cCBE07EE237B6eE70984f313886432);
    address grail = address(0x3d9907F9a368ad0a51Be60f7Da3b97cf940982D8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address nftPool = address(0xf49926092302B0c18385a7069f98456dF0e5C8Fe);
    address nitroPool = address(0xE651C9562F471bE685c1faE9EFaa0b5932974172);
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
