//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "./MorphoVaultV2Strategy.sol";

contract MorphoVaultStrategyMainnet_KPKY_EURe_V2 is MorphoVaultV2Strategy {

  constructor() {}

  function initializeStrategy(
    address _storage,
    address _vault
  ) public initializer {
    address underlying = address(0x0c06cCF38114ddfc35e07427B9424adcca9F44F8);
    address morphoVault = address(0x7bfdE3A7bd346Da92521D384563F89BB45dE1f60);
    address weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    MorphoVaultV2Strategy.initializeBaseStrategy(
      _storage,
      underlying,
      _vault,
      morphoVault,
      weth
    );
  }

  // EURe has 18 decimals, and the RewardForwarder on Arbitrum swaps the fee on the spot. The
  // 1e3 default would let through a fee too small to come out of that swap as anything, and
  // the revert would take the hard work or the withdrawal that triggered it down with it.
  // 1e15 is the same 0.001 units the default stands for on a 6 decimal underlying.
  function feeFloor() public view virtual override returns (uint256) {
    return 1e15;
  }
}
