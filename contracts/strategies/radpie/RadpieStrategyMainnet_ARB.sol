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
    address underlying = address(0x912CE59144191C1204E64559FE8253a0e49E6548); // ARB address
    address rewardPool = address(0xc256d80128113C8c23DFce0F5a877b738738AD7f); // ARB Pool Rewarder
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
