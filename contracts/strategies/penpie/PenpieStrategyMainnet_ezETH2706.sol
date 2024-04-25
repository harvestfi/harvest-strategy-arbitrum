//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_ezETH2706 is PenpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x5E03C94Fc5Fb2E21882000A96Df0b63d2c4312e2); //ezETH Pendle Market
    address rewardPool = address(0x0776C06907CE6Ff3d9Dbf84bA9B3422d7225942D); //MasterPenpie
    address ezeth = address(0x2416092f143378750bb29b79eD961ab195CcEea5);
    address syezeth = address(0x0dE802e3D6Cc9145A150bBDc8da9F988a98c5202);
    address pendle = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      ezeth,
      syezeth
    );
    rewardTokens = [pendle];
  }
}
