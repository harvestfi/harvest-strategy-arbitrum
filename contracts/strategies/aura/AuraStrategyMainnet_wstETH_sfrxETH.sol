//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./AuraStrategy.sol";

contract AuraStrategyMainnet_wstETH_sfrxETH is AuraStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xc2598280bFeA1Fe18dFcaBD21C7165c40c6859d3);
    address aura = address(0x1509706a6c66CA549ff0cB464de88231DDBe213B);
    address bal = address(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    address arb = address(0x912CE59144191C1204E64559FE8253a0e49E6548);
    address rewardPool = address(0x83D37cbA332ffd53A4336Ee06f3c301B8929E684);
    AuraStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      rewardPool,
      0xc2598280bfea1fe18dfcabd21c7165c40c6859d30000000000000000000004f3,  // Balancer Pool id
      51,      // Aura Pool id
      underlying   //depositToken
    );
    rewardTokens = [aura, bal, arb];
  }
}
