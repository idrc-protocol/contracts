// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Hub} from "../src/Hub.sol";
import {Reward} from "../src/RewardDistributor.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRX} from "../src/IDRX.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract HubTest is Test {
    IDRX internal asset;
    Hub internal hubImpl;
    IDRC internal idrcImpl;
    Hub internal hub;
    IDRC internal idrc;
    Reward internal rewardImpl;
    Reward internal reward;

    address internal owner = makeAddr("OWNER");
    address internal adminManager = makeAddr("ADMIN_MANAGER");
    address internal user = makeAddr("USER");
    address internal other = makeAddr("OTHER");

    uint256 internal constant USER_BALANCE = 1_000_000 * 1e2;
    uint256 internal constant PRICE = 100;

    function setUp() public {
        vm.startPrank(owner);
        asset = new IDRX("IDRX Token", "IDRX", 2);

        uint256 nonce = vm.getNonce(owner);
        address predictedIdrcImpl = vm.computeCreateAddress(owner, nonce);
        address predictedHubImpl = vm.computeCreateAddress(owner, nonce + 1);
        address predictedRewardImpl = vm.computeCreateAddress(owner, nonce + 2);
        address predictedRewardProxy = vm.computeCreateAddress(owner, nonce + 3);
        address predictedIdrcProxy = vm.computeCreateAddress(owner, nonce + 4);
        address predictedHubProxy = vm.computeCreateAddress(owner, nonce + 5);

        idrcImpl = new IDRC();
        hubImpl = new Hub();
        rewardImpl = new Reward();

        assertEq(address(idrcImpl), predictedIdrcImpl);
        assertEq(address(hubImpl), predictedHubImpl);
        assertEq(address(rewardImpl), predictedRewardImpl);

        bytes memory rewardInitData =
            abi.encodeWithSelector(Reward.initialize.selector, predictedHubProxy, predictedIdrcProxy, adminManager);
        ERC1967Proxy rewardProxy = new ERC1967Proxy(address(rewardImpl), rewardInitData);

        assertEq(address(rewardProxy), predictedRewardProxy);

        reward = Reward(address(rewardProxy));

        bytes memory idrcInitData =
            abi.encodeWithSelector(IDRC.initialize.selector, predictedHubProxy, predictedRewardProxy);
        ERC1967Proxy idrcProxy = new ERC1967Proxy(address(idrcImpl), idrcInitData);
        ERC1967Proxy hubProxy = new ERC1967Proxy(
            address(hubImpl),
            abi.encodeWithSelector(Hub.initialize.selector, address(asset), predictedIdrcProxy, adminManager)
        );

        assertEq(address(idrcProxy), predictedIdrcProxy);
        assertEq(address(hubProxy), predictedHubProxy);

        hub = Hub(address(hubProxy));
        idrc = IDRC(address(idrcProxy));
        reward = Reward(address(rewardProxy));

        vm.stopPrank();

        asset.mint(user, USER_BALANCE);
    }

    function testInitializeGrantsRoles() public view {
        assertTrue(hub.hasRole(hub.ADMIN_ROLE(), adminManager));
        assertTrue(hub.hasRole(hub.DEFAULT_ADMIN_ROLE(), owner));
    }

    // ====== Subscription Tests =======

    function testRequestSubscriptionMintsShares() public {
        uint256 amount = 32000 * 1e2;
        uint256 expectedShares = amount;

        vm.startPrank(user);
        asset.approve(address(hub), amount);

        vm.expectEmit(true, true, false, true);
        emit Hub.RequestedSubscription(user, amount, expectedShares);

        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), amount);
        assertEq(idrc.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(user), USER_BALANCE - amount);
    }

    function testRequestSubscriptionRevertsForZeroAmount() public {
        vm.expectRevert(Hub.InvalidAmount.selector);
        vm.prank(user);
        hub.requestSubscription(address(asset), 0);
    }

    function testRequestSubscriptionRevertsForUnsupportedAsset() public {
        IDRX unsupported = new IDRX("Other", "OTH", 2);
        unsupported.mint(user, 100 * 1e2);

        vm.startPrank(user);
        unsupported.approve(address(hub), 100 * 1e2);
        vm.expectRevert(Hub.AssetNotSupported.selector);
        hub.requestSubscription(address(unsupported), 100 * 1e2);
        vm.stopPrank();
    }

    // ====== Withdrawal Owner Tests =======

    function testWithdrawAssetByOwnerSuccess() public {
        uint256 amount = 5000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), amount);

        vm.startPrank(adminManager);
        hub.withdrawAsset(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), 0);
        assertEq(asset.balanceOf(adminManager), amount);
    }

    function testWithdrawAssetByNonOwnerReverts() public {
        uint256 amount = 5000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), amount);

        vm.prank(other);
        vm.expectRevert();
        hub.withdrawAsset(address(asset), amount);
    }

    function testWithdrawAssetByOwnerRevertsForInsufficientBalance() public {
        vm.prank(adminManager);
        vm.expectRevert(Hub.InsufficientBalance.selector);
        hub.withdrawAsset(address(asset), 1);
    }

    function testWithdrawAssetByOwnerRevertsForUnsupportedAsset() public {
        IDRX unsupported = new IDRX("Other", "OTH", 2);

        vm.prank(adminManager);
        vm.expectRevert();
        hub.withdrawAsset(address(unsupported), 1);
    }

    function testWithdrawAssetByOwnerRevertsForZeroAmount() public {
        vm.prank(adminManager);
        vm.expectRevert(Hub.InvalidAmount.selector);
        hub.withdrawAsset(address(asset), 0);
    }

    // ====== Redemption Tests =======

    function testRequestRedemptionBurnsSharesAndTransfersAsset() public {
        uint256 amount = 32000 * 1e2;
        uint256 shares = amount;

        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);

        idrc.approve(address(hub), shares);

        vm.expectEmit(true, true, false, true);
        emit Hub.RequestedRedemption(user, shares, amount);

        hub.requestRedemption(address(asset), shares);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), USER_BALANCE);
        assertEq(asset.balanceOf(address(hub)), 0);
    }

    function testRequestRedemptionRevertsForInsufficientBalance() public {
        assertEq(idrc.balanceOf(user), 0);
        vm.prank(user);
        (bool success, bytes memory data) =
            address(hub).call(abi.encodeWithSelector(Hub.requestRedemption.selector, address(asset), hub.PRECISION()));

        assertFalse(success);
        assertEq(bytes4(data), Hub.InsufficientBalance.selector);
    }

    // ====== Reward Distributor Tests =======
    function testRewardDistributorInitializedCorrectly() public view {
        assertEq(reward.hub(), address(hub));
        assertEq(reward.idrc(), address(idrc));
    }

    function testDistributeRewardsByOwner() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        // First, user needs to subscribe so TVL > 0
        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(address(adminManager), rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        // Verify rewards are tracked correctly
        assertEq(reward.earned(user), rewardAmount);
    }

    function testInjectRewardByNonOwnerReverts() public {
        uint256 rewardAmount = 10_000 * 1e2;

        vm.prank(other);
        vm.expectRevert();
        reward.injectReward(rewardAmount);
    }

    function testInjectRewardRevertsForInsufficientBalance() public {
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(owner);
        vm.expectRevert();
        reward.injectReward(rewardAmount);
        vm.stopPrank();
    }

    function testInjectRewardRevertsForZeroAmount() public {
        vm.startPrank(owner);
        vm.expectRevert();
        reward.injectReward(0);
        vm.stopPrank();
    }

    // ====== User Reward Tests =======

    function testUserRewardAccumulation() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(address(adminManager), rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        assertEq(reward.earned(user), rewardAmount);
    }

    function testClaimRewardsByUser() public {
        uint256 subscriptionAmount = 100_000 * 1e2;
        uint256 rewardAmount = 10_000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscriptionAmount);
        hub.requestSubscription(address(asset), subscriptionAmount);
        vm.stopPrank();

        vm.prank(owner);
        asset.mint(address(adminManager), rewardAmount);

        vm.startPrank(adminManager);
        asset.approve(address(reward), rewardAmount);
        reward.injectReward(rewardAmount);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), subscriptionAmount);
        assertEq(reward.earned(user), rewardAmount);

        vm.prank(user);
        reward.claimReward();

        assertEq(idrc.balanceOf(user), subscriptionAmount);
        assertEq(asset.balanceOf(user), USER_BALANCE - subscriptionAmount + rewardAmount);
        assertEq(reward.earned(user), 0);
    }

    function testClaimRewardsByUserRevertsForNoRewards() public {
        assertEq(reward.earned(user), 0);
        vm.prank(user);
        vm.expectRevert();
        reward.claimReward();
    }

    // ====== IDRC Tests =======

    function testIDRCMintByHubRevertsForNonHub() public {
        vm.expectRevert(IDRC.Unauthorized.selector);
        vm.prank(other);
        idrc.mintByHub(other, 1);
    }

    function testIDRCBurnByHubRevertsForNonHub() public {
        vm.expectRevert(IDRC.Unauthorized.selector);
        vm.prank(other);
        idrc.burnByHub(other, 1);
    }
}
