// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IIDRC} from "./interfaces/IIDRC.sol";
import {IHub} from "./interfaces/IHub.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

contract Reward is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_MANAGER_ROLE = keccak256("ADMIN_MANAGER_ROLE");

    address public hub;
    address public idrc;

    uint256 public lastDistribution;
    uint256 public rewardPerTokenStored;
    uint256 public totalRewardsDistributed;
    uint256 public totalRewardsClaimed;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event RewardInjected(uint256 amount, uint256 timestamp);
    event RewardDistributed(uint256 amount, uint256 newRewardPerToken);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardUpdated(address indexed user, uint256 earned);

    error ZeroAmount();
    error ZeroAddress();
    error NoTokensMinted();
    error NoRewardToClaim();
    error NotHubCaller();
    error TransferFailed();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _hubAddress, address _idrc, address _adminManager) external initializer {
        if (_hubAddress == address(0) || _idrc == address(0) || _adminManager == address(0)) {
            revert ZeroAddress();
        }

        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_MANAGER_ROLE, _adminManager);

        hub = _hubAddress;
        idrc = _idrc;
    }

    /**
     * @notice Admin deposits yield from bond coupon/maturity
     * @param amount Amount of reward tokens to distribute
     */
    function injectReward(uint256 amount) external onlyRole(ADMIN_MANAGER_ROLE) nonReentrant {
        if (amount == 0) revert ZeroAmount();

        uint256 supply = IIDRC(idrc).tvl();
        if (supply == 0) revert NoTokensMinted();

        // Transfer reward tokens from admin
        IERC20(IHub(hub).tokenAccepted()).safeTransferFrom(msg.sender, address(this), amount);

        // Distribute to all holders proportionally
        _distribute(amount, supply);

        emit RewardInjected(amount, block.timestamp);
    }

    /**
     * @dev Internal distribution logic
     * Updates the global reward rate that all users accrue from
     */
    function _distribute(uint256 amount, uint256 supply) internal {
        // Calculate new reward per token (scaled by 1e6 for precision)
        uint256 rewardPerToken = (amount * 1e6) / supply;
        rewardPerTokenStored += rewardPerToken;
        lastDistribution = block.timestamp;
        totalRewardsDistributed += amount;

        emit RewardDistributed(amount, rewardPerTokenStored);
    }

    /**
     * @notice Calculate earned rewards for an account
     * @param account User address
     * @return Total earned rewards (claimed + unclaimed)
     */
    function earned(address account) public view returns (uint256) {
        uint256 balance = IIDRC(idrc).balanceOf(account);
        uint256 rewardDelta = rewardPerTokenStored - userRewardPerTokenPaid[account];
        uint256 pending = (balance * rewardDelta) / 1e6;

        return rewards[account] + pending;
    }

    /**
     * @notice Called by IDRC when token balance changes
     * @dev MUST be called before mint/burn/transfer in IDRC token
     * @param account User whose rewards need updating
     */
    function updateReward(address account) external onlyIDRC {
        _updateReward(account);
    }

    /**
     * @dev Update user's reward checkpoint
     */
    function _updateReward(address account) internal {
        uint256 earnedAmount = earned(account);
        rewards[account] = earnedAmount;
        userRewardPerTokenPaid[account] = rewardPerTokenStored;

        emit RewardUpdated(account, earnedAmount);
    }

    /**
     * @notice Claim all pending rewards
     */
    function claimReward() external nonReentrant {
        _claimReward(msg.sender);
    }

    /**
     * @notice Claim rewards for specific account (called by Hub)
     */
    function claimReward(address account) external onlyHub nonReentrant {
        _claimReward(account);
    }

    /**
     * @dev Internal claim logic
     */
    function _claimReward(address account) internal {
        _updateReward(account);

        uint256 reward = rewards[account];
        if (reward == 0) revert NoRewardToClaim();

        rewards[account] = 0;
        totalRewardsClaimed += reward;

        IERC20(IHub(hub).tokenAccepted()).safeTransfer(account, reward);

        emit RewardClaimed(account, reward);
    }

    /**
     * @notice View total unclaimed rewards in contract
     */
    function totalUnclaimedRewards() external view returns (uint256) {
        return totalRewardsDistributed - totalRewardsClaimed;
    }

    /**
     * @notice View reward token balance
     */
    function rewardBalance() external view returns (uint256) {
        return IERC20(IHub(hub).tokenAccepted()).balanceOf(address(this));
    }

    /**
     * @dev Authorize upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Only Hub can call certain functions
     */
    modifier onlyHub() {
        if (msg.sender != hub) revert NotHubCaller();
        _;
    }

    /**
     * @dev Only IDRC can call certain functions
     */
    modifier onlyIDRC() {
        if (msg.sender != idrc) revert NotHubCaller();
        _;
    }
}
