//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./RadpieStrategy.sol";

contract RadpieStrategyMainnet_USDCe is RadpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xd86B1C1C7F921F3663921f8917d086379739cDA3); //USDC_rUSDC
    address rewardPool = address(0xD97EbDd4a104e8336760C6350930a96A9A659A66); //RDNT reward manager
    address esrdnt = address(0x1cC128a5d977B3BA7d598f01dB20A2116F59ef68);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    RadpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool
    );
    rewardTokens = [esrdnt, arb];
  }
}
