//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./RadpieStrategy.sol";

contract RadpieStrategyMainnet_WBTC is RadpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6c1B07ed05656DEdd90321E94B1cDB26981e65f2); //WBTC_rWBTC
    address rewardPool = address(0xD97EbDd4a104e8336760C6350930a96A9A659A66); //RDNT reward manager
    address esrdnt = address(0x1cC128a5d977B3BA7d598f01dB20A2116F59ef68);
    address rdp = address(0x54BDBF3cE36f451Ec61493236b8E6213ac87c0f6);
    RadpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool
    );
    rewardTokens = [esrdnt, rdp];
  }
}
