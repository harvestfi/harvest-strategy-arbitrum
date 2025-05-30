//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/interface/gamma/IHypervisor.sol";
import "../../base/interface/gamma/IUniProxy.sol";
import "../../base/interface/gamma/IClearing.sol";
import "../../base/interface/IVault.sol";
import "../../base/interface/IPotPool.sol";

contract CamelotV3Strategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant xGrail = address(0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _XGRAIL_VAULT_SLOT = 0xd445aff5601e22e4f2e49f44eb54e33aa29670745d5241914b5369f65f9d43d0;
  bytes32 internal constant _POTPOOL_SLOT = 0x7f4b50847e7d7a4da6a6ea36bfb188c77e9f093697337eb9a876744f926dd014;
  bytes32 internal constant _UNIPROXY_SLOT = 0x09ff9720152edb4fad4ed05a0b77258f0fce17715f9397342eb08c8d7f965234;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() BaseUpgradeableStrategy() {
    assert(_XGRAIL_VAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.xGrailVault")) - 1));
    assert(_POTPOOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.potPool")) - 1));
    assert(_UNIPROXY_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.uniProxy")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _grail,
    address _xGrailVault,
    address _potPool,
    address _uniProxy
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _underlying,
      _grail,
      harvestMSIG
    );

    setAddress(_XGRAIL_VAULT_SLOT, _xGrailVault);
    setAddress(_POTPOOL_SLOT, _potPool);
    setAddress(_UNIPROXY_SLOT, _uniProxy);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
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

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  // We assume that all the tradings can be done on Uniswap
  function _liquidateRewards(uint256 _xGrailAmount) internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }

    address _rewardToken = rewardToken();
    address _universalLiquidator = universalLiquidator();
    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 balance = IERC20(token).balanceOf(address(this));
      if (balance == 0) {
          continue;
      }
      if (token != _rewardToken){
          IERC20(token).safeApprove(_universalLiquidator, 0);
          IERC20(token).safeApprove(_universalLiquidator, balance);
          IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, balance, 1, address(this));
      }
    }

    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    uint256 notifyBalance;
    if (_xGrailAmount > rewardBalance.mul(9)) {
      notifyBalance = rewardBalance.mul(10);
    } else {
      notifyBalance = rewardBalance.add(_xGrailAmount);
    }
    _notifyProfitInRewardToken(_rewardToken, notifyBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance < 1e6) {
      _handleXGrail();
      return;
    }

    _depositToGamma();
    _handleXGrail();
  }

  function _handleXGrail() internal {
    uint256 balance = IERC20(xGrail).balanceOf(address(this));
    if (balance == 0) { return; }
    address _xGrailVault = xGrailVault();
    address _potPool = potPool();

    IERC20(xGrail).safeApprove(_xGrailVault, 0);
    IERC20(xGrail).safeApprove(_xGrailVault, balance);
    IVault(_xGrailVault).deposit(balance);

    uint256 vaultBalance = IERC20(_xGrailVault).balanceOf(address(this));
    IERC20(_xGrailVault).safeTransfer(_potPool, vaultBalance);
    IPotPool(_potPool).notifyTargetRewardAmount(_xGrailVault, vaultBalance);
  }

  function _depositToGamma() internal {
    address _underlying = underlying();
    address _clearing = IUniProxy(uniProxy()).clearance();
    address _token0 = IHypervisor(_underlying).token0();
    address _token1 = IHypervisor(_underlying).token1();
    (uint256 toToken0, uint256 toToken1) = _calculateToTokenAmounts();
    (uint256 amount0, uint256 amount1) = _swapToTokens(_token0, _token1, toToken0, toToken1);
    (uint256 min1, uint256 max1) = IClearing(_clearing).getDepositAmount(_underlying, _token0, amount0);
    if (amount1 < min1) {
      (,uint256 max0) = IClearing(_clearing).getDepositAmount(_underlying, _token1, amount1);
      if (amount0 > max0) {
        amount0 = max0;
      }
    } else if (amount1 > max1) {
      amount1 = max1;
    }
    uint256[4] memory minIn = [uint(0), uint(0), uint(0), uint(0)];

    IERC20(_token0).safeApprove(_underlying, 0);
    IERC20(_token0).safeApprove(_underlying, amount0);
    IERC20(_token1).safeApprove(_underlying, 0);
    IERC20(_token1).safeApprove(_underlying, amount1);
    IUniProxy(uniProxy()).deposit(amount0, amount1, address(this), _underlying, minIn);
  }

  function _calculateToTokenAmounts() internal view returns(uint256, uint256){
    address pool = underlying();
    (uint256 poolBalance0, uint256 poolBalance1) = IHypervisor(pool).getTotalAmounts();
    address clearing = IUniProxy(uniProxy()).clearance();
    uint256 sqrtPrice0In1 = uint256(IClearing(clearing).getSqrtTwapX96(pool, 1));
    uint256 price0In1 = sqrtPrice0In1.mul(sqrtPrice0In1).div(uint(2**(96 * 2)).div(1e18));
    uint256 totalPoolBalanceIn1 = poolBalance0.mul(price0In1).div(1e18).add(poolBalance1);
    uint256 poolWeight0 = poolBalance0.mul(price0In1).div(totalPoolBalanceIn1);

    uint256 rewardBalance = IERC20(rewardToken()).balanceOf(address(this));
    uint256 toToken0 = rewardBalance.mul(poolWeight0).div(1e18);
    uint256 toToken1 = rewardBalance.sub(toToken0);
    return (toToken0, toToken1);
  }

  function _swapToTokens(
    address tokenOut0,
    address tokenOut1,
    uint256 toToken0,
    uint256 toToken1
  ) internal returns(uint256, uint256){
    address tokenIn = rewardToken();
    address _universalLiquidator = universalLiquidator();
    uint256 token0Amount;
    if (tokenIn != tokenOut0){
      IERC20(tokenIn).safeApprove(_universalLiquidator, 0);
      IERC20(tokenIn).safeApprove(_universalLiquidator, toToken0);
      IUniversalLiquidator(_universalLiquidator).swap(tokenIn, tokenOut0, toToken0, 1, address(this));
      token0Amount = IERC20(tokenOut0).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is the reward token itself
      token0Amount = toToken0;
    }

    uint256 token1Amount;
    if (tokenIn != tokenOut1){
      IERC20(tokenIn).safeApprove(_universalLiquidator, 0);
      IERC20(tokenIn).safeApprove(_universalLiquidator, toToken1);
      IUniversalLiquidator(_universalLiquidator).swap(tokenIn, tokenOut1, toToken1, 1, address(this));
      token1Amount = IERC20(tokenOut1).balanceOf(address(this));
    } else {
      // otherwise we assme token0 is the reward token itself
      token1Amount = toToken1;
    }
    return (token0Amount, token1Amount);
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    uint256 xGrailReward = IERC20(xGrail).balanceOf(address(this));
    _liquidateRewards(xGrailReward);
    IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
  }

  /*
  *   Withdraws all the asset to the vault
  */
  function withdrawToVault(uint256 amount) public restricted {
    IERC20(underlying()).safeTransfer(vault(), amount);
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
    uint256 xGrailReward = IERC20(xGrail).balanceOf(address(this));
    _liquidateRewards(xGrailReward);
  }

  /**
  * Can completely disable claiming rewards and selling. Good for emergency withdraw in the
  * simplest possible way.
  */
  function setSell(bool s) public onlyGovernance {
    _setSell(s);
  }

  function setXGrailVault(address _value) public onlyGovernance {
    require(xGrailVault() == address(0), "Hodl vault already set");
    setAddress(_XGRAIL_VAULT_SLOT, _value);
  }

  function xGrailVault() public view returns (address) {
    return getAddress(_XGRAIL_VAULT_SLOT);
  }

  function setPotPool(address _value) public onlyGovernance {
    require(potPool() == address(0), "PotPool already set");
    setAddress(_POTPOOL_SLOT, _value);
  }

  function potPool() public view returns (address) {
    return getAddress(_POTPOOL_SLOT);
  }

  function _setUniProxy(address _value) public onlyGovernance {
    setAddress(_UNIPROXY_SLOT, _value);
  }

  function uniProxy() public view returns (address) {
    return getAddress(_UNIPROXY_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }
}