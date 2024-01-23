//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../base/interface/IVault.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/interface/radpie/IBaseRewardPool.sol";
import "../../base/interface/radpie/IMasterRadpie.sol";
import "../../base/interface/radpie/IRadiantStaking.sol";
import "../../base/interface/radpie/IRadpiePoolHelper.sol";
import "../../base/interface/radpie/IRDNTRewardManager.sol";
import "../../base/interface/radpie/IRadpieReceiptToken.sol";
import "../../base/interface/weth/IWETH.sol";

contract RadpieStrategy is BaseUpgradeableStrategy {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public constant weth =
        address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public constant harvestMSIG =
        address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);
    address public constant poolHelper = address(0x4ade86667760f45cBd5255a5bc8B4c3a703dDA7a);

    // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
    bytes32 internal constant _ASSET_SLOT = 0xa65e2b7ef56fbca2772a97c50d792e1f1d2e42e2171db2823e7473841a7c3686;

    // this would be reset on each upgrade
    address[] public rewardTokens;

    constructor() public BaseUpgradeableStrategy() {
        assert(_ASSET_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.asset")) - 1));
    }

    function initializeBaseStrategy(
        address _storage,
        address _underlying,
        address _vault,
        address _rewardPool
    ) public initializer {
        BaseUpgradeableStrategy.initialize(
            _storage,
            _underlying,
            _vault,
            _rewardPool,
            weth,
            harvestMSIG
        );

        address _asset = IRadpieReceiptToken(_underlying).underlying();
        _setAsset(_asset);
    }

    function depositArbCheck() public pure returns (bool) {
        return true;
    }

    function _rewardPoolBalance() internal view returns (uint256 balance) {
        balance = IRadpieReceiptToken(underlying()).balanceOf(address(this));
    }

    function _depositAsset() internal {
        address _asset = asset();
        uint256 entireBalance = IERC20(_asset).balanceOf(address(this));
        if (_asset == weth){
            IWETH(weth).withdraw(entireBalance);
            IRadpiePoolHelper(poolHelper).depositAsset{value: entireBalance}(_asset, entireBalance);
        } else {
            IERC20(_asset).safeApprove(poolHelper, 0);
            IERC20(_asset).safeApprove(poolHelper, entireBalance);
            IRadpiePoolHelper(poolHelper).depositAsset(_asset, entireBalance);
        }
    }

    /*
     *   In case there are some issues discovered about the pool or underlying asset
     *   Governance can exit the pool properly
     *   The function is only used for emergency to exit the pool
     */
    function emergencyExit() public onlyGovernance {
        _setPausedInvesting(true);
    }

    /*
     *   Resumes the ability to invest into the underlying reward pools
     */
    function continueInvesting() public onlyGovernance {
        _setPausedInvesting(false);
    }

    function unsalvagableTokens(address token) public view returns (bool) {
        return (token == rewardToken() || token == underlying());
    }

    function addRewardToken(address _token) public onlyGovernance {
        rewardTokens.push(_token);
    }

    function _liquidateReward() internal {
        if (!sell()) {
            // Profits can be disabled for possible simplified and rapid exit
            emit ProfitsNotCollected(sell(), false);
            return;
        }

        address _universalLiquidator = universalLiquidator();
        address _rewardToken = rewardToken();

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 rewardBalance = IERC20(token).balanceOf(address(this));

            if (rewardBalance == 0) {
                continue;
            }

            if (token != _rewardToken) {
                IERC20(token).safeApprove(_universalLiquidator, 0);
                IERC20(token).safeApprove(_universalLiquidator, rewardBalance);
                IUniversalLiquidator(_universalLiquidator).swap(
                    token,
                    _rewardToken,
                    rewardBalance,
                    1,
                    address(this)
                );
            }
        }

        uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
        _notifyProfitInRewardToken(_rewardToken, rewardBalance);
        uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(
            address(this)
        );

        if (remainingRewardBalance == 0) {
            return;
        }

        address _asset = asset();

        if (_asset != _rewardToken) {
            IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
            IERC20(_rewardToken).safeApprove(
                _universalLiquidator,
                remainingRewardBalance
            );
            IUniversalLiquidator(_universalLiquidator).swap(
                _rewardToken,
                _asset,
                remainingRewardBalance,
                1,
                address(this)
            );
        }

        _depositAsset();
    }

    function _claimRewards() internal {
        address _radiantStaking = IRadpiePoolHelper(poolHelper).radiantStaking();
        address[] memory _assets = new address[](1);
        _assets[0] = asset();

        IRadiantStaking(_radiantStaking).batchHarvestEntitledRDNT(_assets, false);
        IRDNTRewardManager(rewardPool()).redeemEntitledRDNT();
        IMasterRadpie(IRadpieReceiptToken(underlying()).masterRadpie()).multiclaim(_assets);
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawAllToVault() public restricted {
        _claimRewards();
        _liquidateReward();
        address underlying_ = underlying();

        IERC20(underlying_).safeTransfer(
            vault(),
            IERC20(underlying_).balanceOf(address(this))
        );
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawToVault(uint256 _amount) public restricted {
        IERC20(underlying()).safeTransfer(vault(), _amount);
    }

    /*
     *   Note that we currently do not have a mechanism here to include the
     *   amount of reward that is accrued.
     */
    function investedUnderlyingBalance() external view returns (uint256) {
        return IERC20(underlying()).balanceOf(address(this));
    }

    /*
     *   Governance or Controller can claim coins that are somehow transferred into the contract
     *   Note that they cannot come in take away coins that are used and defined in the strategy itself
     */
    function salvage(
        address recipient,
        address token,
        uint256 amount
    ) external onlyControllerOrGovernance {
        // To make sure that governance cannot come in and take away the coins
        require(
            !unsalvagableTokens(token),
            "token is defined as not salvagable"
        );
        IERC20(token).safeTransfer(recipient, amount);
    }

    /*
     *   Get the reward, sell it in exchange for underlying, invest what you got.
     *   It's not much, but it's honest work.
     *
     *   Note that although `onlyNotPausedInvesting` is not added here,
     *   calling `investAllUnderlying()` affectively blocks the usage of `doHardWork`
     *   when the investing is being paused by governance.
     */
    function doHardWork() external onlyNotPausedInvesting restricted {
        _claimRewards();
        _liquidateReward();
    }

    /**
     * Can completely disable claiming UNI rewards and selling. Good for emergency withdraw in the
     * simplest possible way.
     */
    function setSell(bool s) public onlyGovernance {
        _setSell(s);
    }

    function _setAsset(address _value) internal {
        setAddress(_ASSET_SLOT, _value);
    }

    function asset() public view returns (address) {
        return getAddress(_ASSET_SLOT);
    }

    function finalizeUpgrade() external onlyGovernance {
        _finalizeUpgrade();
    }

    receive() external payable {}
}
