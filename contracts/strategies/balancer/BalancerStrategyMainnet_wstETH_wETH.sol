//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./BalancerStrategy.sol";

contract BalancerStrategyMainnet_wstETH_wETH is BalancerStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x36bf227d6BaC96e2aB1EbB5492ECec69C691943f);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address ldo = address(0x13Ad51ed4F1B7e9Dc168d8a00cB3f4dDD85EfA60);
    address wbtc = address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);
    address gauge = address(0x251e51b25AFa40F2B6b9F05aaf1bC7eAa0551771);
    BalancerStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      address(0xBA12222222228d8Ba445958a75a0704d566BF2C8), //balancer vault
      0x36bf227d6bac96e2ab1ebb5492ecec69c691943f000200000000000000000316,  // Pool id
      weth,   //depositToken
      false      //boosted
    );
    rewardTokens = [bal, ldo];
    reward2WETH[bal] = [bal, weth];
    reward2WETH[ldo] = [ldo, wbtc, weth];
    poolIds[bal][weth] = 0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
    poolIds[ldo][wbtc] = 0x9cc5d63aa18e6d33180453d5831acdd6b483e823000100000000000000000327;
    router[wbtc][weth] = camelotRouter;
  }
}
