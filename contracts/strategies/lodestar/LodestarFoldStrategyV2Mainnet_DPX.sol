//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LodestarFoldStrategyV2.sol";

contract LodestarFoldStrategyV2Mainnet_DPX is LodestarFoldStrategyV2 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x6C2C06790b3E3E3c38e12Ee22F8183b37a13EE55);
    address cToken = address(0x5d27cFf80dF09f28534bb37d386D43aA60f88e25);
    address comptroller = address(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    address lode = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
    LodestarFoldStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      130,
      150,
      true
    );
    rewardTokens = [lode, arb];
  }
}