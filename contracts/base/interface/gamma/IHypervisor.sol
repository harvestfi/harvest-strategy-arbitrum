//SPDX-License-Identifier: Unlicense

pragma solidity 0.6.12;

interface IHypervisor {
  function token0() external view returns (address);
  function token1() external view returns (address);
  function getTotalAmounts() external view returns(uint256, uint256);
  function withdraw(uint256 shares, address to, address from, uint256[4] calldata minAmounts) external;
}
