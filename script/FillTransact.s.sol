// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Hub} from "../src/Hub.sol";
import {Reward} from "../src/RewardDistributor.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRX} from "../src/IDRX.sol";

contract FillTransact is Script {
    // Contract addresses - update these with your deployed addresses
    address public hubProxy;
    address public idrcProxy;
    address public rewardProxy;
    address public idrxToken;

    // Test users
    address public user;
    address public admin;
    uint256 public userPrivateKey;
    uint256 public adminPrivateKey;

    function setUp() public {
        // Get contract addresses from environment or use default values
        hubProxy = vm.envOr("HUB_PROXY", address(0xf2CCA756D7dE98d54ed00697EA8Cf50D71ea0Dd1));
        idrcProxy = vm.envOr("IDRC_PROXY", address(0xD3723bD07766d4993FBc936bEA1895227B556ea3));
        rewardProxy = vm.envOr("REWARD_PROXY", address(0xA77C8059B011Ad0DB426623d1c1B985E53fdb7db));
        idrxToken = vm.envOr("IDRX_TOKEN", address(0x3E4c9e0a4F7F735401971dace92d18418da9c937));

        // Create test users
        userPrivateKey = vm.envUint("USER_PRIVATE_KEY");
        user = vm.addr(userPrivateKey);
        adminPrivateKey = vm.envUint("PRIVATE_KEY");
        admin = vm.addr(adminPrivateKey);
    }

    function run() external {
        setUp();

        vm.createSelectFork(vm.envString("RPC_URL"));

        console.log("Starting dummy transactions for indexer testing...");
        console.log("Hub Proxy:", hubProxy);
        console.log("IDRC Proxy:", idrcProxy);
        console.log("Reward Proxy:", rewardProxy);
        console.log("IDRX Token:", idrxToken);

        // Execute all dummy transactions
        _fundTestUsers();
        _performSubscriptions();
        _performRedemptions();
        _adminDepositFunds();
        _adminWithdrawFunds();
        _adminDepositRewards();
        _claimRewards();
        _additionalTransactions();

        console.log("All dummy transactions completed!");
    }

    function _fundTestUsers() internal {
        console.log("\n=== Funding Test Users ===");

        // Fund test users with IDRX tokens
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        IDRX idrx = IDRX(idrxToken);

        // Mint IDRX tokens to test users
        idrx.mint(user, 10000 * 10 ** 2); // 10,000 IDRX (2 decimals)

        // Also mint some to admin for testing
        idrx.mint(admin, 50000 * 10 ** 2); // 50,000 IDRX

        console.log("Funded user with 10,000 IDRX");
        console.log("Funded admin with 50,000 IDRX");

        vm.stopBroadcast();
    }

    function _performSubscriptions() internal {
        console.log("\n=== Performing Subscriptions ===");

        Hub hub = Hub(hubProxy);
        IDRX idrx = IDRX(idrxToken);

        // User subscriptions
        vm.startBroadcast(userPrivateKey);
        idrx.approve(hubProxy, type(uint256).max);
        hub.requestSubscription(idrxToken, 2000 * 10 ** 2); // 2,000 IDRX
        console.log("User subscribed 2,000 IDRX");
        vm.stopBroadcast();

        // Wait a bit to create different timestamps
        vm.warp(block.timestamp + 300); // +5 minutes

        // User subscriptions
        vm.startBroadcast(userPrivateKey);
        idrx.approve(hubProxy, type(uint256).max);
        hub.requestSubscription(idrxToken, 1500 * 10 ** 2); // 1,500 IDRX
        console.log("User subscribed 1,500 IDRX");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 600); // +10 minutes

        // User subscriptions
        vm.startBroadcast(userPrivateKey);
        idrx.approve(hubProxy, type(uint256).max);
        hub.requestSubscription(idrxToken, 3000 * 10 ** 2); // 3,000 IDRX
        console.log("User subscribed 3,000 IDRX");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 900); // +15 minutes

        // Additional subscription from user
        vm.startBroadcast(userPrivateKey);
        hub.requestSubscription(idrxToken, 1000 * 10 ** 2); // 1,000 IDRX
        console.log("User subscribed additional 1,000 IDRX");
        vm.stopBroadcast();
    }

    function _performRedemptions() internal {
        console.log("\n=== Performing Redemptions ===");

        Hub hub = Hub(hubProxy);
        IDRC idrc = IDRC(idrcProxy);

        vm.warp(block.timestamp + 1200); // +20 minutes

        // User redemption
        vm.startBroadcast(userPrivateKey);
        idrc.approve(hubProxy, type(uint256).max);
        hub.requestRedemption(idrxToken, 500 * 10 ** 2); // Redeem 500 IDRC
        console.log("User redeemed 500 IDRC");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 1800); // +30 minutes

        // User redemption
        vm.startBroadcast(userPrivateKey);
        idrc.approve(hubProxy, type(uint256).max);
        hub.requestRedemption(idrxToken, 1000 * 10 ** 2); // Redeem 1,000 IDRC
        console.log("User redeemed 1,000 IDRC");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 2400); // +40 minutes

        // User partial redemption
        vm.startBroadcast(userPrivateKey);
        idrc.approve(hubProxy, type(uint256).max);
        hub.requestRedemption(idrxToken, 750 * 10 ** 2); // Redeem 750 IDRC
        console.log("User redeemed 750 IDRC");
        vm.stopBroadcast();
    }

    function _adminDepositFunds() internal {
        console.log("\n=== Admin Deposit Funds ===");

        Hub hub = Hub(hubProxy);
        IDRX idrx = IDRX(idrxToken);

        vm.warp(block.timestamp + 3000); // +50 minutes

        vm.startBroadcast(adminPrivateKey);
        idrx.approve(hubProxy, type(uint256).max);

        // Multiple admin deposits
        hub.depositAsset(idrxToken, 5000 * 10 ** 2); // 5,000 IDRX
        console.log("Admin deposited 5,000 IDRX");

        vm.warp(block.timestamp + 600); // +10 minutes
        hub.depositAsset(idrxToken, 3000 * 10 ** 2); // 3,000 IDRX
        console.log("Admin deposited 3,000 IDRX");

        vm.warp(block.timestamp + 1200); // +20 minutes
        hub.depositAsset(idrxToken, 10000 * 10 ** 2); // 10,000 IDRX
        console.log("Admin deposited 10,000 IDRX");

        vm.stopBroadcast();
    }

    function _adminWithdrawFunds() internal {
        console.log("\n=== Admin Withdraw Funds ===");

        Hub hub = Hub(hubProxy);

        vm.warp(block.timestamp + 1800); // +30 minutes

        vm.startBroadcast(adminPrivateKey);

        // Multiple admin withdrawals
        hub.withdrawAsset(idrxToken, 2000 * 10 ** 2); // 2,000 IDRX
        console.log("Admin withdrew 2,000 IDRX");

        vm.warp(block.timestamp + 900); // +15 minutes
        hub.withdrawAsset(idrxToken, 1500 * 10 ** 2); // 1,500 IDRX
        console.log("Admin withdrew 1,500 IDRX");

        vm.stopBroadcast();
    }

    function _adminDepositRewards() internal {
        console.log("\n=== Admin Deposit Rewards ===");

        Reward reward = Reward(rewardProxy);
        IDRX idrx = IDRX(idrxToken);

        vm.warp(block.timestamp + 2400); // +40 minutes

        vm.startBroadcast(adminPrivateKey);
        idrx.approve(rewardProxy, type(uint256).max);

        // Multiple reward injections
        reward.injectReward(1000 * 10 ** 2); // 1,000 IDRX reward
        console.log("Admin injected 1,000 IDRX reward");

        vm.warp(block.timestamp + 1800); // +30 minutes
        reward.injectReward(2000 * 10 ** 2); // 2,000 IDRX reward
        console.log("Admin injected 2,000 IDRX reward");

        vm.warp(block.timestamp + 3600); // +1 hour
        reward.injectReward(1500 * 10 ** 2); // 1,500 IDRX reward
        console.log("Admin injected 1,500 IDRX reward");

        vm.stopBroadcast();
    }

    function _claimRewards() internal {
        console.log("\n=== Claiming Rewards ===");

        Reward reward = Reward(rewardProxy);

        vm.warp(block.timestamp + 1200); // +20 minutes

        // User claims rewards
        vm.startBroadcast(userPrivateKey);
        if (reward.earned(user) > 0) {
            reward.claimReward();
            console.log("User claimed rewards");
        } else {
            console.log("User has no rewards to claim");
        }
        vm.stopBroadcast();
    }

    function _additionalTransactions() internal {
        console.log("\n=== Additional Mixed Transactions ===");

        Hub hub = Hub(hubProxy);
        IDRC idrc = IDRC(idrcProxy);
        Reward reward = Reward(rewardProxy);

        vm.warp(block.timestamp + 900); // +15 minutes

        // More subscriptions
        vm.startBroadcast(userPrivateKey);
        hub.requestSubscription(idrxToken, 2500 * 10 ** 2);
        console.log("User additional subscription of 2,500 IDRX");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 600); // +10 minutes

        // Admin deposits more rewards
        vm.startBroadcast(adminPrivateKey);
        reward.injectReward(3000 * 10 ** 2);
        console.log("Admin injected additional 3,000 IDRX reward");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 1200); // +20 minutes

        // User makes another subscription
        vm.startBroadcast(userPrivateKey);
        hub.requestSubscription(idrxToken, 1750 * 10 ** 2);
        console.log("User additional subscription of 1,750 IDRX");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 900); // +15 minutes

        // Admin withdraws some funds
        vm.startBroadcast(adminPrivateKey);
        hub.withdrawAsset(idrxToken, 2500 * 10 ** 2);
        console.log("Admin withdrew 2,500 IDRX");
        vm.stopBroadcast();

        vm.warp(block.timestamp + 1800); // +30 minutes

        // Final reward claims
        vm.startBroadcast(userPrivateKey);
        if (reward.earned(user) > 0) {
            reward.claimReward();
            console.log("User final reward claim");
        }
        vm.stopBroadcast();

        // Final statistics
        console.log("\n=== Final Statistics ===");
        console.log("Total IDRC Supply:", idrc.totalSupply());
        console.log("Total Rewards Distributed:", reward.totalRewardsDistributed());
        console.log("Total Rewards Claimed:", reward.totalRewardsClaimed());
        console.log("Unclaimed Rewards:", reward.totalUnclaimedRewards());
    }
}
