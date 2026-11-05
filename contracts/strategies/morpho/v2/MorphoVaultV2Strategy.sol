// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../../../base/interface/IUniversalLiquidator.sol";
import "../../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../../base/interface/morpho/IMorphoVault.sol";
import "../../../base/interface/morpho/IMorphoVaultV2.sol";

contract MorphoVaultV2Strategy is BaseUpgradeableStrategy {

  using SafeERC20 for IERC20;

  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _MORPHO_VAULT_SLOT = 0xf5b51c17c9e35d4327e4aa5b82628726ecdd06e6cb73d4658ac1e871f3879ea3;
  bytes32 internal constant _STORED_SUPPLIED_SLOT = 0x280539da846b4989609abdccfea039bd1453e4f710c670b29b9eeaca0730c1a2;
  bytes32 internal constant _PENDING_FEE_SLOT = 0x0af7af9f5ccfa82c3497f40c7c382677637aee27293a6243a22216b51481bd97;

    // this would be reset on each upgrade
  address[] public rewardTokens;

  struct Stream {
    uint256 lastUpdate;     // last timestamp we updated unlocked accounting
    uint256 periodFinish;   // end of current stream period
    uint256 rate;          // tokens per second (truncated), in token's natural units

    uint256 accounted;     // how many tokens are reserved/managed by the stream (locked+unlocked-not-yet-sold)
    uint256 unlocked;      // unlocked amount accumulated since last sale (ready to sell)
    uint256 duration;      // distribution duration (seconds). 0 disables streaming (sell all)
  }

  mapping(address => Stream) internal _stream;

  event ForcedWithdrawal(uint256 withdrawn, uint256 penalty);

  constructor() BaseUpgradeableStrategy() {
    assert(_MORPHO_VAULT_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.morphoVault")) - 1));
    assert(_STORED_SUPPLIED_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.storedSupplied")) - 1));
    assert(_PENDING_FEE_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.pendingFee")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _morphoVault,
    address _rewardToken
  )
  public initializer {
    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _morphoVault,
      _rewardToken,
      harvestMSIG
    );

    require(IMorphoVault(_morphoVault).asset() == _underlying, "Underlying mismatch");
    _setMorphoVault(_morphoVault);
  }

  function currentSupplied() public view returns (uint256) {
    address _morphoVault = morphoVault();
    return IMorphoVault(_morphoVault).convertToAssets(IMorphoVault(_morphoVault).balanceOf(address(this)));
  }

  function storedSupplied() public view returns (uint256) {
    return getUint256(_STORED_SUPPLIED_SLOT);
  }

  function _updateStoredSupplied() internal {
    setUint256(_STORED_SUPPLIED_SLOT, currentSupplied());
  }

  function totalFeeNumerator() public view returns (uint256) {
    return strategistFeeNumerator() + platformFeeNumerator() + profitSharingNumerator();
  }

  function pendingFee() public view returns (uint256) {
    return getUint256(_PENDING_FEE_SLOT);
  }

  function _accrueFee() internal {
    uint256 fee;
    if (currentSupplied() > storedSupplied()) {
      uint256 balanceIncrease = currentSupplied() - storedSupplied();
      fee = balanceIncrease * totalFeeNumerator() / feeDenominator();
    }
    setUint256(_PENDING_FEE_SLOT, pendingFee() + fee);
  }

  function feeFloor() public view virtual returns (uint256) {
    return 1e3;
  }

  function _handleFee() internal {
    _accrueFee();
    uint256 fee = pendingFee();
    uint256 floor = feeFloor();
    if (fee > floor) {
      address _underlying = underlying();
      uint256 availableBalance = IERC20(_underlying).balanceOf(address(this));
      if (availableBalance < fee) {
        // Only ask the Morpho vault for the shortfall, and never for more than the position
        // is actually worth right now. That is not the same as what the vault can pay: a
        // Vault V2 serves withdrawals from its idle balance and its liquidity adapter only,
        // and reports `maxWithdraw` as zero whatever it holds, so there is nothing to size
        // the request against. If it cannot pay, the fee waits for a later call rather than
        // taking the hard work down with it.
        uint256 redeemable = Math.min(fee - availableBalance, currentSupplied());
        if (redeemable > 0) {
          try IMorphoVault(morphoVault()).withdraw(redeemable, address(this), address(this)) {} catch {}
        }
      }
      fee = Math.min(fee, IERC20(_underlying).balanceOf(address(this)));
      // The RewardForwarder swaps the fee as it receives it, so a part payment has to clear
      // the floor just as the whole fee does.
      if (fee <= floor) {
        return;
      }
      uint256 balanceIncrease = fee * feeDenominator() / totalFeeNumerator();
      _notifyProfitInRewardToken(_underlying, balanceIncrease);
      setUint256(_PENDING_FEE_SLOT, pendingFee() - fee);
    }
  }
  
  function depositArbCheck() public pure returns (bool) {
    // there's no arb here.
    return true;
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == underlying() || token == morphoVault());
  }

  /**
  * Exits Moonwell and transfers everything to the vault.
  */
  function withdrawAllToVault() public restricted {
    address _underlying = underlying();
    _handleFee();
    _liquidateRewards();
    _redeemMaximum();
    // Keep back whatever fee `_handleFee` could not pay out - it is below the dust floor,
    // or the yield source refused the redemption. Handing it to the vault along with
    // everything else would leave `pendingFee` with nothing behind it, and
    // `investedUnderlyingBalance()` would then report less than zero.
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    uint256 fee = pendingFee();
    if (balance > fee) {
      IERC20(_underlying).safeTransfer(vault(), balance - fee);
    }
    _updateStoredSupplied();
  }

  function emergencyExit() external onlyGovernance {
    _accrueFee();
    _redeemMaximum();
    _updateStoredSupplied();
  }

  /**
  * A withdrawal for when the Morpho vault cannot pay one. A Vault V2 pays out of its idle
  * balance, topped up from its liquidity adapter if it has one; whatever else it holds has
  * to be deallocated first. `forceDeallocate` lets any depositor do that, for a penalty the
  * Morpho vault takes out of that depositor's shares. This deallocates what it is told to
  * and withdraws in the same call, before anyone else can get to what it paid to free, and
  * sends the proceeds to the vault.
  *
  * `adapters`, `data` and `assets` are what to deallocate, entry by entry. `data` is whatever
  * the adapter expects: the abi-encoded market parameters for a market adapter, nothing for
  * a vault adapter. The penalty is charged on everything deallocated, and anything freed
  * beyond what is withdrawn here is left idle for other depositors, so size the entries to
  * the withdrawal. A market can only give back what is not lent out.
  *
  * `amountUnderlying` is how much to send to the vault. It is cut down to what the position
  * is worth net of the pending fee, and to what the Morpho vault holds idle once the
  * deallocations are done - the liquidity adapter is not drawn on - so the maximum takes
  * everything that can be had. `maxPenalty` is the most underlying the deallocations are
  * allowed to cost.
  *
  * The next hard work supplies whatever the vault invests again, so if the funds are to
  * stay out, lower the fraction the vault invests first.
  */
  function forceWithdrawToVault(
    address[] calldata adapters,
    bytes[] calldata data,
    uint256[] calldata assets,
    uint256 amountUnderlying,
    uint256 maxPenalty
  ) external onlyGovernance {
    _accrueFee();
    uint256 penalty = _forceDeallocate(adapters, data, assets);
    require(penalty <= maxPenalty, "Penalty too high");
    uint256 withdrawn = _redeemIdle(amountUnderlying);
    _updateStoredSupplied();
    emit ForcedWithdrawal(withdrawn, penalty);
  }

  function _forceDeallocate(
    address[] calldata adapters,
    bytes[] calldata data,
    uint256[] calldata assets
  ) internal returns (uint256 penalty) {
    require(adapters.length == data.length && adapters.length == assets.length, "Length mismatch");
    address _morphoVault = morphoVault();
    uint256 supplied = currentSupplied();
    for (uint256 i; i < adapters.length; i++) {
      IMorphoVaultV2(_morphoVault).forceDeallocate(adapters[i], data[i], assets[i], address(this));
    }
    // The penalty is taken in shares, so it shows up as a smaller position.
    uint256 suppliedAfter = currentSupplied();
    penalty = supplied > suppliedAfter ? supplied - suppliedAfter : 0;
  }

  /**
  * Withdraws up to `amountUnderlying` out of what the Morpho vault holds idle and sends it
  * to the vault.
  */
  function _redeemIdle(uint256 amountUnderlying) internal returns (uint256 toVault) {
    address _underlying = underlying();
    uint256 supplied = currentSupplied();
    uint256 idle = IERC20(_underlying).balanceOf(morphoVault());
    uint256 fee = Math.min(pendingFee(), supplied);
    toVault = Math.min(Math.min(supplied - fee, amountUnderlying), idle);
    // The fee comes out as well if the Morpho vault can spare it, and waits here for the
    // next hard work. Left supplied it would go on earning, and that is a position a later
    // exit would have to get out of a vault that may have nothing to pay it with.
    uint256 toKeep = Math.min(fee, idle - toVault);
    _redeem(toVault + toKeep);
    if (toVault > 0) {
      IERC20(_underlying).safeTransfer(vault(), toVault);
    }
  }

  function withdrawToVault(uint256 amountUnderlying) public restricted {
    _accrueFee();
    address _underlying = underlying();
    uint256 balance = IERC20(_underlying).balanceOf(address(this));
    if (amountUnderlying <= balance) {
      IERC20(_underlying).safeTransfer(vault(), amountUnderlying);
      _updateStoredSupplied();
      return;
    }
    uint256 toRedeem = amountUnderlying - balance;
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

  function addRewardToken(address _token) public onlyGovernance {
    rewardTokens.push(_token);
  }

  function _removeRewardToken(address _token) internal {
    uint256 length = rewardTokens.length;
    for (uint256 i; i < length; i++) {
      if (rewardTokens[i] == _token) {
        rewardTokens[i] = rewardTokens[length - 1];
        rewardTokens.pop();
        delete _stream[_token];
        return;
      }
    }
  }

  function setSell(bool s) public onlyGovernance {
    _setSell(s);
  }

  function _liquidateRewards() internal {
    if (!sell()) {
      // Profits can be disabled for possible simplified and rapid exit
      emit ProfitsNotCollected(sell(), false);
      return;
    }
    address _rewardToken = rewardToken();
    address _universalLiquidator = universalLiquidator();
    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      if (token == _rewardToken) continue;
      _syncRewardStream(token);
      uint256 toSell = _pullClaimable(token);
      if (toSell > _minSellAmount(token)) {
        IERC20(token).safeApprove(_universalLiquidator, 0);
        IERC20(token).safeApprove(_universalLiquidator, toSell);
        IUniversalLiquidator(_universalLiquidator).swap(token, _rewardToken, toSell, 1, address(this));
      }
    }
    uint256 rewardBalance = IERC20(_rewardToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_rewardToken, rewardBalance);
    uint256 remainingRewardBalance = IERC20(_rewardToken).balanceOf(address(this));

    if (remainingRewardBalance <= 1e12) {
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
  * The smallest amount of a reward token worth handing to the liquidator: a millionth of a
  * whole token. Less than that can come out of the swap as nothing, which reverts it. What
  * is held back is not lost - it is no longer accounted for, so `_syncRewardStream` picks
  * it up as newly arrived on the next hard work.
  */
  function _minSellAmount(address token) internal view returns (uint256) {
    uint256 decimals = IERC20Metadata(token).decimals();
    return decimals > 6 ? 10 ** (decimals - 6) : 0;
  }

  function distributionTime(address token) public view returns (uint256) {
    return _stream[token].duration;
  }

  function sellable(address token) public view returns (uint256) {
    Stream memory stream = _stream[token];
    if (stream.duration == 0) {
      return IERC20(token).balanceOf(address(this));
    }
    uint256 unlockedAccrued = stream.unlocked;
    uint256 last = stream.lastUpdate;
    if (last == 0) return unlockedAccrued;

    uint256 nowTs = block.timestamp;
    uint256 effEnd = Math.min(nowTs, stream.periodFinish);
    if (effEnd <= last) return unlockedAccrued;

    uint256 dt = effEnd - last;
    return unlockedAccrued + (dt * stream.rate);
  }

  function _accrueUnlocked(address token) internal {
    Stream storage stream = _stream[token];
    uint256 nowTs = block.timestamp;

    uint256 last = stream.lastUpdate;
    if (last == 0) {
      stream.lastUpdate = nowTs;
      return;
    }

    uint256 effEnd = Math.min(nowTs, uint256(stream.periodFinish));
    if (effEnd <= last) {
      return;
    }

    uint256 dt = effEnd - last;
    uint256 unlockedNow = dt * uint256(stream.rate);

    if (unlockedNow > 0) {
      stream.unlocked += unlockedNow;
    }

    stream.lastUpdate = effEnd;
  }

  function _syncRewardStream(address token) internal {
    Stream storage stream = _stream[token];
    uint256 nowTs = block.timestamp;

    // If streaming is disabled, we don't need to track anything.
    if (stream.duration == 0) {
      // keep accounting minimal: avoid stale accounted/unlocked causing confusion.
      stream.accounted = 0;
      stream.unlocked = 0;
      stream.rate = 0;
      stream.lastUpdate = nowTs;
      stream.periodFinish = nowTs;
      return;
    }

    _accrueUnlocked(token);

    uint256 bal = IERC20(token).balanceOf(address(this));
    uint256 accounted = stream.accounted;
    uint256 newlyArrived = (bal > accounted) ? (bal - accounted) : 0;

    if (newlyArrived == 0) {
      return;
    }

    uint256 duration = stream.duration;

    uint256 leftover = 0;
    if (nowTs < uint256(stream.periodFinish)) {
      uint256 remaining = uint256(stream.periodFinish) - nowTs;
      leftover = remaining * uint256(stream.rate);
    }

    uint256 totalToStream = newlyArrived + leftover;
    uint256 newRate = totalToStream / duration;

    stream.rate = newRate;
    stream.lastUpdate = nowTs;
    stream.periodFinish = nowTs + duration;

    // 4) Increase accounted by the newly arrived amount (we now manage it)
    stream.accounted = accounted + newlyArrived;
  }

  function _pullClaimable(address token) internal returns (uint256 amount) {
    Stream storage stream = _stream[token];

    if (stream.duration == 0) {
      amount = IERC20(token).balanceOf(address(this));
      return amount;
    }

    _accrueUnlocked(token);

    amount = stream.unlocked;
    if (amount == 0) return 0;

    uint256 bal = IERC20(token).balanceOf(address(this));
    amount = Math.min(amount, bal);

    stream.unlocked -= amount;

    if (stream.accounted >= amount) {
      stream.accounted -= amount;
    } else {
      // very defensive; should not happen unless token is weird (rebasing/fee-on-transfer)
      stream.accounted = 0;
    }
  }

  /**
  * Withdraws all assets, liquidates XVS, and invests again in the required ratio.
  */
  function doHardWork() public restricted {
    _handleFee();
    _claimGeneralIncentives();
    _liquidateRewards();
    _supply(IERC20(underlying()).balanceOf(address(this)));
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

  /**
  * Returns the current balance.
  */
  function investedUnderlyingBalance() public view returns (uint256) {
    uint256 total = IERC20(underlying()).balanceOf(address(this)) + storedSupplied();
    uint256 fee = pendingFee();
    // Clamped rather than subtracted outright: this is read by every vault entrypoint, so
    // an underflow here would take deposits, withdrawals and the share price down with it.
    return total > fee ? total - fee : 0;
  }

  /**
  * Supplies to Moonwel
  */
  function _supply(uint256 amount) internal {
    if (amount == 0){
      return;
    }
    address _underlying = underlying();
    address _morphoVault = morphoVault();
    IERC20(_underlying).safeApprove(_morphoVault, 0);
    IERC20(_underlying).safeApprove(_morphoVault, amount);
    IMorphoVault(_morphoVault).deposit(amount, address(this));
  }

  function _redeem(uint256 amountUnderlying) internal {
    if (amountUnderlying == 0){
      return;
    }
    IMorphoVault(morphoVault()).withdraw(amountUnderlying, address(this), address(this));
  }

  function _redeemMaximum() internal {
    // The fee is deliberately left supplied: it doubles as the rounding margin that keeps
    // `withdraw` from asking the Morpho vault for more than the shares can cover. Clamped
    // rather than subtracted outright, so that a fee larger than what is left cannot revert
    // the exit.
    uint256 supplied = currentSupplied();
    uint256 fee = pendingFee();
    if (supplied > fee) {
      uint256 toRedeem = supplied - fee;
      if (toRedeem > feeFloor()) {
        _redeem(toRedeem);
      } else {
        // Dust is not worth failing an exit over. If the Morpho vault cannot pay even
        // that, it stays behind.
        try IMorphoVault(morphoVault()).withdraw(toRedeem, address(this), address(this)) {} catch {}
      }
    }
  }

  function _setMorphoVault (address _target) internal {
    setAddress(_MORPHO_VAULT_SLOT, _target);
  }

  function morphoVault() public view returns (address) {
    return getAddress(_MORPHO_VAULT_SLOT);
  }

  function finalizeUpgrade() external virtual onlyGovernance {
    _finalizeUpgrade();
  }

  function _setDistributionTime(address token, uint256 duration) internal {
    require(duration == 0 || duration > 10, "duration > 10 || 0");
    _stream[token].duration = duration;
  }

  function setDistributionTime(address token, uint256 duration) external onlyGovernance {
    _setDistributionTime(token, duration);
  }

  receive() external payable {}
}
