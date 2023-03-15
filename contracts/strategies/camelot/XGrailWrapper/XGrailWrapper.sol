// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "../../../base/interface/IController.sol";
import "../../../base/interface/IRewardForwarder.sol";
import "../../../base/interface/IUpgradeSource.sol";
import "../../../base/inheritance/ControllableInit.sol";
import "../../../base/interface/IPotPool.sol";
import "./XGrailWrapperStorage.sol";
import "../../../base/interface/camelot/IXGrail.sol";
import "../../../base/interface/camelot/IXGrailTokenUsage.sol";
import "../../../base/interface/camelot/IDividendsV2.sol";
import "../../../base/interface/camelot/ICamelotPair.sol";
import "../../../base/interface/camelot/ICamelotRouter.sol";
import "../../../base/interface/camelot/IYieldBooster.sol";

contract XGrailWrapper is ERC20Upgradeable, IUpgradeSource, ControllableInit, XGrailWrapperStorage {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  struct TargetAllocation {
    address allocationAddress; // Address to allocate too
    uint256 weight;            // Weight of allocation (in BPS)
    bytes data;                // Bytes to send in the usageData field
  }

  struct CurrentAllocation {
    address allocationAddress; // Address to allocate too
    uint256 amount;            // Amount of allocation in xGrail
    bytes data;                // Bytes to send in the usageData field
  }

  /**
   * Caller has exchanged assets for shares, and transferred those shares to owner.
   *
   * MUST be emitted when tokens are deposited into the Vault via the mint and deposit methods.
   */
  event Deposit(address indexed sender, address indexed receiver, uint256 assets, uint256 shares);
  event Redeem(address indexed userAddress, uint256 xGrailAmount, uint256 grailAmount, uint256 duration);
  event FinalizeRedeem(address indexed userAddress, uint256 xGrailAmount, uint256 grailAmount);
  event CancelRedeem(address indexed userAddress, uint256 xGrailAmount);
  event ProfitLogInReward(address indexed rewardToken, uint256 profitAmount, uint256 feeAmount, uint256 timestamp);
  event PlatformFeeLogInReward(address indexed treasury, address indexed rewardToken, uint256 profitAmount, uint256 feeAmount, uint256 timestamp);

  CurrentAllocation[] public currentAllocations;
  TargetAllocation[] public allocationTargets;
  mapping(address => uint256[]) public userRedeems;
  address[] internal rewardTokens;
  mapping(address => bool) internal isLp;
  mapping(address => address[]) internal path2Target;

  // Only smart contracts will be affected by this modifier
  modifier defense() {
    require(
      (msg.sender == tx.origin) ||                      // If it is a normal user and not smart contract, then the requirement will pass
      !IController(controller()).greyList(msg.sender),  // If it is a smart contract, then
      "Grey list"        // make sure that it is not on our greyList.
    );
    _;
  }

  /*
   * @dev Check if a redeem entry exists
   */
  modifier validateRedeem(address userAddress, uint256 redeemIndex) {
    require(redeemIndex < userRedeems[userAddress].length, "Redeem does not exist");
    _;
  }

  constructor() public {
  }

  // the function is name differently to not cause inheritance clash in truffle and allows tests
  function initializeVault(address _storage, address _xGrail, address _camelotRouter, address _yieldBooster, address _potPool) public initializer {
    __ERC20_init(
      string(abi.encodePacked("FARM_", ERC20Upgradeable(_xGrail).symbol())),
      string(abi.encodePacked("f", ERC20Upgradeable(_xGrail).symbol()))
    );
    _setupDecimals(ERC20Upgradeable(_xGrail).decimals());

    ControllableInit.initialize(_storage);

    XGrailWrapperStorage.initialize(_xGrail, _camelotRouter, _yieldBooster, _potPool);
  }

  /*///////////////////////////////////////////////////////////////
                  STORAGE SETTER AND GETTER
  //////////////////////////////////////////////////////////////*/

  function xGrail() public view returns(address) {
    return _xGrail();
  }

  function camelotRouter() public view returns(address) {
    return _camelotRouter();
  }

  function setCamelotRouter(address _target) external onlyGovernance {
    _setCamelotRouter(_target);
  }

  function yieldBooster() public view returns(address) {
    return _yieldBooster();
  }

  function setYieldBooster(address _target) external onlyGovernance {
    _setYieldBooster(_target);
  }

  function potPool() public view returns(address) {
    return _potPool();
  }

  function setPotPool(address _target) external onlyGovernance {
    _setPotPool(_target);
  }

  function nextImplementation() public view returns(address) {
    return _nextImplementation();
  }

  function nextImplementationTimestamp() public view returns(uint256) {
    return _nextImplementationTimestamp();
  }

  function nextImplementationDelay() public view returns(uint256) {
    return IController(controller()).nextImplementationDelay();
  }

  function dividendsAddress() public view returns(address) {
    return IXGrail(xGrail()).dividendsAddress();
  }

  function grailToken() public view returns(address) {
    return IXGrail(xGrail()).grailToken();
  }

  /*///////////////////////////////////////////////////////////////
                  INTERNAL HELPER FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function _camelotSwap(address[] memory path, uint256 amountIn, uint256 minAmountOut) internal {
    address _camelotRouter = camelotRouter();
    address sellToken = path[0];
    IERC20Upgradeable(sellToken).safeApprove(_camelotRouter, 0);
    IERC20Upgradeable(sellToken).safeApprove(_camelotRouter, amountIn);
    ICamelotRouter(_camelotRouter).swapExactTokensForTokensSupportingFeeOnTransferTokens(
      amountIn, minAmountOut, path, address(this), governance(), block.timestamp
    );
  }

  function _liquidateRewards() internal {
    for (uint256 i; i < rewardTokens.length; i++) {
      address token = rewardTokens[i];
      uint256 balance = IERC20Upgradeable(token).balanceOf(address(this));
      if (isLp[token]) {
        address token0 = ICamelotPair(token).token0();
        address token1 = ICamelotPair(token).token1();
        ICamelotRouter(camelotRouter()).removeLiquidity(token0, token1, balance, 1, 1, address(this), block.timestamp);
        uint256 balance0 = IERC20Upgradeable(token0).balanceOf(address(this));
        if (path2Target[token0].length > 1) {
          _camelotSwap(path2Target[token0], balance0, 1);
        }
        uint256 balance1 = IERC20Upgradeable(token1).balanceOf(address(this));
        if (path2Target[token1].length > 1) {
          _camelotSwap(path2Target[token1], balance1, 1);
        }
      } else {
        if (path2Target[token].length > 1) {
          _camelotSwap(path2Target[token], balance, 1);
        }
      }
    }

    address _targetToken = IController(controller()).targetToken();
    uint256 targetBalance = IERC20Upgradeable(_targetToken).balanceOf(address(this));
    _notifyProfitInRewardToken(_targetToken, targetBalance);
    uint256 remainingTargetBalance = IERC20Upgradeable(_targetToken).balanceOf(address(this));

    if (remainingTargetBalance == 0) {
      return;
    }

    address _potPool = potPool();
    IERC20Upgradeable(_targetToken).safeTransfer(_potPool, remainingTargetBalance);
    IPotPool(_potPool).notifyTargetRewardAmount(_targetToken, remainingTargetBalance);    
  }

  function _notifyProfitInRewardToken(address _rewardToken, uint256 _rewardBalance ) internal {
    if (_rewardBalance > 0) {
      address _controller = controller();
      uint _feeDenominator = IController(_controller).feeDenominator();
      uint256 platformFee = _rewardBalance.mul(IController(_controller).platformFeeNumerator()).div(_feeDenominator);
      uint256 profitSharingFee = _rewardBalance.mul(IController(_controller).profitSharingNumerator()).div(_feeDenominator);

      address platformFeeRecipient = IController(_controller).governance();

      emit ProfitLogInReward(_rewardToken, _rewardBalance, profitSharingFee, block.timestamp);
      emit PlatformFeeLogInReward(platformFeeRecipient, _rewardToken, _rewardBalance, platformFee, block.timestamp);

      address rewardForwarder = IController(_controller).rewardForwarder();
      IERC20Upgradeable(_rewardToken).safeApprove(rewardForwarder, 0);
      IERC20Upgradeable(_rewardToken).safeApprove(rewardForwarder, _rewardBalance);

      // Distribute/send the fees
      IRewardForwarder(rewardForwarder).notifyFee(_rewardToken, profitSharingFee, 0, platformFee);
    }
  }

  function _handleXGrailRewards() internal {
    uint256 wrapperTotalSupply = totalSupply();
    uint256 totalXGrailBalance = xGrailBalanceTotal();
    if (totalXGrailBalance > wrapperTotalSupply) {
      uint256 availableReward = totalXGrailBalance.sub(wrapperTotalSupply);
      _deposit(availableReward, address(this), address(this));

      _notifyProfitInRewardToken(address(this), availableReward);
      uint256 remainingBalance = balanceOf(address(this));

      address _potPool = potPool();
      IERC20Upgradeable(address(this)).safeTransfer(_potPool, remainingBalance);
      IPotPool(_potPool).notifyTargetRewardAmount(address(this), remainingBalance);    
    }
  }

  function _convertToXGrail(uint256 amount, address sender) internal {
    require(amount > 0, "0-value");
    if (sender != address(this)){
      IERC20Upgradeable(grailToken()).safeTransferFrom(sender, address(this), amount);
    }
    IXGrail(xGrail()).convert(amount);
  }

  function _deposit(uint256 amount, address sender, address beneficiary) internal {
    require(amount > 0, "0-value");
    require(beneficiary != address(0), "0-address");

    _mint(beneficiary, amount);

    if (sender != address(this)){
      IERC20Upgradeable(xGrail()).safeTransferFrom(sender, address(this), amount);
    }

    // update the contribution amount for the beneficiary
    emit Deposit(sender, beneficiary, amount, amount);
  }

  /**
   * @dev Initiates redeem process (xGRAIL to GRAIL)
   *
   */
  function _redeem(uint256 xGrailAmount, uint256 duration, address receiver, address owner) internal {
    require(xGrailAmount > 0, "0-value");
    require(duration >= IXGrail(xGrail()).minRedeemDuration(), "redeem duration");

    address sender = msg.sender;
    if (sender != owner) {
      uint256 currentAllowance = allowance(owner, sender);
      if (currentAllowance != uint(-1)) {
        require(currentAllowance >= xGrailAmount, "ERC20: allowance");
        _approve(owner, sender, currentAllowance - xGrailAmount);
      }
    }

    _burn(owner, xGrailAmount);
    IXGrail(xGrail()).redeem(xGrailAmount, duration);

    uint256 index = IXGrail(xGrail()).getUserRedeemsLength(address(this)).sub(1);  //Get info for the redemption we just added
    IXGrail.RedeemInfo memory info = IXGrail(xGrail()).getUserRedeem(address(this), index);
    emit Redeem(receiver, info.xGrailAmount, info.grailAmount, duration);

    // if redeeming is not immediate, go through vesting process
    if(duration > 0) {
      // add redeeming entry
      userRedeems[receiver].push(index);
    } else {
      // immediately redeem for GRAIL
      _finalizeRedeem(receiver, info.xGrailAmount, info.grailAmount);
    }
  }

  /**
   * @dev Finalizes the redeeming process for "userAddress" by transferring him "grailAmount"
   *
   * Any vesting check should be ran before calling this
   */
  function _finalizeRedeem(address userAddress, uint256 xGrailAmount, uint256 grailAmount) internal {
    // sends due GRAIL tokens
    IERC20Upgradeable(grailToken()).safeTransfer(userAddress, grailAmount);

    emit FinalizeRedeem(userAddress, xGrailAmount, grailAmount);
  }

  function _deleteRedeemEntry(uint256 index) internal {
    userRedeems[msg.sender][index] = userRedeems[msg.sender][userRedeems[msg.sender].length - 1];
    userRedeems[msg.sender].pop();
  }

  /*///////////////////////////////////////////////////////////////
                  VIEW FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function getCurrentAllocation(address allocationAddress, bytes memory data) public view returns(uint256) {
    if (allocationAddress == dividendsAddress()) {
      return IXGrail(xGrail()).getUsageAllocation(address(this), allocationAddress);
    } else if (allocationAddress == yieldBooster()) {
      (address poolAddress, uint256 tokenId) = abi.decode(data, (address, uint256));
      return IYieldBooster(yieldBooster()).getUserPositionAllocation(address(this), poolAddress, tokenId);
    }
  }

  /*
  * Returns the cash balance across all users in this contract.
  */
  function xGrailBalanceInVault() view public returns (uint256) {
    return IERC20Upgradeable(xGrail()).balanceOf(address(this));
  }

  /* Returns the amount of xGrail allocated and being redeemed.
  */
  function xGrailBalanceAllocated() view public returns (IXGrail.XGrailBalance memory) {
    return IXGrail(xGrail()).getXGrailBalance(address(this));
  }

  function pendingDeallocationFee(CurrentAllocation memory allocation) view public returns (uint256) {
    uint256 feeBP = IXGrail(xGrail()).usagesDeallocationFee(allocation.allocationAddress);
    return allocation.amount.mul(feeBP).div(10000);
  }

  function pendingDeallocationFeeTotal() view public returns (uint256) {
    uint256 totalPendingFee = 0;
    for (uint256 i = 0; i < currentAllocations.length; i++){
      totalPendingFee += pendingDeallocationFee(currentAllocations[i]);
    }
    return totalPendingFee;
  }

  function xGrailBalanceTotal() view public returns (uint256) {
    return xGrailBalanceInVault().add(xGrailBalanceAllocated().allocatedAmount).sub(pendingDeallocationFeeTotal());      //We don't count redeeming balance, because those shares have been burnt.
  }

  function getUserRedeemInfo(address user, uint256 index) view public returns (IXGrail.RedeemInfo memory) {
    return IXGrail(xGrail()).getUserRedeem(address(this), userRedeems[user][index]);
  }

  /*///////////////////////////////////////////////////////////////
                  STATE CHANGING FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /**
  * Chooses the best strategy and re-invests. If the strategy did not change, it just calls
  * doHardWork on the current strategy. Call this through controller to claim hard rewards.
  */
  function doHardWork() external onlyControllerOrGovernance {
    // ensure that new funds are invested too
    IDividendsV2(dividendsAddress()).harvestAllDividends();
    _liquidateRewards();
    _handleXGrailRewards();
    rebalanceAllocations();
  }

  function rebalanceAllocations() public onlyControllerOrGovernance {
    uint256 maxLength = currentAllocations.length.add(allocationTargets.length);
    address[] memory increaseAddresses = new address[](maxLength);
    uint256[] memory increaseAmounts = new uint256[](maxLength);
    bytes[] memory increaseDatas = new bytes[](maxLength);
    address[] memory decreaseAddresses = new address[](maxLength);
    uint256[] memory decreaseAmounts = new uint256[](maxLength);
    bytes[] memory decreaseDatas = new bytes[](maxLength);
    uint256 nDecrease = 0;
    uint256 nIncrease = 0;

    for (uint256 i; i < currentAllocations.length; i++) {  //Check if we have current allocations that are not in the targets
      address allocationAddress = currentAllocations[i].allocationAddress;
      bytes memory data = currentAllocations[i].data;
      bool isTarget = false;
      for (uint256 j; j < allocationTargets.length; j++) {
        address targetAddress = allocationTargets[j].allocationAddress;
        bytes memory targetData = allocationTargets[j].data;
        if (targetAddress == allocationAddress && keccak256(targetData) == keccak256(data)) {
          isTarget = true;
          break;
        }
      }
      if (!isTarget) {
        decreaseAddresses[nDecrease] = allocationAddress;
        decreaseAmounts[nDecrease] = currentAllocations[i].amount;
        decreaseDatas[nDecrease] = data;
        nDecrease += 1;
      }
    }

    uint256 nAllocations = 0;
    for (uint256 i; i < allocationTargets.length; i++) {           //Split target allocations into increases and decreases
      address allocationAddress = allocationTargets[i].allocationAddress;
      bytes memory data = allocationTargets[i].data;
      uint256 currentAmount = getCurrentAllocation(allocationAddress, data);
      uint256 targetAmount = xGrailBalanceTotal().mul(allocationTargets[i].weight).div(10000);
      if (currentAmount > targetAmount) {
        decreaseAddresses[nDecrease] = allocationAddress;
        decreaseAmounts[nDecrease] = currentAmount.sub(targetAmount);
        decreaseDatas[nDecrease] = data;
        nDecrease += 1;
      } else if (targetAmount > currentAmount) {
        increaseAddresses[nIncrease] = allocationAddress;
        increaseAmounts[nIncrease] = targetAmount.sub(currentAmount);
        increaseDatas[nIncrease] = data;
        nIncrease += 1;
      } else {    //No change in amount, store to current positions
        CurrentAllocation memory newAllocation;
        newAllocation.allocationAddress = allocationAddress;
        newAllocation.amount = targetAmount;
        newAllocation.data = data;
        if (nAllocations >= currentAllocations.length) {
          currentAllocations.push(newAllocation);
        } else {
          currentAllocations[nAllocations] = newAllocation;
        }
        nAllocations += 1;
      }
    }

    for (uint256 i; i < nDecrease; i++) {        //First handle decreases to free up xGrail for increases
      IXGrail(xGrail()).deallocate(decreaseAddresses[i], decreaseAmounts[i], decreaseDatas[i]);
      if (getCurrentAllocation(decreaseAddresses[i], decreaseDatas[i]) > 0){
        CurrentAllocation memory newAllocation;
        newAllocation.allocationAddress = decreaseAddresses[i];
        newAllocation.amount = decreaseAmounts[i];
        newAllocation.data = decreaseDatas[i];
        if (nAllocations >= currentAllocations.length) {
          currentAllocations.push(newAllocation);
        } else {
          currentAllocations[nAllocations] = newAllocation;
        }
        nAllocations += 1;
      }
    }

    for (uint256 i; i < nIncrease; i++) {        //Now handle increases
      address _xGrail = xGrail();
      IXGrail(_xGrail).approveUsage(increaseAddresses[i], increaseAmounts[i]);
      IXGrail(_xGrail).allocate(increaseAddresses[i], increaseAmounts[i], increaseDatas[i]);
      CurrentAllocation memory newAllocation;
      newAllocation.allocationAddress = increaseAddresses[i];
      newAllocation.amount = increaseAmounts[i];
      newAllocation.data = increaseDatas[i];
      currentAllocations.push(newAllocation);
      if (nAllocations >= currentAllocations.length) {
        currentAllocations.push(newAllocation);
      } else {
        currentAllocations[nAllocations] = newAllocation;
      }
      nAllocations += 1;
    }

    if (currentAllocations.length > nAllocations) {
      for (uint256 i; i < currentAllocations.length.sub(nAllocations); i++) {
        currentAllocations.pop();
      }
    }
  }

  function setAllocationTargets(address[] memory addresses, uint256[] memory weights, bytes[] memory datas) external onlyGovernance {
    require(addresses.length == weights.length, "Array mismatch");
    require(addresses.length == datas.length, "Array mismatch");
    uint256 totalWeight = 0;
    uint256 nAllocations = 0;
    for (uint256 i; i < addresses.length; i++) {
      if (addresses[i] == dividendsAddress()) {
        require(weights[i] >= 5000, "Dividend weight");
      }
      TargetAllocation memory newAllocation;
      newAllocation.allocationAddress = addresses[i];
      newAllocation.weight = weights[i];
      newAllocation.data = datas[i];
      if (nAllocations >= allocationTargets.length) {
        allocationTargets.push(newAllocation);
      } else {
        allocationTargets[nAllocations] = newAllocation;
      }
      nAllocations += 1;
      totalWeight = totalWeight.add(weights[i]);
    }

    require(totalWeight == 10000, "Total weight");

    if (allocationTargets.length > nAllocations) {
      for (uint256 i; i < allocationTargets.length.sub(nAllocations); i++) {
        allocationTargets.pop();
      }
    }
  }

  /*///////////////////////////////////////////////////////////////
                  DEPOSIT FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  /*
  * Allows for depositing the underlying asset in exchange for shares.
  * Approval is assumed.
  */
  function depositGrail(uint256 amount) external nonReentrant defense {
    _convertToXGrail(amount, msg.sender);
    _deposit(amount, address(this), msg.sender);
  }

  function depositXGrail(uint256 amount) external nonReentrant defense {
    _deposit(amount, msg.sender, msg.sender);
  }

  /*
  * Allows for depositing the underlying asset in exchange for shares
  * assigned to the holder.
  * This facilitates depositing for someone else (using DepositHelper)
  */
  function depositGrailFor(uint256 amount, address holder) public nonReentrant defense {
    _convertToXGrail(amount, msg.sender);
    _deposit(amount, msg.sender, holder);
  }

  function depositXGrailFor(uint256 amount, address holder) public nonReentrant defense {
    _deposit(amount, msg.sender, holder);
  }

  /*///////////////////////////////////////////////////////////////
                  REDEEM FUNCTIONS
  //////////////////////////////////////////////////////////////*/

  function redeem(uint256 xGrailAmount, uint256 duration) external nonReentrant defense {
    _redeem(xGrailAmount, duration, msg.sender, msg.sender); 
  }

  function redeemTo(uint256 xGrailAmount, uint256 duration, address to) external nonReentrant defense {
    _redeem(xGrailAmount, duration, to, msg.sender);
  }

  function redeemFromTo(uint xGrailAmount, uint256 duration, address to, address from) external nonReentrant defense {
    _redeem(xGrailAmount, duration, to, from);
  }

  /**
   * @dev Cancels an ongoing redeem entry
   *
   * Can only be called by its owner
   */
  function cancelRedeem(uint256 redeemIndex) external nonReentrant defense validateRedeem(msg.sender, redeemIndex) {
    uint256 index = userRedeems[msg.sender][redeemIndex];
    IXGrail.RedeemInfo memory info = getUserRedeemInfo(msg.sender, redeemIndex);

    _mint(msg.sender, info.xGrailAmount);
    IXGrail(xGrail()).cancelRedeem(index);

    emit CancelRedeem(msg.sender, info.xGrailAmount);

    // remove redeem entry
    _deleteRedeemEntry(redeemIndex);
  }

  /**
   * @dev Finalizes redeem process when vesting duration has been reached
   *
   * Can only be called by the redeem entry owner
   */
  function finalizeRedeem(uint256 redeemIndex) external nonReentrant defense validateRedeem(msg.sender, redeemIndex) {
    uint256 index = userRedeems[msg.sender][redeemIndex];
    IXGrail.RedeemInfo memory info = getUserRedeemInfo(msg.sender, redeemIndex);
    require(block.timestamp >= info.endTime, "redeem not yet");

    IXGrail(xGrail()).finalizeRedeem(index);
    _finalizeRedeem(msg.sender, info.xGrailAmount, info.grailAmount);

    // remove redeem entry
    _deleteRedeemEntry(redeemIndex);
  }

  /*///////////////////////////////////////////////////////////////
                  PROXY - UPGRADES
  //////////////////////////////////////////////////////////////*/

  /**
  * Schedules an upgrade for this vault's proxy.
  */
  function scheduleUpgrade(address impl) public onlyGovernance {
    _setNextImplementation(impl);
    _setNextImplementationTimestamp(block.timestamp.add(nextImplementationDelay()));
  }

  function shouldUpgrade() external view override returns (bool, address) {
    return (
      nextImplementationTimestamp() != 0
        && block.timestamp > nextImplementationTimestamp()
        && nextImplementation() != address(0),
      nextImplementation()
    );
  }

  function finalizeUpgrade() external override onlyGovernance {
    _setNextImplementation(address(0));
    _setNextImplementationTimestamp(0);
  }
}