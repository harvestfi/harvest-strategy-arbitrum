//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_eETH is PenpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xE11f9786B06438456b044B3E21712228ADcAA0D1); //eETH Pendle Market
    address rewardPool = address(0x0776C06907CE6Ff3d9Dbf84bA9B3422d7225942D); //MasterPenpie
    address weeth = address(0x35751007a407ca6FEFfE80b3cB397736D2cf4dbe);
    address syweeth = address(0xa6C895EB332E91c5b3D00B7baeEAae478cc502DA);
    address pendle = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      weeth,
      syweeth
    );
    rewardTokens = [pendle, arb];
  }
}
