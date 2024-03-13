//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LodestarFoldStrategyV2.sol";

contract LodestarFoldStrategyV2Mainnet_FRAX is LodestarFoldStrategyV2 {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    address cToken = address(0xD12d43Cdf498e377D3bfa2c6217f05B466E14228);
    address comptroller = address(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    address lode = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
    LodestarFoldStrategyV2.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      730,
      750,
      true
    );
    rewardTokens = [lode, arb];
  }
}