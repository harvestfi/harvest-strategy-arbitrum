//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LodestarFoldStrategyV2.sol";

contract LodestarFoldStrategyV2Mainnet_PENDLE is LodestarFoldStrategyV2 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x0c880f6761F1af8d9Aa9C466984b80DAb9a8c9e8);
    address cToken = address(0x39c27DfdC9364a976926a820c8CAA8Fd035D0727);
    address comptroller = address(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    address lode = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
    LodestarFoldStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      480,
      500,
      true
    );
    rewardTokens = [lode, arb];
  }
}