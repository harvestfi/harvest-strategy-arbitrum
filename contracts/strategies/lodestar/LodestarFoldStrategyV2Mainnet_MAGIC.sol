//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LodestarFoldStrategyV2.sol";

contract LodestarFoldStrategyV2Mainnet_MAGIC is LodestarFoldStrategyV2 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x539bdE0d7Dbd336b79148AA742883198BBF60342);
    address cToken = address(0xf21Ef887CB667f84B8eC5934C1713A7Ade8c38Cf);
    address comptroller = address(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    address lode = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    LodestarFoldStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      480,
      500,
      1000,
      true
    );
    rewardTokens = [lode, arb];
  }
}