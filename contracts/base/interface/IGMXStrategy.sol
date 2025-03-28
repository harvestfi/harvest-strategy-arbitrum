// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

interface IGMXStrategy {

    /// @notice declared as public so child contract can call it
    function isUnsalvageableToken(address token) external view returns (bool);

    function salvageToken(address recipient, address token, uint amount) external;

    function governance() external view returns (address);

    function controller() external view returns (address);

    function underlying() external view returns (address);

    function vault() external view returns (address);

    function withdrawAllToVault() external returns(bytes32);

    function withdrawToVault(uint256 _amount) external returns(bytes32);

    function investedUnderlyingBalance() external view returns (uint256);

    function doHardWork() external returns(bytes32);

    function depositArbCheck() external view returns (bool);

    function strategist() external view returns (address);

    /**
     * @return  The value of any accumulated rewards that are under control by the strategy. Each index corresponds with
     *          the tokens in `rewardTokens`. This function is not a `view`, because some protocols, like Curve, need
     *          writeable functions to get the # of claimable reward tokens
     */
    function getRewardPoolValues() external returns (uint256[] memory);
}
