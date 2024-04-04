//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_gDAI is PenpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x99Ed4F0Ab6524d26B31D0aEa087eBe20D5949e0f); //Gains Network gDAI Pendle Market
    address rewardPool = address(0x0776C06907CE6Ff3d9Dbf84bA9B3422d7225942D); //MasterPenpie
    address gdai = address(0xd85E038593d7A098614721EaE955EC2022B9B91B);
    address sygdai = address(0xAF699fb0D9F12Bf7B14474aE5c9Bea688888DF73);
    address pendle = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      gdai,
      sygdai
    );
    rewardTokens = [pendle];
  }
}
