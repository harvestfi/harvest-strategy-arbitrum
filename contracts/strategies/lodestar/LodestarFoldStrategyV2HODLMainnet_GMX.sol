//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LodestarFoldStrategyV2HODL.sol";

contract LodestarFoldStrategyV2HODLMainnet_GMX is LodestarFoldStrategyV2HODL {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xfc5A1A6EB076a2C7aD06eD22C90d7E710E35ad0a);
    address cToken = address(0x79B6c5e1A7C0aD507E1dB81eC7cF269062BAb4Eb);
    address comptroller = address(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    LodestarFoldStrategyV2HODL.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      680,
      700,
      1000,
      true,
      address(0x710A1AB6Cb8412DE9613ad6c7195453Ce8b5ca71), // LODE vault
      address(0) //potPool (to be set after deployment)
    );
    rewardTokens = [lode, arb];
  }
}