//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/interface/hop/ILPToken.sol";
import "../../base/interface/hop/IStakingRewards.sol";
import "../../base/interface/hop/ISwap.sol";

contract HopStrategy is BaseUpgradeableStrategy {
    using SafeMath for uint256;
    using SafeMath for uint8;
    using SafeERC20 for IERC20;

    address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

    // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
    bytes32 internal constant _DEPOSIT_TOKEN_SLOT = 0x219270253dbc530471c88a9e7c321b36afda219583431e7b6c386d2d46e70c86;

    // this would be reset on each upgrade
    address[] public rewardTokens;

    constructor() public BaseUpgradeableStrategy() {
        assert(_DEPOSIT_TOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositToken")) - 1));
    }

    function initializeBaseStrategy(
        address _storage,
        address _underlying,
        address _vault,
        address _rewardPool,
        address _rewardToken,
        address _depositToken
    ) public initializer {
        BaseUpgradeableStrategy.initialize(
            _storage,
            _underlying,
            _vault,
            _rewardPool,
            _rewardToken,
            harvestMSIG
        );

        _setDepositToken(_depositToken);
    }

    function depositArbCheck() public pure returns (bool) {
        return true;
    }

    function _rewardPoolBalance() internal view returns (uint256 balance) {
        balance = IStakingRewards(rewardPool()).balanceOf(address(this));
    }

    function _investAllUnderlying() internal onlyNotPausedInvesting {
        address _underlying = underlying();
        address _rewardPool = rewardPool();
        uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));
        if (entireBalance > 0) {
            IERC20(_underlying).safeApprove(_rewardPool, 0);
            IERC20(_underlying).safeApprove(_rewardPool, entireBalance);
            IStakingRewards(_rewardPool).stake(entireBalance);
        }
    }

    function _exitRewardPool() internal {
        uint256 stakedBalance = _rewardPoolBalance();
        if (stakedBalance != 0) {
            IStakingRewards(rewardPool()).exit();
        }
    }

    function _withdrawUnderlyingFromPool(uint256 amount) internal {
        if (amount > 0) {
            IStakingRewards(rewardPool()).withdraw(amount);
        }
    }

    /*
     *   In case there are some issues discovered about the pool or underlying asset
     *   Governance can exit the pool properly
     *   The function is only used for emergency to exit the pool
     */
    function emergencyExit() public onlyGovernance {
        _exitRewardPool();
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

        address _depositToken = depositToken();

        if (_depositToken != _rewardToken) {
            IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
            IERC20(_rewardToken).safeApprove(
                _universalLiquidator,
                remainingRewardBalance
            );
            IUniversalLiquidator(_universalLiquidator).swap(
                _rewardToken,
                _depositToken,
                remainingRewardBalance,
                1,
                address(this)
            );
        }

        _makeHopLP();
    }

    function _makeHopLP() internal {
        address _depositToken = depositToken();
        address swap = ILPToken(underlying()).swap();
        uint256 depositBalance = IERC20(_depositToken).balanceOf(address(this));
        if (depositBalance == 0) {
            return;
        }
        uint8 index = ISwap(swap).getTokenIndex(_depositToken);
        uint256[] memory amounts = new uint256[](2);
        amounts[index] = depositBalance;

        IERC20(_depositToken).safeApprove(swap, 0);
        IERC20(_depositToken).safeApprove(swap, depositBalance);
        ISwap(swap).addLiquidity(amounts, 1, block.timestamp);
    }

    function _claimRewards() internal {
        IStakingRewards(rewardPool()).getReward();
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawAllToVault() public restricted {
        _exitRewardPool();
        _claimRewards();
        _liquidateReward();
        address underlying_ = underlying();
        IERC20(underlying_).safeTransfer(vault(), IERC20(underlying_).balanceOf(address(this)));
    }

    /*
     *   Withdraws all the asset to the vault
     */
    function withdrawToVault(uint256 _amount) public restricted {
        // Typically there wouldn't be any amount here
        // however, it is possible because of the emergencyExit
        address underlying_ = underlying();
        uint256 entireBalance = IERC20(underlying_).balanceOf(address(this));

        if(_amount > entireBalance){
            // While we have the check above, we still using SafeMath below
            // for the peace of mind (in case something gets changed in between)
            uint256 needToWithdraw = _amount.sub(entireBalance);
            uint256 toWithdraw = Math.min(_rewardPoolBalance(), needToWithdraw);
            _withdrawUnderlyingFromPool(toWithdraw);
        }
        IERC20(underlying_).safeTransfer(vault(), _amount);
    }

    /*
     *   Note that we currently do not have a mechanism here to include the
     *   amount of reward that is accrued.
     */
    function investedUnderlyingBalance() external view returns (uint256) {
        if (rewardPool() == address(0)) {
            return IERC20(underlying()).balanceOf(address(this));
        }
        // Adding the amount locked in the reward pool and the amount that is somehow in this contract
        // both are in the units of "underlying"
        // The second part is needed because there is the emergency exit mechanism
        // which would break the assumption that all the funds are always inside of the reward pool
        return _rewardPoolBalance().add(IERC20(underlying()).balanceOf(address(this)));
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
        _investAllUnderlying();
    }

    /**
     * Can completely disable claiming UNI rewards and selling. Good for emergency withdraw in the
     * simplest possible way.
     */
    function setSell(bool s) public onlyGovernance {
        _setSell(s);
    }

    function _setDepositToken(address _address) internal {
        setAddress(_DEPOSIT_TOKEN_SLOT, _address);
    }

    function depositToken() public view returns (address) {
        return getAddress(_DEPOSIT_TOKEN_SLOT);
    }

    function finalizeUpgrade() external onlyGovernance {
        _finalizeUpgrade();
    }
}
