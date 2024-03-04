//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./RadpieStrategy.sol";

contract RadpieStrategyMainnet_ARB is RadpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xf6da879761961ABD22177242904a6E12BB034C22); //ARB_rARB
    address rewardPool = address(0xD97EbDd4a104e8336760C6350930a96A9A659A66); //RDNT reward manager
    address esrdnt = address(0x1cC128a5d977B3BA7d598f01dB20A2116F59ef68);
    RadpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool
    );
    rewardTokens = [esrdnt];
  }
}
