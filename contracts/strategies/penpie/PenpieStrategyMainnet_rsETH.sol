//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./PenpieStrategy.sol";

contract PenpieStrategyMainnet_rsETH is PenpieStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6F02C88650837C8dfe89F66723c4743E9cF833cd); //rsETH Pendle Market
    address rewardPool = address(0x0776C06907CE6Ff3d9Dbf84bA9B3422d7225942D); //MasterPenpie
    address rseth = address(0x4186BFC76E2E237523CBC30FD220FE055156b41F);
    address syrseth = address(0xf176fB51F4eB826136a54FDc71C50fCd2202E272);
    address pendle = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    PenpieStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      rseth,
      syrseth
    );
    rewardTokens = [pendle, arb];
  }
}
