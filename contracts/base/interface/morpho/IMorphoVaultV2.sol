//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IMorphoVaultV2 {
    function forceDeallocate(address adapter, bytes memory data, uint256 assets, address onBehalf) external returns (uint256 penaltyShares);
    function forceDeallocatePenalty(address adapter) external view returns (uint256);
}
