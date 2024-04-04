//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_aUSDC is PenpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xBa4A858d664Ddb052158168DB04AFA3cFF5CFCC8); //AAVE aUSDC Pendle Market
    address rewardPool = address(0x0776C06907CE6Ff3d9Dbf84bA9B3422d7225942D); //MasterPenpie
    address aarbusdcn = address(0x724dc807b04555b71ed48a6896b6F41593b8C637);
    address syausdc = address(0x50288c30c37FA1Ec6167a31E575EA8632645dE20);
    address pendle = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    address usdc = address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      aarbusdcn,
      syausdc
    );
    rewardTokens = [pendle];
  }
}
