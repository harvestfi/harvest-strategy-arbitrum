//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

interface IRadiantStaking {
    function batchHarvestEntitledRDNT(address[] calldata _assets, bool _force) external;
}