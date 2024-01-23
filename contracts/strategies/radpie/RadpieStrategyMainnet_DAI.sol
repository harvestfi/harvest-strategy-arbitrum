//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./RadpieStrategy.sol";

contract RadpieStrategyMainnet_DAI is RadpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x8409DE8E98F80D0E40F42849eF0923c2493BEeAd); //DAI_rDAI
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
