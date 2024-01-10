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
    address underlying = address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1); // DAI address
    address rewardPool = address(0x8384fCdA31054efc8B4899d81F510e868f747029); // DAI Pool Rewarder
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
