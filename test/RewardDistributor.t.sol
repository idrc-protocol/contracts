// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Reward} from "../src/RewardDistributor.sol";
import {Hub} from "../src/Hub.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRX} from "../src/IDRX.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RewardDistributorUnitTest is Test {
    Reward internal rewardImpl;
    Reward internal reward;
    Hub internal hubImpl;
    Hub internal hub;
    IDRC internal idrcImpl;
    IDRC internal idrc;
    IDRX internal asset;

    address internal owner = makeAddr("OWNER");
    address internal adminManager = makeAddr("ADMIN_MANAGER");
    address internal user = makeAddr("USER");
    address internal user2 = makeAddr("USER2");
    address internal other = makeAddr("OTHER");

    uint256 internal constant INITIAL_BALANCE = 10_000_000 * 1e2;

    event RewardInjected(uint256 amount, uint256 timestamp);
    event RewardDistributed(uint256 amount, uint256 newRewardPerToken);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy asset token
        asset = new IDRX("IDRX Token", "IDRX", 2);

        // Compute addresses
        uint256 nonce = vm.getNonce(owner);
        address predictedIdrcImpl = vm.computeCreateAddress(owner, nonce);
        address predictedHubImpl = vm.computeCreateAddress(owner, nonce + 1);
        address predictedRewardImpl = vm.computeCreateAddress(owner, nonce + 2);
        address predictedRewardProxy = vm.computeCreateAddress(owner, nonce + 3);
        address predictedIdrcProxy = vm.computeCreateAddress(owner, nonce + 4);
        address predictedHubProxy = vm.computeCreateAddress(owner, nonce + 5);

        // Deploy implementations
        idrcImpl = new IDRC();
        hubImpl = new Hub();
        rewardImpl = new Reward();

        // Deploy reward proxy
        bytes memory rewardInitData =
            abi.encodeWithSelector(Reward.initialize.selector, predictedHubProxy, predictedIdrcProxy, adminManager);
        ERC1967Proxy rewardProxy = new ERC1967Proxy(address(rewardImpl), rewardInitData);
        reward = Reward(address(rewardProxy));

        // Deploy IDRC and Hub proxies
        bytes memory idrcInitData =
            abi.encodeWithSelector(IDRC.initialize.selector, predictedHubProxy, predictedRewardProxy);
        ERC1967Proxy idrcProxy = new ERC1967Proxy(address(idrcImpl), idrcInitData);
        idrc = IDRC(address(idrcProxy));

        bytes memory hubInitData =
            abi.encodeWithSelector(Hub.initialize.selector, address(asset), address(idrc), adminManager);
        ERC1967Proxy hubProxy = new ERC1967Proxy(address(hubImpl), hubInitData);
        hub = Hub(address(hubProxy));

        vm.stopPrank();

        // Mint tokens to users
        asset.mint(user, INITIAL_BALANCE);
        asset.mint(user2, INITIAL_BALANCE);
    }

    // ====== Initialization Tests ======

    function testInitializeCorrectly() public view {
        assertEq(reward.hub(), address(hub));
        assertEq(reward.idrc(), address(idrc));
        assertEq(reward.owner(), owner);
        assertTrue(reward.hasRole(reward.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(reward.hasRole(reward.ADMIN_MANAGER_ROLE(), adminManager));
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        reward.initialize(address(hub), address(idrc), adminManager);
    }

    function testInitializeWithZeroAddresses() public {
        Reward newRewardImpl = new Reward();
        bytes memory initData = abi.encodeWithSelector(Reward.initialize.selector, address(0), address(0), address(0));
        vm.expectRevert(Reward.ZeroAddress.selector);
        new ERC1967Proxy(address(newRewardImpl), initData);
    }

    // ====== InjectReward Tests ======

    function testInjectRewardSuccess() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        // User subscribes first (so TVL > 0)
        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // Admin injects reward
        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);

        vm.expectEmit(false, false, false, true);
        emit RewardInjected(rewardAmount, block.timestamp);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(reward)), rewardAmount);
        assertEq(reward.earned(user), rewardAmount);
    }

    function testInjectRewardMultipleTimes() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 reward1 = 5_000 * 1e2;
        uint256 reward2 = 3_000 * 1e2;

        // User subscribes
        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // First reward injection
        vm.prank(owner);
        asset.mint(adminManager, reward1 + reward2);

        vm.startPrank(adminManager);
        asset.approve(address(reward), reward1);
        reward.injectReward(reward1);

        // Second reward injection
        asset.approve(address(reward), reward2);
        reward.injectReward(reward2);
        vm.stopPrank();

        assertEq(reward.earned(user), 8_000 * 1e2);
    }

    function testInjectRewardMultipleStakers() public {
        uint256 subscription1 = 60_000 * 1e2;
        uint256 subscription2 = 40_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        // User 1 subscribes
        vm.startPrank(user);
        asset.approve(address(hub), subscription1);
        hub.requestSubscription(address(asset), subscription1);
        vm.stopPrank();

        // User 2 subscribes
        vm.startPrank(user2);
        asset.approve(address(hub), subscription2);
        hub.requestSubscription(address(asset), subscription2);
        vm.stopPrank();

        // Inject reward
        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        // User 1 should get 60% of rewards (6000)
        // User 2 should get 40% of rewards (4000)
        assertEq(reward.earned(user), 6_000 * 1e2);
        assertEq(reward.earned(user2), 4_000 * 1e2);
    }

    function testInjectRewardRevertsForNonAdminManager() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(other, rewardAmount);

        vm.startPrank(other);
        asset.approve(address(reward), rewardAmount);
        vm.expectRevert();
        reward.injectReward(rewardAmount);
        vm.stopPrank();
    }

    function testInjectRewardRevertsForZeroAmount() public {
        uint256 subscriptionAmount = 100_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(adminManager);
        vm.expectRevert(Reward.ZeroAmount.selector);
        reward.injectReward(0);
    }

    function testInjectRewardRevertsForZeroTVL() public {
        uint256 rewardAmount = 10_000 * 1e2;

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        vm.expectRevert(Reward.NoTokensMinted.selector);
        reward.injectReward(rewardAmount);
        vm.stopPrank();
    }

    function testInjectRewardRevertsForInsufficientBalance() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // Don't mint tokens to adminManager
        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        vm.expectRevert();
        reward.injectReward(rewardAmount);
        vm.stopPrank();
    }

    function testInjectRewardRevertsForInsufficientAllowance() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        // Don't approve tokens
        vm.prank(adminManager);
        vm.expectRevert();
        reward.injectReward(rewardAmount);
    }

    // ====== Earned Tests ======

    function testEarnedInitiallyZero() public view {
        assertEq(reward.earned(user), 0);
    }

    function testEarnedAfterRewardInjection() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        assertEq(reward.earned(user), rewardAmount);
    }

    function testEarnedProportionalDistribution() public {
        uint256 subscription1 = 30_000 * 1e2;
        uint256 subscription2 = 70_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        // User 1 subscribes 30%
        vm.startPrank(user);
        asset.approve(address(hub), subscription1);
        hub.requestSubscription(address(asset), subscription1);
        vm.stopPrank();

        // User 2 subscribes 70%
        vm.startPrank(user2);
        asset.approve(address(hub), subscription2);
        hub.requestSubscription(address(asset), subscription2);
        vm.stopPrank();

        // Inject reward
        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        // Check proportional distribution
        assertEq(reward.earned(user), 3_000 * 1e2); // 30%
        assertEq(reward.earned(user2), 7_000 * 1e2); // 70%
    }

    function testEarnedAfterBalanceChange() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount1 = 10_000 * 1e2;
        uint256 rewardAmount2 = 5_000 * 1e2;

        // User subscribes
        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // First reward injection
        vm.prank(owner);
        asset.mint(adminManager, rewardAmount1);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount1);
        reward.injectReward(rewardAmount1);
        vm.stopPrank();

        // User2 subscribes after first reward
        vm.startPrank(user2);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // Second reward injection
        vm.prank(owner);
        asset.mint(adminManager, rewardAmount2);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount2);
        reward.injectReward(rewardAmount2);
        vm.stopPrank();

        assertEq(reward.earned(user), 12_500 * 1e2);
        assertEq(reward.earned(user2), 2_500 * 1e2);
    }

    function testEarnedForNonStaker() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        assertEq(reward.earned(other), 0);
    }

    // ====== ClaimReward Tests ======

    function testClaimRewardSuccess() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        // User subscribes
        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // Inject reward
        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        uint256 userBalanceBefore = asset.balanceOf(user);
        assertEq(reward.earned(user), rewardAmount);

        // Claim reward
        vm.prank(user);
        reward.claimReward();

        assertEq(reward.earned(user), 0);
        assertEq(asset.balanceOf(user), userBalanceBefore + rewardAmount);
    }

    function testClaimRewardMultipleTimes() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 reward1 = 5_000 * 1e2;
        uint256 reward2 = 3_000 * 1e2;

        // User subscribes
        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // First reward
        vm.prank(owner);
        asset.mint(adminManager, reward1);

        vm.startPrank(adminManager);
        asset.approve(address(reward), reward1);
        reward.injectReward(reward1);
        vm.stopPrank();

        // Claim first reward
        vm.prank(user);
        reward.claimReward();

        assertEq(reward.earned(user), 0);

        // Second reward
        vm.prank(owner);
        asset.mint(adminManager, reward2);

        vm.startPrank(adminManager);
        asset.approve(address(reward), reward2);
        reward.injectReward(reward2);
        vm.stopPrank();

        // Claim second reward
        uint256 userBalanceBefore = asset.balanceOf(user);
        vm.prank(user);
        reward.claimReward();

        assertEq(asset.balanceOf(user), userBalanceBefore + reward2);
    }

    function testClaimRewardRevertsForNoRewards() public {
        vm.prank(user);
        vm.expectRevert(Reward.NoRewardToClaim.selector);
        reward.claimReward();
    }

    function testClaimRewardRevertsAfterClaiming() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        vm.prank(user);
        reward.claimReward();

        // Try to claim again
        vm.prank(user);
        vm.expectRevert(Reward.NoRewardToClaim.selector);
        reward.claimReward();
    }

    function testClaimRewardByAnyoneForUser() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        uint256 userBalanceBefore = asset.balanceOf(user);

        // Other person claims for user (via Hub)
        vm.prank(address(hub));
        reward.claimReward(user);

        assertEq(asset.balanceOf(user), userBalanceBefore + rewardAmount);
    }

    // ====== UpdateReward Tests ======

    function testUpdateRewardByIDRC() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        // IDRC can update reward
        vm.prank(address(idrc));
        reward.updateReward(user);
    }

    function testUpdateRewardRevertsForNonHub() public {
        vm.prank(other);
        vm.expectRevert(Reward.NotHubCaller.selector);
        reward.updateReward(user);
    }

    // ====== Access Control Tests ======

    function testAdminManagerRoleGranted() public view {
        assertTrue(reward.hasRole(reward.ADMIN_MANAGER_ROLE(), adminManager));
    }

    function testGrantAdminManagerRole() public {
        address newAdmin = makeAddr("NEW_ADMIN");

        vm.startPrank(owner);
        reward.grantRole(reward.ADMIN_MANAGER_ROLE(), newAdmin);
        vm.stopPrank();

        assertTrue(reward.hasRole(reward.ADMIN_MANAGER_ROLE(), newAdmin));

        // New admin can inject rewards
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(newAdmin, rewardAmount);

        vm.startPrank(newAdmin);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();
    }

    function testRevokeAdminManagerRole() public {
        vm.startPrank(owner);
        reward.revokeRole(reward.ADMIN_MANAGER_ROLE(), adminManager);
        vm.stopPrank();

        assertFalse(reward.hasRole(reward.ADMIN_MANAGER_ROLE(), adminManager));

        // Revoked admin cannot inject rewards
        vm.prank(adminManager);
        vm.expectRevert();
        reward.injectReward(1000);
    }

    // ====== Ownership Tests ======

    function testOwnerIsSetCorrectly() public view {
        assertEq(reward.owner(), owner);
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("NEW_OWNER");

        vm.prank(owner);
        reward.transferOwnership(newOwner);

        assertEq(reward.owner(), newOwner);
    }

    function testTransferOwnershipRevertsForNonOwner() public {
        address newOwner = makeAddr("NEW_OWNER");

        vm.prank(user);
        vm.expectRevert();
        reward.transferOwnership(newOwner);
    }

    // ====== Upgrade Tests ======

    function testUpgradeByOwner() public {
        Reward newImplementation = new Reward();

        vm.prank(owner);
        reward.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradeRevertsForNonOwner() public {
        Reward newImplementation = new Reward();

        vm.prank(user);
        vm.expectRevert();
        reward.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradePreservesState() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        uint256 earnedBefore = reward.earned(user);

        Reward newImplementation = new Reward();

        vm.prank(owner);
        reward.upgradeToAndCall(address(newImplementation), "");

        assertEq(reward.earned(user), earnedBefore);
        assertEq(reward.hub(), address(hub));
        assertEq(reward.idrc(), address(idrc));
    }

    // ====== View Function Tests ======

    function testLastDistribution() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        assertEq(reward.lastDistribution(), 0);

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        assertEq(reward.lastDistribution(), block.timestamp);
    }

    function testRewardPerTokenStored() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        assertEq(reward.rewardPerTokenStored(), 0);

        vm.prank(owner);
        asset.mint(adminManager, rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        // rewardPerTokenStored = balance * 1e6 / supply
        // = 10_000 * 1e2 * 1e6 / 100_000 * 1e2 = 100000
        assertEq(reward.rewardPerTokenStored(), 100000);
    }

    // ====== Edge Cases and Complex Scenarios ======

    function testComplexMultiUserScenario() public {
        uint256 sub1 = 50_000 * 1e2;
        uint256 sub2 = 30_000 * 1e2;
        uint256 reward1 = 8_000 * 1e2;
        uint256 reward2 = 4_000 * 1e2;

        // User1 subscribes 50k
        vm.startPrank(user);
        asset.approve(address(hub), sub1);
        hub.requestSubscription(address(asset), sub1);
        vm.stopPrank();

        // Inject first reward (user1 gets all)
        vm.prank(owner);
        asset.mint(adminManager, reward1);

        vm.startPrank(adminManager);
        asset.approve(address(reward), reward1);
        reward.injectReward(reward1);
        vm.stopPrank();

        // User2 subscribes 30k (now total is 80k)
        vm.startPrank(user2);
        asset.approve(address(hub), sub2);
        hub.requestSubscription(address(asset), sub2);
        vm.stopPrank();

        // Inject second reward (split proportionally)
        vm.prank(owner);
        asset.mint(adminManager, reward2);

        vm.startPrank(adminManager);
        asset.approve(address(reward), reward2);
        reward.injectReward(reward2);
        vm.stopPrank();

        // First injection: rewardPerTokenStored = 8000 * 1e6 / 50000 = 160000
        // user2 subscribes (userRewardPerTokenPaid[user2] = 160000)
        // Second injection: rewardPerTokenStored += 4000 * 1e6 / 80000 = 160000 + 50000 = 210000
        // user1 earned: 50000 * (210000 - 0) / 1e6 = 10500
        // user2 earned: 30000 * (210000 - 160000) / 1e6 = 1500
        assertEq(reward.earned(user), 10_500 * 1e2);
        assertEq(reward.earned(user2), 1_500 * 1e2);

        // Verify the total rewards match injected amount
        assertEq(asset.balanceOf(address(reward)), 12_000 * 1e2);
        assertEq(reward.earned(user) + reward.earned(user2), 12_000 * 1e2);
    }

    function testRewardAccumulationAfterClaim() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 reward1 = 5_000 * 1e2;
        uint256 reward2 = 3_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        // First reward
        vm.prank(owner);
        asset.mint(adminManager, reward1);

        vm.startPrank(adminManager);
        asset.approve(address(reward), reward1);
        reward.injectReward(reward1);
        vm.stopPrank();

        // Claim
        vm.prank(user);
        reward.claimReward();

        // Second reward
        vm.prank(owner);
        asset.mint(adminManager, reward2);

        vm.startPrank(adminManager);
        asset.approve(address(reward), reward2);
        reward.injectReward(reward2);
        vm.stopPrank();

        // Should only have second reward
        assertEq(reward.earned(user), reward2);
    }
}
