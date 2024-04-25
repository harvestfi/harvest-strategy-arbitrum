//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_wstETH2706 is PenpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xFd8AeE8FCC10aac1897F8D5271d112810C79e022); //wstETH Pendle Market
    address rewardPool = address(0x0776C06907CE6Ff3d9Dbf84bA9B3422d7225942D); //MasterPenpie
    address wsteth = address(0x5979D7b546E38E414F7E9822514be443A4800529);
    address sywsteth = address(0x80c12D5b6Cc494632Bf11b03F09436c8B61Cc5Df);
    address pendle = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      wsteth,
      sywsteth
    );
    rewardTokens = [pendle];
  }
}
