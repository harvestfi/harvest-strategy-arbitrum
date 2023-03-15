//SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../base/upgradability/BaseUpgradeableStrategy.sol";
import "../../base/interface/camelot/ICamelotRouter.sol";
import "../../base/interface/camelot/ICamelotPair.sol";
import "../../base/interface/camelot/INFTPool.sol";
import "../../base/interface/camelot/INitroPool.sol";

contract CamelotStrategy is BaseUpgradeableStrategy {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public constant camelotRouter = address(0xc873fEcbd354f5A56E00E710B90EF4201db2448d);
  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  address public constant xGrail = address(0x3CAaE25Ee616f2C8E13C74dA0813402eae3F496b);
  address public constant harvestMSIG = address(0xf3D1A027E858976634F81B7c41B09A05A46EdA21);
  address public constant uniV3Router = address(0xE592427A0AEce92De3Edee1F18E0157C05861564);

  // additional storage slots (on top of BaseUpgradeableStrategy ones) are defined here
  bytes32 internal constant _POS_ID_SLOT = 0x025da88341279feed86c02593d3d75bb35ff95cb72e32ffd093929b008413de5;
  bytes32 internal constant _NFT_POOL_SLOT = 0x828d9a241b00468f203e6001f37c2f3f9b054802b5bfa652f8dee2a0f2d586d9;
  bytes32 internal constant _NITRO_POOL_SLOT = 0x1ee567d62ee6cf3d5c44deeb8b6f34774a4a2d99f55ae3d5f1ca16bee430b005;

  // this would be reset on each upgrade
  mapping(address => address[]) public WETH2deposit;
  mapping(address => address[]) public reward2WETH;
  address[] public rewardTokens;
  mapping (address => mapping(address => uint24)) public storedPairFee;

  constructor() public BaseUpgradeableStrategy() {
    assert(_POS_ID_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.posId")) - 1));
    assert(_NFT_POOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.nftPool")) - 1));
    assert(_NITRO_POOL_SLOT == bytes32(uint256(keccak256("eip1967.strategyStorage.nitroPool")) - 1));
  }

  function initializeBaseStrategy(
    address _storage,
    address _underlying,
    address _vault,
    address _nftPool,
    address _nitroPool
  ) public initializer {

    BaseUpgradeableStrategy.initialize(
      _storage,
      _underlying,
      _vault,
      _nitroPool,
      weth,
      harvestMSIG
    );

    address _lpt;
    (_lpt,,,,,,,) = INFTPool(_nftPool).getPoolInfo();
    require(_lpt == underlying(), "NFTPool Info does not match underlying");
    address checkNftPool = INitroPool(_nitroPool).nftPool();
    require(checkNftPool == _nftPool, "NitroPool does not match NFTPool");
    _setNFTPool(_nftPool);
    _setNitroPool(_nitroPool);
  }

  function depositArbCheck() public pure returns(bool) {
    return true;
  }

  function rewardPoolBalance() internal view returns (uint256 bal) {
    (bal,,,,) = INitroPool(nitroPool()).userInfo(address(this));
  }

  function exitRewardPool() internal {
    uint256 stakedBalance = rewardPoolBalance();
    if (stakedBalance != 0) {
      uint256 _posId = posId();
      INitroPool(nitroPool()).withdraw(_posId);
      INFTPool(nftPool()).withdrawFromPosition(_posId, stakedBalance);
    }
  }

  function partialWithdrawalRewardPool(uint256 amount) internal {
      uint256 _posId = posId();
      address _nitroPool = nitroPool();
      address _nftPool = nftPool();
      INitroPool(_nitroPool).withdraw(_posId);
      INFTPool(_nftPool).withdrawFromPosition(_posId, amount);
      INFTPool(_nftPool).safeTransferFrom(address(this), _nitroPool, _posId);
  }

  function emergencyExitRewardPool() internal {
    uint256 stakedBalance = rewardPoolBalance();
    if (stakedBalance != 0) {
      uint256 _posId = posId();
      INitroPool(nitroPool()).emergencyWithdraw(_posId);
      INFTPool(nftPool()).emergencyWithdraw(_posId);
    }
  }

  function unsalvagableTokens(address token) public view returns (bool) {
    return (token == rewardToken() || token == underlying());
  }

  function enterRewardPool() internal {
    address _underlying = underlying();
    address _nftPool = nftPool();
    address _nitroPool = nitroPool();
    uint256 entireBalance = IERC20(_underlying).balanceOf(address(this));
    IERC20(_underlying).safeApprove(_nftPool, 0);
    IERC20(_underlying).safeApprove(_nftPool, entireBalance);
    if (rewardPoolBalance() > 0) {  //We already have a position. Withdraw from staking, add to position, stake again.
      uint256 _posId = posId();
      INitroPool(_nitroPool).withdraw(_posId);
      INFTPool(_nftPool).addToPosition(_posId, entireBalance);
      INFTPool(_nftPool).safeTransferFrom(address(this), _nitroPool, _posId);
    } else {                        //We do not yet have a position. Create a position and store the position ID. Then stake.
      INFTPool(_nftPool).createPosition(entireBalance, 0);
      uint256 newPosId = INFTPool(_nftPool).tokenOfOwnerByIndex(address(this), 0);
      _setPosId(newPosId);
      INFTPool(_nftPool).safeTransferFrom(address(this), _nitroPool, posId());
    }
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

  function setDepositLiquidationPath(address [] memory _route) public onlyGovernance {
    address _underlying = underlying();
    address token0 = ICamelotPair(_underlying).token0();
    address token1 = ICamelotPair(_underlying).token1();
    require(_route[0] == weth, "Path should start with WETH");
    require(_route[_route.length-1] == token0 || _route[_route.length-1] == token1, "Path should end with a token in the LP");
    WETH2deposit[_route[_route.length-1]] = _route;
  }

  function setRewardLiquidationPath(address [] memory _route) public onlyGovernance {
    require(_route[_route.length-1] == weth, "Path should end with WETH");
    bool isReward = false;
    for(uint256 i = 0; i < rewardTokens.length; i++){
      if (_route[0] == rewardTokens[i]) {
        isReward = true;
      }
    }
    require(isReward, "Path should start with a rewardToken");
    reward2WETH[_route[0]] = _route;
  }

  function addRewardToken(address _token, address[] memory _path2WETH) public onlyGovernance {
    rewardTokens.push(_token);
    setRewardLiquidationPath(_path2WETH);
  }

  // We assume that all the tradings can be done on Sushiswap
  function _liquidateReward() internal {
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

  /**
  * Sets the minimum amount of CRV needed to trigger a sale.
  */
  function setSellFloor(uint256 floor) public onlyGovernance {
    _setSellFloor(floor);
  }

  // masterchef rewards pool ID
  function _setPosId(uint256 _value) internal {
    setUint256(_POS_ID_SLOT, _value);
  }

  function posId() public view returns (uint256) {
    return getUint256(_POS_ID_SLOT);
  }

  function _setNFTPool(address _address) internal {
    setAddress(_NFT_POOL_SLOT, _address);
  }

  function nftPool() public view returns (address) {
    return getAddress(_NFT_POOL_SLOT);
  }

  function _setNitroPool(address _address) internal {
    setAddress(_NITRO_POOL_SLOT, _address);
  }

  function nitroPool() public view returns (address) {
    return getAddress(_NITRO_POOL_SLOT);
  }

  function finalizeUpgrade() external onlyGovernance {
    _finalizeUpgrade();
  }

  receive() external payable {} // this is needed for the WETH unwrapping
}