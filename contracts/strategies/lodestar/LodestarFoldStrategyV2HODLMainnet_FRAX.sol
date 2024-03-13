//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./LodestarFoldStrategyV2HODL.sol";

contract LodestarFoldStrategyV2HODLMainnet_FRAX is LodestarFoldStrategyV2HODL {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F);
    address cToken = address(0xD12d43Cdf498e377D3bfa2c6217f05B466E14228);
    address comptroller = address(0xa86DD95c210dd186Fa7639F93E4177E97d057576);
    LodestarFoldStrategyV2HODL.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      cToken,
      comptroller,
      730,
      750,
      true,
      address(0x710A1AB6Cb8412DE9613ad6c7195453Ce8b5ca71), // LODE vault
      address(0) //potPool (to be set after deployment)
    );
    rewardTokens = [lode, arb];
  }
}