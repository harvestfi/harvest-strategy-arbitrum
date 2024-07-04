// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.6.12;

interface CTokenInterface {

    /**
     * @notice Total amount of outstanding borrows of the underlying in this market
     */
    function totalBorrows() external view returns (uint);

    /**
     * @notice Total number of tokens in circulation
     */
    function totalSupply() external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function balanceOfUnderlying(address owner) external returns (uint);

    function getAccountSnapshot(address account) external view returns (uint, uint, uint, uint);

    function borrowRatePerBlock() external view returns (uint);

    function supplyRatePerBlock() external view returns (uint);

    function totalBorrowsCurrent() external returns (uint);

    function borrowBalanceCurrent(address account) external returns (uint);

    function borrowBalanceStored(address account) external view returns (uint);

    function exchangeRateCurrent() external returns (uint);

    function exchangeRateStored() external view returns (uint);

    function getCash() external view returns (uint);

    function accrueInterest() external returns (uint);
}

interface CErc20Interface {

    /**
     * @notice Underlying asset for this CToken
     */
    function underlying() external view returns (address);

    /*** User Interface ***/

    function mint(uint mintAmount) external returns (uint);
    function mint() external payable returns (uint);

    function redeemUnderlying(uint redeemAmount) external returns (uint);

    function borrow(uint borrowAmount) external returns (uint);

    function repayBorrow(uint repayAmount) external returns (uint);
    function repayBorrow() external payable returns (uint);
}