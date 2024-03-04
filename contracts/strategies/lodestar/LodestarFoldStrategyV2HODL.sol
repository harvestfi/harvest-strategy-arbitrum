// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../base/interface/IUniversalLiquidator.sol";
import "../../base/interface/IVault.sol";
import "../../base/interface/IPotPool.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/lodestar/CTokenInterfaces.sol";
import "../../base/interface/lodestar/ComptrollerInterface.sol";
import "../../base/interface/balancer/IBVault.sol";
import "../../base/interface/weth/IWETH.sol";

contract LodestarFoldStrategyV2HODL is BaseUpgradeableStrategy {

  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant lode = address(0xF19547f9ED24aA66b03c3a552D181Ae334FBb8DB);
  address public constant bVault = address(0xBA12222222228d8Ba445958a75a0704d566BF2C8);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _CTOKEN_SLOT = 0x316ad921d519813e6e41c0e056b79e4395192c2b101f8b61cf5b94999360d568;
  bytes32 internal constant _COLLATERALFACTORNUMERATOR_SLOT = 0x129eccdfbcf3761d8e2f66393221fa8277b7623ad13ed7693a0025435931c64a;
  bytes32 internal constant _FACTORDENOMINATOR_SLOT = 0x4e92df66cc717205e8df80bec55fc1429f703d590a2d456b97b74f0008b4a3ee;
  bytes32 internal constant _BORROWTARGETFACTORNUMERATOR_SLOT = 0xa65533f4b41f3786d877c8fdd4ae6d27ada84e1d9c62ea3aca309e9aa03af1cd;
  bytes32 internal constant _FOLD_SLOT = 0x1841be4c16015a744c9fbf595f7c6b32d40278c16c1fc7cf2de88c6348de44ba;
  bytes32 internal constant _LODE_VAULT_SLOT = 0xf7566b617fb729f096ab296b2ea55a2d2da7aa17043d001c3834a520a9963a7f;
  bytes32 internal constant _POTPOOL_SLOT = 0x7f4b50847e7d7a4da6a6ea36bfb188c77e9f093697337eb9a876744f926dd014;

  uint256 public suppliedInUnderlying;
  uint256 public borrowedInUnderlying;

  bool internal makingFlashDeposit;
  bool internal makingFlashWithdrawal;

  // this would be reset on each upgrade
  address[] public rewardTokens;

  constructor() public BaseUpgradeableStrategy() {
    assert(_CTOKEN_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.cToken")) - 1));
    assert(_COLLATERALFACTORNUMERATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.collateralFactorNumerator")) - 1));
    assert(_FACTORDENOMINATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.factorDenominator")) - 1));
    assert(_BORROWTARGETFACTORNUMERATOR_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.borrowTargetFactorNumerator")) - 1));
    assert(_FOLD_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.fold")) - 1));
    assert(_LODE_VAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.lodeVault")) - 1));
    assert(_POTPOOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.potPool")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _cToken,
    address _comptroller,
    uint256 _borrowTargetFactorNumerator,
    uint256 _collateralFactorNumerator,
    uint256 _factorDenominator,
    bool _fold,
    address _lodeVault,
    address _potPool
  )
  public initializer {
    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _comptroller,
      weth,
      harvestMSIG
    );
    _setCToken(_cToken);

    _setFactorDenominator(_factorDenominator);
    require(_collateralFactorNumerator <= factorDenominator(), "CF too high");
    setUint256(_COLLATERALFACTORNUMERATOR_SLOT, _collateralFactorNumerator);
    require(_borrowTargetFactorNumerator < _collateralFactorNumerator, "BF too high");
    setUint256(_BORROWTARGETFACTORNUMERATOR_SLOT, _borrowTargetFactorNumerator);
    
    setBoolean(_FOLD_SLOT, _fold);
    address[] memory markets = new address[](1);
    markets[0] = _cToken;
    ComptrollerInterface(_comptroller).enterMarkets(markets);

    setAddress(_LODE_VAULT_SLOT, _lodeVault);
    setAddress(_POTPOOL_SLOT, _potPool);
  }

  modifier updateSupplyInTheEnd() {
    _;
    address _cToken = cToken();
    // amount we supplied
    suppliedInUnderlying = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    borrowedInUnderlying = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
  }

  function depositArbCheck() external pure returns (bool) {
    // there's no arb here.
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying() || token == cToken());
  }

  /**
  * The strategy invests by supplying the underlying as a collateral.
  */
  function _investAllUnderlying() internal onlyNotPausedInvesting updateSupplyInTheEnd {
    address _underlying = underlying();
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance > 0) {
      _supply(underlyingBalance);
    }
    if (!fold()) {
      return;
    }
    _depositWithFlashloan();
  }

  /**
  * Exits Moonwell and transfers everything to the vault.
  */
  function withdrawAllToVault() external restricted updateSupplyInTheEnd {
    address _underlying = underlying();
    _withdrawMaximum(true);
    if (IERC20(_underlying).balanceOf(address(this)) > 0) {
      IERC20(_underlying).safeTransfer(vault(), IERC20(_underlying).balanceOf(address(this)));
    }
  }

  function emergencyExit() external onlyGovernance updateSupplyInTheEnd {
    _withdrawMaximum(false);
  }

  function _withdrawMaximum(bool claim) internal updateSupplyInTheEnd {
    if (claim) {
      _claimRewards();
      _liquidateRewards();
    }
    _redeemMaximumWithFlashloan();
  }

  function withdrawToVault(uint256 amountUnderlying) external restricted updateSupplyInTheEnd {
    address _underlying = underlying();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amountUnderlying <= balance) {
      IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
      return;
    }
    uint256 toRedeem = amountUnderlying.sub(balance);
    // get some of the underlying
    _redeemPartial(toRedeem);
    // transfer the amount requested (or the amount we have) back to vault()
    IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
    balance = IERC20(_underlying).balanceOf(address(this));
    if (balance > 0) {
      _investAllUnderlying();
    }
  }

  /**
  * Withdraws all assets, liquidates XVS, and invests again in the required ratio.
  */
  function doHardWork() external restricted {
    _claimRewards();
    _liquidateRewards();
    _investAllUnderlying();
  }

  /**
  * Redeems `amountUnderlying` or fails.
  */
  function _redeemPartial(uint256 amountUnderlying) internal {
    address _underlying = underlying();
    uint256 balanceBefore = IERC20(_underlying).balanceOf(address(this));
    _redeemWithFlashloan(
      amountUnderlying,
      fold()? borrowTargetFactorNumerator():0
      );
    uint256 balanceAfter = IERC20(_underlying).balanceOf(address(this));
    require(balanceAfter.sub(balanceBefore) >= amountUnderlying, "Redeem amount");
  }

  /**
  * Salvages a token.
  */
  function salvage(address recipient, address token, uint256 amount) external onlyGovernance {
    // To make sure that governance cannot come in and take away the coins
    require(!unsalvagableTokens(token), "NS");
    IERC20(token).safeTransfer(recipient, amount);
  }

  function _claimRewards() internal {
    ComptrollerInterface(rewardPool()).claimComp(address(this));
  }

  function addRewardToken(address _token) external onlyGovernance {
    rewardTokens.push(_token);
  }

  function _liquidateRewards() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
    address _rewardToken = rewardToken();
    address _universalLiquidator = universalLiquidator();
    uint256 hodledInRT;
    uint256 totalFee = strategistFeeNumerator().add(platformFeeNumerator()).add(profitSharingNumerator());
    uint256 _feeDenominator = feeDenominator();
    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 balance = IERC20(token).balanceOf(address(this));
      if (balance == 0) {
        continue;
      }
      if (token == lode) {
        uint256 toHodl = balance.mul(_feeDenominator.sub(totalFee)).div(_feeDenominator);
        _hodlLode(toHodl);
        balance = IERC20(token).balanceOf(address(this));
        hodledInRT = balance.mul(_feeDenominator.sub(totalFee)).div(totalFee);
      }
      if (token != _rewardToken){
        uint256 rtBefore = IERC20(_rewardToken).balanceOf(address(this));
        IERC20(token).safeApprove(_universalLiquidator, 0);
        IERC20(token).safeApprove(_universalLiquidator, balance);
        IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, balance, 1, address(this));
        uint256 rtGained = IERC20(_rewardToken).balanceOf(address(this)).sub(rtBefore);
        if (token == lode) {
          hodledInRT = rtGained.mul(_feeDenominator.sub(totalFee)).div(totalFee);
        }
      }
    }
    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this)).add(hodledInRT);
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance <= 1e10) {
      return;
    }
  
    address _underlying = underlying();
    if (_underlying != _rewardToken) {
      IERC20(_rewardToken).safeApprove(_universalLiquidator, 0);
      IERC20(_rewardToken).safeApprove(_universalLiquidator, remainingRewardBalance);
      IUniversalLiquidator(_universalLiquidator).swap(_rewardToken, _underlying, remainingRewardBalance, 1, address(this));
    }
  }

  function _hodlLode(uint256 toHodl) internal {
    address _lodeVault = lodeVault();
    address _potPool = potPool();

    IERC20(lode).safeApprove(_lodeVault, 0);
    IERC20(lode).safeApprove(_lodeVault, toHodl);
    IVault(_lodeVault).deposit(toHodl);

    uint256 vaultBalance = IERC20(_lodeVault).balanceOf(address(this));
    IERC20(_lodeVault).safeTransfer(_potPool, vaultBalance);
    IPotPool(_potPool).notifyTargetRewardAmount(_lodeVault, vaultBalance);
  }

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    // underlying in this strategy + underlying redeemable from Radiant - debt
    return IERC20(underlying()).balanceOf(address(this))
    .add(suppliedInUnderlying)
    .sub(borrowedInUnderlying);
  }

  /**
  * Supplies to Moonwel
  */
  function _supply(uint256 amount) internal {
    if (amount == 0){
      return;
    }
    address _underlying = underlying();
    address _cToken = cToken();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amount < balance) {
      balance = amount;
    }
    if (_underlying == weth) {
      IWETH(weth).withdraw(balance);
      CErc20Interface(_cToken).mint{value: balance}();
    } else {
      IERC20(_underlying).safeApprove(_cToken, 0);
      IERC20(_underlying).safeApprove(_cToken, balance);
      CErc20Interface(_cToken).mint(balance);
    }
  }

  /**
  * Borrows against the collateral
  */
  function _borrow(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    // Borrow, check the balance for this contract's address
    CErc20Interface(cToken()).borrow(amountUnderlying);
    if(underlying() == weth){
      IWETH(weth).deposit{value: address(this).balance}();
    }
  }

  function _redeem(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    CErc20Interface(cToken()).redeemUnderlying(amountUnderlying);
    if(underlying() == weth){
      IWETH(weth).deposit{value: address(this).balance}();
    }
  }

  function _repay(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    address _underlying = underlying();
    address _cToken = cToken();
    if (_underlying == weth) {
      IWETH(weth).withdraw(amountUnderlying);
      CErc20Interface(_cToken).repayBorrow{value: amountUnderlying}();
    } else {
      IERC20(_underlying).safeApprove(_cToken, 0);
      IERC20(_underlying).safeApprove(_cToken, amountUnderlying);
      CErc20Interface(_cToken).repayBorrow(amountUnderlying);
    }
  }

  function _redeemMaximumWithFlashloan() internal {
    address _cToken = cToken();
    // amount of liquidity in Radiant
    uint256 available = CTokenInterface(_cToken).getCash();
    // amount we supplied
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 balance = supplied.sub(borrowed);

    _redeemWithFlashloan(Math.min(available, balance), 0);
    supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    uint256 exchangeRate = CTokenInterface(_cToken).exchangeRateStored().div(1e18);
    if (supplied > exchangeRate) {
      _redeem(supplied);
    }
  }

  function _depositWithFlashloan() internal {
    address _cToken = cToken();
    uint _denom = factorDenominator();
    uint _borrowNum = borrowTargetFactorNumerator();
    // amount we supplied
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 balance = supplied.sub(borrowed);
    uint256 borrowTarget = balance.mul(_borrowNum).div(_denom.sub(_borrowNum));
    uint256 borrowDiff;
    if (borrowed > borrowTarget) {
      _redeemPartial(0);
      borrowDiff = 0;
    } else {
      borrowDiff = borrowTarget.sub(borrowed);
      uint256 borrowCap = ComptrollerInterface(rewardPool()).borrowCaps(_cToken);
      uint256 totalBorrows = CTokenInterface(_cToken).totalBorrows();
      uint256 borrowAvail;
      if (totalBorrows < borrowCap) {
        borrowAvail = borrowCap.sub(totalBorrows).sub(1);
      } else {
        borrowAvail = 0;
      }
      if (borrowDiff > borrowAvail){
        borrowDiff = borrowAvail;
      }
    }

    address _underlying = underlying();
    uint256 balancerBalance = IERC20(_underlying).balanceOf(bVault);

    if (borrowDiff > balancerBalance) {
      _depositNoFlash(supplied, borrowed, _cToken, _denom, _borrowNum);
    } else {
      address[] memory tokens = new address[](1);
      uint256[] memory amounts = new uint256[](1);
      bytes memory userData = abi.encode(0);
      tokens[0] = underlying();
      amounts[0] = borrowDiff;
      makingFlashDeposit = true;
      IBVault(bVault).flashLoan(address(this), tokens, amounts, userData);
      makingFlashDeposit = false;
    }
  }

  function _redeemWithFlashloan(uint256 amount, uint256 borrowTargetFactorNumerator) internal {
    address _cToken = cToken();
    // amount we supplied
    uint256 supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    // amount we borrowed
    uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
    uint256 newBorrowTarget;
    {
        uint256 oldBalance = supplied.sub(borrowed);
        uint256 newBalance = oldBalance.sub(amount);
        newBorrowTarget = newBalance.mul(borrowTargetFactorNumerator).div(factorDenominator().sub(borrowTargetFactorNumerator));
    }
    uint256 borrowDiff;
    if (borrowed < newBorrowTarget) {
      borrowDiff = 0;
    } else {
      borrowDiff = borrowed.sub(newBorrowTarget);
    }
    address _underlying = underlying();
    uint256 balancerBalance = IERC20(_underlying).balanceOf(bVault);

    if (borrowDiff > balancerBalance) {
      _redeemNoFlash(amount, supplied, borrowed, _cToken, factorDenominator(), borrowTargetFactorNumerator);
    } else {
      address[] memory tokens = new address[](1);
      uint256[] memory amounts = new uint256[](1);
      bytes memory userData = abi.encode(0);
      tokens[0] = underlying();
      amounts[0] = borrowDiff;
      makingFlashWithdrawal = true;
      IBVault(bVault).flashLoan(address(this), tokens, amounts, userData);
      makingFlashWithdrawal = false;
      _redeem(amount);
    }
  }

  function receiveFlashLoan(IERC20[] memory /*tokens*/, uint256[] memory amounts, uint256[] memory feeAmounts, bytes memory /*userData*/) external {
    require(msg.sender == bVault);
    require(!makingFlashDeposit || !makingFlashWithdrawal, "Only one can be true");
    require(makingFlashDeposit || makingFlashWithdrawal, "One has to be true");
    address _underlying = underlying();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    uint256 toRepay = amounts[0].add(feeAmounts[0]);
    if (makingFlashDeposit){
      _supply(balance);
      _borrow(toRepay);
    } else {
      address _cToken = cToken();
      uint256 borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
      uint256 repaying = Math.min(balance, borrowed);
      IERC20(_underlying).safeApprove(_cToken, 0);
      IERC20(_underlying).safeApprove(_cToken, repaying);
      _repay(repaying);
      _redeem(toRepay);
    }
    IERC20(_underlying).safeTransfer(bVault, toRepay);
  }

  function _depositNoFlash(uint256 supplied, uint256 borrowed, address _cToken, uint256 _denom, uint256 _borrowNum) internal {
    address _underlying = underlying();
    uint256 balance = supplied.sub(borrowed);
    uint256 borrowTarget = balance.mul(_borrowNum).div(_denom.sub(_borrowNum));
    {
      uint256 borrowCap = ComptrollerInterface(rewardPool()).borrowCaps(_cToken);
      uint256 totalBorrows = CTokenInterface(_cToken).totalBorrows();
      uint256 borrowAvail;
      if (totalBorrows < borrowCap) {
        borrowAvail = borrowCap.sub(totalBorrows).sub(1);
      } else {
        borrowAvail = 0;
      }
      if (borrowTarget.sub(borrowed) > borrowAvail) {
        borrowTarget = borrowed.add(borrowAvail);
      }
    }
    while (borrowed < borrowTarget) {
      uint256 wantBorrow = borrowTarget.sub(borrowed);
      uint256 maxBorrow = supplied.mul(collateralFactorNumerator()).div(_denom).sub(borrowed);
      _borrow(Math.min(wantBorrow, maxBorrow));
      uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
      if (underlyingBalance > 0) {
        _supply(underlyingBalance);
      }
      //update parameters
      borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
      supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
      balance = supplied.sub(borrowed);
    }
  }

  function _redeemNoFlash(uint256 amount, uint256 supplied, uint256 borrowed, address _cToken, uint256 _denom, uint256 _borrowNum) internal {
    address _underlying = underlying();
    uint256 newBorrowTarget;
    {
        uint256 oldBalance = supplied.sub(borrowed);
        uint256 newBalance = oldBalance.sub(amount);
        newBorrowTarget = newBalance.mul(_borrowNum).div(_denom.sub(_borrowNum));
    }
    while (borrowed > newBorrowTarget) {
      uint256 requiredCollateral = borrowed.mul(_denom).div(collateralFactorNumerator());
      uint256 toRepay = borrowed.sub(newBorrowTarget);
      // redeem just as much as needed to repay the loan
      // supplied - requiredCollateral = max redeemable, amount + repay = needed
      uint256 toRedeem = Math.min(supplied.sub(requiredCollateral), amount.add(toRepay));
      _redeem(toRedeem);
      // now we can repay our borrowed amount
      uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
      _repay(Math.min(toRepay, underlyingBalance));
      // update the parameters
      borrowed = CTokenInterface(_cToken).borrowBalanceCurrent(address(this));
      supplied = CTokenInterface(_cToken).balanceOfUnderlying(address(this));
    }
    uint256 underlyingBalance = IERC20(_underlying).balanceOf(address(this));
    if (underlyingBalance < amount) {
      uint256 toRedeem = amount.sub(underlyingBalance);
      uint256 balance = supplied.sub(borrowed);
      // redeem the most we can redeem
      _redeem(Math.min(toRedeem, balance));
    }
  }

  // updating collateral factor
  // note 1: one should settle the loan first before calling this
  // note 2: collateralFactorDenominator is 1000, therefore, for 20%, you need 200
  function _setCollateralFactorNumerator(uint256 _numerator) internal {
    require(_numerator <= uint(820).mul(factorDenominator()).div(1000), "Collateral factor cannot be this high");
    require(_numerator > borrowTargetFactorNumerator(), "Collateral factor should be higher than borrow target");
    setUint256(_COLLATERALFACTORNUMERATOR_SLOT, _numerator);
  }

  function collateralFactorNumerator() public view returns (uint256) {
    return getUint256(_COLLATERALFACTORNUMERATOR_SLOT);
  }

  function _setFactorDenominator(uint256 _denominator) internal {
    setUint256(_FACTORDENOMINATOR_SLOT, _denominator);
  }

  function factorDenominator() internal view returns (uint256) {
    return getUint256(_FACTORDENOMINATOR_SLOT);
  }

  function setBorrowTargetFactorNumerator(uint256 _numerator) public onlyGovernance {
    require(_numerator < collateralFactorNumerator(), "Target should be lower than collateral limit");
    setUint256(_BORROWTARGETFACTORNUMERATOR_SLOT, _numerator);
  }

  function borrowTargetFactorNumerator() public view returns (uint256) {
    return getUint256(_BORROWTARGETFACTORNUMERATOR_SLOT);
  }

  function setFold (bool _fold) public onlyGovernance {
    setBoolean(_FOLD_SLOT, _fold);
  }

  function fold() public view returns (bool) {
    return getBoolean(_FOLD_SLOT);
  }

  function _setCToken (address _target) internal {
    setAddress(_CTOKEN_SLOT, _target);
  }

  function cToken() internal view returns (address) {
    return getAddress(_CTOKEN_SLOT);
  }

  function setLodeVault(address _value) public onlyGovernance {
    setAddress(_LODE_VAULT_SLOT, _value);
  }

  function lodeVault() internal view returns (address) {
    return getAddress(_LODE_VAULT_SLOT);
  }

  function setPotPool(address _value) public onlyGovernance {
    setAddress(_POTPOOL_SLOT, _value);
  }

  function potPool() internal view returns (address) {
    return getAddress(_POTPOOL_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance updateSupplyInTheEnd {
    _finalizeUpgrade();
  }

  receive() external payable {}
}