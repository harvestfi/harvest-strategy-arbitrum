//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../interface/IBooster.sol";
import "../interface/IBaseRewardPool.sol";
import "../../../base/interface/curve/ICurveDeposit_NG.sol";
import "../../../base/interface/curve/ICurveDeposit_2token.sol";
import "../../../base/interface/curve/ICurveDeposit_3token.sol";
import "../../../base/interface/curve/ICurveDeposit_4token.sol";
import "../../../base/interface/weth/IWETH.sol";
import "../../../base/interface/IUniversalLiquidator.sol";

contract ConvexStrategy is BaseUpgradeableStrategy {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant booster = address(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);
  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _POOLID_SLOT = 0x3fd729bfa2e28b7806b03a6e014729f59477b530f995be4d51defc9dad94810b;
  bytes32 internal constant _DEPOSIT_TOKEN_SLOT = 0x219270253dbc530471c88a9e7c321b36afda219583431e7b6c386d2d46e70c86;
  bytes32 internal constant _DEPOSIT_ARRAY_POSITION_SLOT = 0xb7c50ef998211fff3420379d0bf5b8dfb0cee909d1b7d9e517f311c104675b09;
  bytes32 internal constant _CURVE_DEPOSIT_SLOT = 0xb306bb7adebd5a22f5e4cdf1efa00bc5f62d4f5554ef9d62c1b16327cd3ab5f9;
  bytes32 internal constant _NTOKENS_SLOT = 0xbb60b35bae256d3c1378ff05e8d7bee588cd800739c720a107471dfa218f74c1;
  bytes32 internal constant _NG_SLOT = 0xcd6a0b148d19dba2b2780e77ba620dd79534ef7aeb84c51a65b7d73c6a83da27;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() public BaseUpgradeableStrategy() {
    assert(_POOLID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.poolId")) - 1));
    assert(_DEPOSIT_TOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositToken")) - 1));
    assert(_DEPOSIT_ARRAY_POSITION_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.depositArrayPosition")) - 1));
    assert(_CURVE_DEPOSIT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.curveDeposit")) - 1));
    assert(_NTOKENS_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.nTokens")) - 1));
    assert(_NG_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.NG")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _rewardPool,
    uint256 _poolID,
    address _depositToken,
    uint256 _depositArrayPosition,
    address _curveDeposit,
    uint256 _nTokens,
    bool _NG
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _rewardPool,
      weth,
      harvestMSIG
    );

    address _lpt;
    (_lpt,,,,) = IBooster(booster).poolInfo(_poolID);
    require(_lpt == underlying(), "Pool Info does not match underlying");
    require(_depositArrayPosition < _nTokens, "Deposit array position out of bounds");
    require(1 < _nTokens && _nTokens < 5, "_nTokens should be 2, 3 or 4");
    _setDepositArrayPosition(_depositArrayPosition);
    _setPoolId(_poolID);
    _setDepositToken(_depositToken);
    _setCurveDeposit(_curveDeposit);
    _setNTokens(_nTokens);
    _setNG(_NG);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function rewardPoolBalance() internal view returns (uint256 bal) {
      bal = IBaseRewardPool(rewardPool()).balanceOf(address(this));
  }

  function exitRewardPool() internal {
      uint256 stakedBalance = rewardPoolBalance();
      if (stakedBalance != 0) {
          IBaseRewardPool(rewardPool()).withdrawAll(true);
      }
  }

  function partialWithdrawalRewardPool(uint256 amount) internal {
    IBaseRewardPool(rewardPool()).withdraw(amount, false);  //don't claim rewards at this point
  }

  function emergencyExitRewardPool() internal {
    uint256 stakedBalance = rewardPoolBalance();
    if (stakedBalance != 0) {
        IBaseRewardPool(rewardPool()).withdrawAll(false); //don't claim rewards
    }
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  function enterRewardPool() internal {
    address _underlying = underlying();
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));
    IERC20(_underlying).safeApprove(booster, 0);
    IERC20(_underlying).safeApprove(booster, entireBalance);
    IBooster(booster).depositAll(poolId()); //deposit and stake
  }

  /*
  *   In case there are some issues discovered about the pool or underlying asset
  *   Governance can exit the pool properly
  *   The function is only used for emergency to exit the pool
  */
  function emergencyExit() public onlyGovernance {
    emergencyExitRewardPool();
    _setPausedInvesting(true);
  }

  /*
  *   Resumes the ability to invest into the underlying reward pools
  */

  function continueInvesting() public onlyGovernance {
    _setPausedInvesting(false);
  }

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  function changeDepositToken(address _depositToken, uint256 _depositArrayPosition) public onlyGovernance {
    _setDepositToken(_depositToken);
    _setDepositArrayPosition(_depositArrayPosition);
  }

  // We assume that all the tradings can be done on Sushiswap
  function _liquidateReward() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapoolId exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }

    address _rewardToken = rewardToken();
    address _depositToken = depositToken();
    address _universalLiquidator = universalLiquidator();

    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 balance = IERC20(token).balanceOf(address(this));

      if (balance > 0 && token != _rewardToken) {
        IERC20(token).safeApprove(_universalLiquidator, 0);
        IERC20(token).safeApprove(_universalLiquidator, balance);
        IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, balance, 1, address(this));
      }

    }

    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    if(_depositToken != _rewardToken) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, _depositToken, remainingRewardBalance, 1, address(this));
    }

    uint256 tokenBalance = IERC20(_depositToken).balanceOf(address(this));
    if (tokenBalance > 0) {
      depositCurve();
    }
  }

  function depositCurve() internal {
    address _depositToken = depositToken();
    address _curveDeposit = curveDeposit();
    uint256 _nTokens = nTokens();

    uint256 tokenBalance = IERC20(_depositToken).balanceOf(address(this));
    IERC20(_depositToken).safeApprove(_curveDeposit, 0);
    IERC20(_depositToken).safeApprove(_curveDeposit, tokenBalance);

    // we can accept 1 as minimum, this will be called only by trusted roles
    uint256 minimum = 1;
    if (_nTokens == 2) {
      if (NG()) {
        uint256[] memory depositArray = new uint256[](2);
        depositArray[depositArrayPosition()] = tokenBalance;
        ICurveDeposit_NG(_curveDeposit).add_liquidity(depositArray, minimum);
      } else {
        uint256[2] memory depositArray;
        depositArray[depositArrayPosition()] = tokenBalance;
        ICurveDeposit_2token(_curveDeposit).add_liquidity(depositArray, minimum);
      }
    } else if (_nTokens == 3) {
      uint256[3] memory depositArray;
      depositArray[depositArrayPosition()] = tokenBalance;
      ICurveDeposit_3token(_curveDeposit).add_liquidity(depositArray, minimum);
    } else if (_nTokens == 4) {
      uint256[4] memory depositArray;
      depositArray[depositArrayPosition()] = tokenBalance;
      ICurveDeposit_4token(_curveDeposit).add_liquidity(depositArray, minimum);
    }
  }

  /*
  *   Stakes everything the strategy holds into the reward pool
  */
  function investAllUnderlying() internal onlyNotPausedInvesting {
    // this check is needed, because most of the SNX reward pools will revert if
    // you try to stake(0).
    if(IERC20(underlying()).balanceOf(address(this)) > 0) {
      enterRewardPool();
    }
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    if (address(rewardPool()) != address(0)) {
      exitRewardPool();
    }
    _liquidateReward();
    IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawToVault(uint256 amount) public restricted {
    address _underlying = underlying();
    // Typically there wouldn't be any amount here
    // however, it is possible because of the emergencyExit
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));

    if(amount > entireBalance){
      // While we have the check above, we still using SafeMath below
      // for the peace of mind (in case something gets changed in between)
      uint256 needToWithdraw = amount.sub(entireBalance);
      uint256 toWithdraw = Math.min(rewardPoolBalance(), needToWithdraw);
      partialWithdrawalRewardPool(toWithdraw);
    }
    IERC20(_underlying).safeTransfer(vault(), amount);
  }

  /*
  *   Note that we currently do not have a mechanism here to include the
  *   amount of reward that is accrued.
  */
  function investedUnderlyingBalance() external view returns (uint256) {
    return rewardPoolBalance()
      .add(IERC20(underlying()).balanceOf(address(this)));
  }

  /*
  *   Governance or Controller can claim coins that are somehow transferred into the contract
  *   Note that they cannot come in take away coins that are used and defined in the strategy itself
  */
  function salvage(address recipient, address token, uint256 amount) external onlyControllerOrGovernance {
     // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
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
    IBaseRewardPool(rewardPool()).getReward(address(this));
    _liquidateReward();
    investAllUnderlying();
  }

  /**
  * Can completely disable claiming UNI rewards and selling. Good for emergency withdraw in the
  * simplest possible way.
  */
  function setSell(bool s) public onlyGovernance {
    _setSell(s);
  }

  // masterchef rewards pool ID
  function _setPoolId(uint256 _value) internal {
    setUint256(_POOLID_SLOT, _value);
  }

  function poolId() public view returns (uint256) {
    return getUint256(_POOLID_SLOT);
  }

  function _setDepositToken(address _address) internal {
    setAddress(_DEPOSIT_TOKEN_SLOT, _address);
  }

  function depositToken() public view returns (address) {
    return getAddress(_DEPOSIT_TOKEN_SLOT);
  }

  function _setDepositArrayPosition(uint256 _value) internal {
    setUint256(_DEPOSIT_ARRAY_POSITION_SLOT, _value);
  }

  function depositArrayPosition() public view returns (uint256) {
    return getUint256(_DEPOSIT_ARRAY_POSITION_SLOT);
  }

  function _setCurveDeposit(address _address) internal {
    setAddress(_CURVE_DEPOSIT_SLOT, _address);
  }

  function curveDeposit() public view returns (address) {
    return getAddress(_CURVE_DEPOSIT_SLOT);
  }

  function _setNTokens(uint256 _value) internal {
    setUint256(_NTOKENS_SLOT, _value);
  }

  function nTokens() public view returns (uint256) {
    return getUint256(_NTOKENS_SLOT);
  }

  function _setNG(bool _value) internal {
    setBoolean(_NG_SLOT, _value);
  }

  function NG() public view returns (bool) {
    return getBoolean(_NG_SLOT);
  }


  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {} // this is needed for the WETH unwrapping
}