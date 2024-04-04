//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_mPENDLE is PenpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xf617792eA9Dceb2208F4C440258B21d2f3FdB9A3); //mPendle Pendle Market
    address rewardPool = address(0x0776C06907CE6Ff3d9Dbf84bA9B3422d7225942D); //MasterPenpie
    address mpendle = address(0xB688BA096b7Bb75d7841e47163Cd12D18B36A5bF);
    address sympendle = address(0x5C4110eD760470f79E469a901Bd6fb45a65BE0F4);
    address pendle = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      mpendle,
      sympendle
    );
    rewardTokens = [pendle];
  }
}
