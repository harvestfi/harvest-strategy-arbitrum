// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/aave/IAToken.sol";
import "../../base/interface/aave/IPool.sol";
import "../../base/interface/aave/IAaveIncentivesController.sol";

contract AaveRewardStrategy is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _ATOKEN_SLOT = 0x8cdee58637b787efaa2d78bb1da1e053a2c91e61640b32339bfbba65c00abd68;
  bytes32 internal constant _STORED_SUPPLIED_SLOT = 0x280539da846b4989609abdccfea039bd1453e4f710c670b29b9eeaca0730c1a2;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() public BaseUpgradeableStrategy() {
    assert(_ATOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.aToken")) - 1));
    assert(_STORED_SUPPLIED_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.storedSupplied")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _aToken,
    address _rewardToken
  )
  public initializer {
    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _aToken,
      _rewardToken,
      harvestMSIG
    );

    require(IAToken(_aToken).UNDERLYING_ASSET_ADDRESS() == _underlying, "Underlying mismatch");
    _setAToken(_aToken);
  }

  function currentSupplied() public view returns (uint256) {
    return IAToken(aToken()).balanceOf(address(this));
  }

  function storedSupplied() public view returns (uint256) {
    return getUint256(_STORED_SUPPLIED_SLOT);
  }

  function _updateStoredSupplied() internal {
    setUint256(_STORED_SUPPLIED_SLOT, currentSupplied());
  }

  function pendingFee() public view returns (uint256) {
    uint256 balanceIncrease = currentSupplied().sub(storedSupplied());
    uint256 fee = balanceIncrease.mul(strategistFeeNumerator().add(platformFeeNumerator()).add(profitSharingNumerator())).div(feeDenominator());
    return fee;
  }
  
  function depositArbCheck() public pure returns (bool) {
    // there's no arb here.
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == underlying() || token == aToken());
  }

  /**
  * Exits Moonwell and transfers everything to the vault.
  */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    _handleFee();
    _redeemMaximum();
    if (IERC20(_underlying).balanceOf(address(this)) > 0) {
      IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
    }
    _updateStoredSupplied();
  }

  function emergencyExit() external onlyGovernance {
    _handleFee();
    _redeemMaximum();
    _updateStoredSupplied();
  }

  function withdrawToVault(uint256 amountUnderlying) public restricted {
    address _underlying = underlying();
    _handleFee();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amountUnderlying <= balance) {
      IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
      return;
    }
    uint256 toRedeem = amountUnderlying.sub(balance);
    // get some of the underlying
    _redeem(toRedeem);
    // transfer the amount requested (or the amount we have) back to vault()
    IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
    balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      _supply(balance);
    }
    _updateStoredSupplied();
  }

  /**
  * Withdraws all assets, liquidates XVS, and invests again in the required ratio.
  */
  function doHardWork() public restricted {
    _handleFee();
    _claimReward();
    _liquidateReward();
    uint256 balance = IERC20(underlying()).balanceOf(address(this));
    if (balance > 0) {
      _supply(balance);
    }
    _updateStoredSupplied();
  }

  /**
  * Salvages a token.
  */
  function salvage(address recipient, address token, uint256 amount) public onlyGovernance {
    // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "token is defined as not salvagable");
    IERC20(token).safeTransfer(recipient, amount);
  }

  function _handleFee() internal {
    uint256 balanceIncrease = currentSupplied().sub(storedSupplied());
    _redeem(pendingFee());
    address _underlying = underlying();
    _notifyProfitInRewardToken(_underlying, balanceIncrease);
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      _supply(balance);
    }
    _updateStoredSupplied();
  }

  function _claimReward() internal {
    address _aToken = aToken();
    address incentivesController = IAToken(_aToken).getIncentivesController();
    address[] memory assets = new address[](1);
    assets[0] = _aToken;
    IAaveIncentivesController(incentivesController).claimAllRewards(assets, address(this));
  }

  function _liquidateReward() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
    address _rewardToken = rewardToken();
    address _universalLiquidator = universalLiquidator();
    for(uint256 i = 0; i < rewardTokens.length; i++){
      address token = rewardTokens[i];
      uint256 rewardBalance = IERC20(token).balanceOf(address(this));
      if (rewardBalance == 0) {
        continue;
      }
      if (token != _rewardToken){
          IERC20(token).safeApprove(_universalLiquidator, 0);
          IERC20(token).safeApprove(_universalLiquidator, rewardBalance);
          IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, rewardBalance, 1, address(this));
      }
    }

    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance == 0) {
      return;
    }

    address _underlying = underlying();
    if (_underlying != _rewardToken) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, _underlying, remainingRewardBalance, 1, address(this));
    }
  }

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    // underlying in this strategy + underlying redeemable from Radiant - debt
    return IERC20(underlying()).balanceOf(address(this))
    .add(currentSupplied())
    .sub(pendingFee());
  }

  /**
  * Supplies to Moonwel
  */
  function _supply(uint256 amount) internal {
    if (amount == 0){
      return;
    }
    address _underlying = underlying();
    address _pool = IAToken(aToken()).POOL();
    IERC20(_underlying).safeApprove(_pool, 0);
    IERC20(_underlying).safeApprove(_pool, amount);
     IPool(_pool).supply(_underlying, amount, address(this), 0);
  }

  function _redeem(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    address _pool = IAToken(aToken()).POOL();
     IPool(_pool).withdraw(underlying(), amountUnderlying, address(this));
  }

  function _redeemMaximum() internal {
    if (currentSupplied() > 0) {
      _redeem(type(uint).max);
    }
  }

  function _setAToken (address _target) internal {
    setAddress(_ATOKEN_SLOT, _target);
  }

  function aToken() public view returns (address) {
    return getAddress(_ATOKEN_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _setRewardToken(0x912CE59144191C1204E64559FE8253a0e49E6548);
    _finalizeUpgrade();
  }

  receive() external payable {}
}