//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./CurveStrategy.sol";

contract CurveStrategyMainnet_dlcBTC_WBTC is CurveStrategy {

  constructor() public {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0xe957cE03cCdd88f02ed8b05C9a3A28ABEf38514A);
    address gauge = address(0x02b8e750E68cb648dB2c2ac4BBb47A10A5c12588);
    address dlcbtc = address(0x050C24dBf1eEc17babE5fc585F06116A259CC77A);
    CurveStrategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      gauge,
      dlcbtc,
      dlcbtc,
      underlying,
      1,
      2,
      true
    );
    rewardTokens = [dlcbtc];
  }
}
