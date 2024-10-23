// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.26;

import "@openzeppelin/contracts-upgradeable/utils/math/MathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "./interface/IGMXStrategy.sol";
import "./interface/IVault.sol";
import "./interface/IController.sol";
import "./interface/IUpgradeSource.sol";
import "./inheritance/ControllableInit.sol";
import "./VaultStorage.sol";
import "./interface/IERC4626.sol";

contract VaultV1GMX is ERC20Upgradeable, IUpgradeSource, ControllableInit, VaultStorage {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using AddressUpgradeable for address;
  using SafeMathUpgradeable for uint256;

  event Invest(uint256 amount);
  event StrategyAnnounced(address newStrategy, uint256 time);
  event StrategyChanged(address newStrategy, address oldStrategy);

  event DepositStarted(address sender, address receiver, uint256 amountIn);
  event WithdrawalStarted(address sender, address receiver, uint256 amountIn);

  event DepositFailed(address sender, address receiver, uint256 amountIn);
  event WithdrawalFailed(address sender, address receiver, uint256 amountIn);

  struct PendingAction {
    bool pending;
    address sender;
    address receiver;
    uint256 amountIn;
  }

  mapping (bytes32 => PendingAction) public pendingDeposits;
  mapping (bytes32 => PendingAction) public pendingWithdrawals;

  uint256 internal pendingDepositAmount;
  uint256 internal pendingWithdrawalAmount;

  constructor() {
  }

  modifier onlyStrategy() {
    require(msg.sender == strategy(), "Not strategy");
    _;
  }

  // the function is name differently to not cause inheritance clash in truffle and allows tests
  function initializeVault(
    address _storage,
    address _underlying,
    uint256 _toInvestNumerator,
    uint256 _toInvestDenominator
  ) public initializer {
    require(_toInvestNumerator <= _toInvestDenominator, "cannot invest more than 100%");
    require(_toInvestDenominator != 0, "cannot divide by 0");

    __ERC20_init(
      string(abi.encodePacked("FARM_", ERC20Upgradeable(_underlying).symbol())),
      string(abi.encodePacked("f", ERC20Upgradeable(_underlying).symbol()))
    );
    _setDecimals(ERC20Upgradeable(_underlying).decimals());

    ControllableInit.initialize(
      _storage
    );

    uint256 underlyingUnit = 10 ** uint256(ERC20Upgradeable(address(_underlying)).decimals());
    VaultStorage.initialize(
      _underlying,
      _toInvestNumerator,
      _toInvestDenominator,
      underlyingUnit
    );
  }

  function strategy() public view returns(address) {
    return _strategy();
  }

  function underlying() public view returns(address) {
    return _underlying();
  }

  function underlyingUnit() public view returns(uint256) {
    return _underlyingUnit();
  }

  function vaultFractionToInvestNumerator() public view returns(uint256) {
    return _vaultFractionToInvestNumerator();
  }

  function vaultFractionToInvestDenominator() public view returns(uint256) {
    return _vaultFractionToInvestDenominator();
  }

  function nextImplementation() public view returns(address) {
    return _nextImplementation();
  }

  function nextImplementationTimestamp() public view returns(uint256) {
    return _nextImplementationTimestamp();
  }

  function nextImplementationDelay() public view returns (uint256) {
    return IController(controller()).nextImplementationDelay();
  }

  modifier whenStrategyDefined() {
    require(address(strategy()) != address(0), "Strategy must be defined");
    _;
  }

  // Only smart contracts will be affected by this modifier
  modifier defense() {
    require(
      (msg.sender == tx.origin) ||                // If it is a normal user and not smart contract,
                                                  // then the requirement will pass
      !IController(controller()).greyList(msg.sender), // If it is a smart contract, then
      "This smart contract has been grey listed"  // make sure that it is not on our greyList.
    );
    _;
  }

  /**
  * Chooses the best strategy and re-invests. If the strategy did not change, it just calls
  * doHardWork on the current strategy. Call this through controller to claim hard rewards.
  */
  function doHardWork() whenStrategyDefined onlyControllerOrGovernance external {
    // ensure that new funds are invested too
    invest();
    IGMXStrategy(strategy()).doHardWork();
  }

  /*
  * Returns the cash balance across all users in this contract.
  */
  function underlyingBalanceInVault() view public returns (uint256) {
    return IERC20Upgradeable(underlying()).balanceOf(address(this));
  }

  /* Returns the current underlying (e.g., DAI's) balance together with
   * the invested amount (if DAI is invested elsewhere by the strategy).
  */
  function underlyingBalanceWithInvestment() view public returns (uint256) {
    if (address(strategy()) == address(0)) {
      // initial state, when not set
      return underlyingBalanceInVault();
    }
    return underlyingBalanceInVault().add(IGMXStrategy(strategy()).investedUnderlyingBalance()).sub(pendingDepositAmount);
  }

  function getPricePerFullShare() public view returns (uint256) {
    return totalSupply() == 0
        ? underlyingUnit()
        : underlyingUnit().mul(underlyingBalanceWithInvestment()).div(totalSupply().add(pendingWithdrawalAmount));
  }

  /* get the user's share (in underlying)
  */
  function underlyingBalanceWithInvestmentForHolder(address holder) view external returns (uint256) {
    if (totalSupply() == 0) {
      return 0;
    }
    return underlyingBalanceWithInvestment()
        .mul(balanceOf(holder))
        .div(totalSupply().add(pendingWithdrawalAmount));
  }

  function nextStrategy() public view returns (address) {
    return _nextStrategy();
  }

  function nextStrategyTimestamp() public view returns (uint256) {
    return _nextStrategyTimestamp();
  }

  function canUpdateStrategy(address _strategy) public view returns (bool) {
    bool isStrategyNotSetYet = strategy() == address(0);
    bool hasTimelockPassed = block.timestamp > nextStrategyTimestamp() && nextStrategyTimestamp() != 0;
    return isStrategyNotSetYet || (_strategy == nextStrategy() && hasTimelockPassed);
  }

  /**
  * Indicates that the strategy update will happen in the future
  */
  function announceStrategyUpdate(address _strategy) public onlyControllerOrGovernance {
    // records a new timestamp
    uint256 when = block.timestamp.add(nextImplementationDelay());
    _setNextStrategyTimestamp(when);
    _setNextStrategy(_strategy);
    emit StrategyAnnounced(_strategy, when);
  }

  /**
  * Finalizes (or cancels) the strategy update by resetting the data
  */
  function finalizeStrategyUpdate() public onlyControllerOrGovernance {
    _setNextStrategyTimestamp(0);
    _setNextStrategy(address(0));
  }

  function setStrategy(address _strategy) public onlyControllerOrGovernance {
    require(canUpdateStrategy(_strategy),
      "The strategy exists and switch timelock did not elapse yet");
    require(_strategy != address(0), "new _strategy cannot be empty");
    require(IGMXStrategy(_strategy).underlying() == address(underlying()), "Vault underlying must match Strategy underlying");
    require(IGMXStrategy(_strategy).vault() == address(this), "the strategy does not belong to this vault");

    emit StrategyChanged(_strategy, strategy());
    if (address(_strategy) != address(strategy())) {
      if (address(strategy()) != address(0)) { // if the original strategy (no underscore) is defined
        require(underlyingBalanceWithInvestment() == underlyingBalanceInVault(), "Withdraw to vault first");
        IERC20Upgradeable(underlying()).safeApprove(address(strategy()), 0);
      }
      _setStrategy(_strategy);
      IERC20Upgradeable(underlying()).safeApprove(address(strategy()), 0);
      IERC20Upgradeable(underlying()).safeApprove(address(strategy()), type(uint256).max);
    }
    finalizeStrategyUpdate();
  }

  function setVaultFractionToInvest(uint256 numerator, uint256 denominator) external onlyGovernance {
    require(denominator > 0, "denominator must be greater than 0");
    require(numerator <= denominator, "denominator must be greater than or equal to the numerator");
    _setVaultFractionToInvestNumerator(numerator);
    _setVaultFractionToInvestDenominator(denominator);
  }

  function availableToInvestOut() public view returns (uint256) {
    uint256 wantInvestInTotal = underlyingBalanceWithInvestment()
        .mul(vaultFractionToInvestNumerator())
        .div(vaultFractionToInvestDenominator());
    uint256 alreadyInvested = IGMXStrategy(strategy()).investedUnderlyingBalance();
    if (alreadyInvested >= wantInvestInTotal) {
      return 0;
    } else {
      uint256 remainingToInvest = wantInvestInTotal.sub(alreadyInvested);
      return remainingToInvest <= underlyingBalanceInVault()
        // TODO: we think that the "else" branch of the ternary operation is not
        // going to get hit
        ? remainingToInvest : underlyingBalanceInVault();
    }
  }

  function invest() internal whenStrategyDefined {
    uint256 availableAmount = availableToInvestOut();
    if (availableAmount > 0) {
      IERC20Upgradeable(underlying()).safeTransfer(address(strategy()), availableAmount);
      emit Invest(availableAmount);
    }
  }

  /*
  * Allows for depositing the underlying asset in exchange for shares.
  * Approval is assumed.
  */
  function deposit(uint256 amount) external nonReentrant defense returns (uint256 minted) {
    minted = _deposit(amount, msg.sender, msg.sender);
  }

  /*
  * Allows for depositing the underlying asset in exchange for shares
  * assigned to the holder.
  * This facilitates depositing for someone else (using DepositHelper)
  */
  function depositFor(uint256 amount, address holder) public nonReentrant defense returns (uint256 minted) {
    minted = _deposit(amount, msg.sender, holder);
  }

  function withdraw(uint256 shares) external nonReentrant defense returns (uint256 amtUnderlying) {
    amtUnderlying = _withdraw(shares, msg.sender, msg.sender);
  }

  function withdrawAll() public onlyControllerOrGovernance whenStrategyDefined {
    bytes32 withdrawalHash = IGMXStrategy(strategy()).withdrawAllToVault();
    
    pendingWithdrawals[withdrawalHash] = PendingAction(
      true,
      address(this),
      address(this),
      0
    );
  }

  function _deposit(uint256 amount, address sender, address beneficiary) internal returns (uint256) {
    require(amount > 0, "Cannot deposit 0");
    require(beneficiary != address(0), "holder must be defined");

    if (address(strategy()) != address(0)) {
      require(IGMXStrategy(strategy()).depositArbCheck(), "Too much arb");
    }

    IERC20Upgradeable(underlying()).safeTransferFrom(sender, address(this), amount);

    invest();
    bytes32 depositHash = IGMXStrategy(strategy()).doHardWork();

    require(!pendingDeposits[depositHash].pending, "Deposit pending");

    pendingDeposits[depositHash] = PendingAction(
      true,
      sender,
      beneficiary,
      amount
    );
    pendingDepositAmount += amount;

    emit DepositStarted(sender, beneficiary, amount);

    return 0;
  }

  function _finalizeDeposit(bool success, bytes32 depositHash, uint256 correctedAmount) internal {
    PendingAction memory pendingDeposit = pendingDeposits[depositHash];
    require(pendingDeposit.pending, "No pending deposit");

    if (success) {
      uint256 toMint = totalSupply() == 0
          ? correctedAmount
          : correctedAmount.mul(totalSupply().add(pendingWithdrawalAmount)).div(underlyingBalanceWithInvestment());
      _mint(pendingDeposit.receiver, toMint);

      // update the contribution amount for the beneficiary
      emit IERC4626.Deposit(pendingDeposit.sender, pendingDeposit.receiver, pendingDeposit.amountIn, toMint);
    } else {
      IERC20Upgradeable(underlying()).safeTransfer(pendingDeposit.sender, pendingDeposit.amountIn);
      emit DepositFailed(pendingDeposit.sender, pendingDeposit.receiver, pendingDeposit.amountIn);
    }

    pendingDepositAmount -= pendingDeposit.amountIn;
    pendingDeposits[depositHash] = PendingAction(
      false,
      address(0),
      address(0),
      0
    );
  }

  function finalizeDeposit(bool success, bytes32 depositHash, uint256 correctedAmount) external onlyStrategy nonReentrant {
    _finalizeDeposit(success, depositHash, correctedAmount);
  } 

  function _withdraw(uint256 numberOfShares, address receiver, address owner) internal returns (uint256) {
    require(totalSupply() > 0, "Vault has no shares");
    require(numberOfShares > 0, "numberOfShares must be greater than 0");
    uint256 totalSupply = totalSupply();

    address sender = msg.sender;
      if (sender != owner) {
        uint256 currentAllowance = allowance(owner, sender);
        if (currentAllowance != type(uint256).max) {
          require(currentAllowance >= numberOfShares, "ERC20: transfer amount exceeds allowance");
          _approve(owner, sender, currentAllowance - numberOfShares);
        }
      }
    _burn(owner, numberOfShares);

    uint256 underlyingAmountToWithdraw = underlyingBalanceWithInvestment()
        .mul(numberOfShares)
        .div(totalSupply);

    if (underlyingAmountToWithdraw <= underlyingBalanceInVault()) {
      IERC20Upgradeable(underlying()).safeTransfer(receiver, underlyingAmountToWithdraw);

      emit IERC4626.Withdraw(sender, receiver, owner, underlyingAmountToWithdraw, numberOfShares);
      return underlyingAmountToWithdraw;
    }

    bytes32 withdrawalHash;
    if (numberOfShares == totalSupply) {
      withdrawalHash = IGMXStrategy(strategy()).withdrawAllToVault();
    } else {
      withdrawalHash = IGMXStrategy(strategy()).withdrawToVault(underlyingAmountToWithdraw);
    }

    require(!pendingWithdrawals[withdrawalHash].pending, "Withdrawal pending");

    if (withdrawalHash == bytes32(0)) {
      pendingWithdrawals[withdrawalHash] = PendingAction(
        true,
        owner,
        receiver,
        numberOfShares
      );
      pendingWithdrawalAmount += numberOfShares;
      _finalizeWithdrawal(true, withdrawalHash, underlyingAmountToWithdraw);
      emit IERC4626.Withdraw(sender, receiver, owner, underlyingAmountToWithdraw, numberOfShares);
      return underlyingAmountToWithdraw;
    }

    pendingWithdrawals[withdrawalHash] = PendingAction(
      true,
      owner,
      receiver,
      numberOfShares
    );
    pendingWithdrawalAmount += numberOfShares;

    emit WithdrawalStarted(owner, receiver, numberOfShares);

    return 0;
  }

  function _finalizeWithdrawal(bool success, bytes32 withdrawalHash, uint256 amountReceived) internal {
    PendingAction memory pendingWithdrawal = pendingWithdrawals[withdrawalHash];
    require(pendingWithdrawal.pending, "No pending withdrawal");
    
    if (pendingWithdrawal.amountIn > 0) {
      if (success) {
        IERC20Upgradeable(underlying()).safeTransfer(pendingWithdrawal.receiver, amountReceived);
        
        // update the withdrawal amount for the holder
        emit IERC4626.Withdraw(pendingWithdrawal.sender, pendingWithdrawal.receiver, pendingWithdrawal.sender, amountReceived, pendingWithdrawal.amountIn);
      } else {
        _mint(pendingWithdrawal.sender, pendingWithdrawal.amountIn);
        emit WithdrawalFailed(pendingWithdrawal.sender, pendingWithdrawal.receiver, pendingWithdrawal.amountIn);
      }
    }

    pendingWithdrawalAmount -= pendingWithdrawal.amountIn;
    pendingWithdrawals[withdrawalHash] = PendingAction(
      false,
      address(0),
      address(0),
      0
    );
  }

  function finalizeWithdrawal(bool success, bytes32 withdrawalHash, uint256 amountReceived) external onlyStrategy nonReentrant {
    _finalizeWithdrawal(success, withdrawalHash, amountReceived);
  }

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