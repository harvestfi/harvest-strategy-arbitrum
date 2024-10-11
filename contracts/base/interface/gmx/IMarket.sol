// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IMarket {
        struct Props {
        address marketToken;
        address indexToken;
        address longToken;
        address shortToken;
    }

    function dataStore() external view returns (address);
}