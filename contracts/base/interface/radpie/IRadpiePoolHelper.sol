//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IRadpiePoolHelper {
    function totalStaked(address _asset) external view returns (uint256);

    function balance(address _asset, address _address) external view returns (uint256);

    function depositAsset(address _asset, uint256 _amount) external payable;

    function withdrawAsset(address _asset, uint256 _amount) external;

    function radiantStaking() external view returns (address);
}