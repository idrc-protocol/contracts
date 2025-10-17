// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IRewardDistributor {
    // State variables
    function hub() external view returns (address);
    function idrc() external view returns (address);
    function lastDistribution() external view returns (uint256);
    function rewardPerTokenStored() external view returns (uint256);
    function totalRewardsDistributed() external view returns (uint256);
    function totalRewardsClaimed() external view returns (uint256);
    function userRewardPerTokenPaid(address account) external view returns (uint256);
    function rewards(address account) external view returns (uint256);

    // Events
    event RewardInjected(uint256 amount, uint256 timestamp);
    event RewardDistributed(uint256 amount, uint256 newRewardPerToken);
    event RewardClaimed(address indexed user, uint256 amount);
    event RewardUpdated(address indexed user, uint256 earned);

    // Errors
    error ZeroAmount();
    error ZeroAddress();
    error NoTokensMinted();
    error NoRewardToClaim();
    error NotHubCaller();
    error TransferFailed();

    // Functions
    function initialize(address _hubAddress, address _idrc, address _adminManager) external;

    function injectReward(uint256 amount) external;

    function earned(address account) external view returns (uint256);

    function updateReward(address account) external;

    function claimReward() external;

    function claimReward(address account) external;

    function totalUnclaimedRewards() external view returns (uint256);

    function rewardBalance() external view returns (uint256);
}
