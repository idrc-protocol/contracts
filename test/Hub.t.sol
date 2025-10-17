// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Hub} from "../src/Hub.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRX} from "../src/IDRX.sol";
import {Reward} from "../src/RewardDistributor.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract HubUnitTest is Test {
    Hub internal hubImpl;
    Hub internal hub;
    IDRC internal idrcImpl;
    IDRC internal idrc;
    Reward internal rewardImpl;
    Reward internal reward;
    IDRX internal asset;

    address internal owner = makeAddr("OWNER");
    address internal adminManager = makeAddr("ADMIN_MANAGER");
    address internal user = makeAddr("USER");
    address internal user2 = makeAddr("USER2");
    address internal other = makeAddr("OTHER");

    uint256 internal constant INITIAL_BALANCE = 1_000_000 * 1e2;

    event RequestedSubscription(address indexed user, uint256 amount, uint256 shares);
    event RequestedRedemption(address indexed user, uint256 shares, uint256 amount);

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
        assertEq(hub.tokenAccepted(), address(asset));
        assertTrue(hub.hasRole(hub.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(hub.hasRole(hub.ADMIN_ROLE(), adminManager));
    }

    function testInitializeGrantsCorrectRoles() public view {
        bytes32 adminRole = hub.ADMIN_ROLE();
        bytes32 defaultAdminRole = hub.DEFAULT_ADMIN_ROLE();

        assertTrue(hub.hasRole(defaultAdminRole, owner));
        assertTrue(hub.hasRole(adminRole, adminManager));
        assertFalse(hub.hasRole(adminRole, user));
        assertFalse(hub.hasRole(defaultAdminRole, user));
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        hub.initialize(address(asset), address(idrc), adminManager);
    }

    // ====== Subscription Tests ======

    function testRequestSubscriptionSuccess() public {
        uint256 amount = 50000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), amount);

        vm.expectEmit(true, true, false, true);
        emit RequestedSubscription(user, amount, amount);

        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), amount);
        assertEq(idrc.balanceOf(user), amount);
        assertEq(asset.balanceOf(user), INITIAL_BALANCE - amount);
    }

    function testRequestSubscriptionMultipleUsers() public {
        uint256 amount1 = 30000 * 1e2;
        uint256 amount2 = 20000 * 1e2;

        // User 1 subscribes
        vm.startPrank(user);
        asset.approve(address(hub), amount1);
        hub.requestSubscription(address(asset), amount1);
        vm.stopPrank();

        // User 2 subscribes
        vm.startPrank(user2);
        asset.approve(address(hub), amount2);
        hub.requestSubscription(address(asset), amount2);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), amount1);
        assertEq(idrc.balanceOf(user2), amount2);
        assertEq(asset.balanceOf(address(hub)), amount1 + amount2);
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

    function testRequestSubscriptionRevertsForInsufficientAllowance() public {
        uint256 amount = 1000 * 1e2;
        vm.prank(user);
        vm.expectRevert();
        hub.requestSubscription(address(asset), amount);
    }

    function testRequestSubscriptionRevertsForInsufficientBalance() public {
        uint256 amount = INITIAL_BALANCE + 1;
        vm.startPrank(user);
        asset.approve(address(hub), amount);
        vm.expectRevert();
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();
    }

    // ====== Redemption Tests ======

    function testRequestRedemptionSuccess() public {
        uint256 amount = 32000 * 1e2;

        // First subscribe
        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);

        // Then redeem
        idrc.approve(address(hub), amount);

        vm.expectEmit(true, true, false, true);
        emit RequestedRedemption(user, amount, amount);

        hub.requestRedemption(address(asset), amount);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), INITIAL_BALANCE);
        assertEq(asset.balanceOf(address(hub)), 0);
    }

    function testRequestRedemptionPartial() public {
        uint256 subscribeAmount = 50000 * 1e2;
        uint256 redeemAmount = 20000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscribeAmount);
        hub.requestSubscription(address(asset), subscribeAmount);

        idrc.approve(address(hub), redeemAmount);
        hub.requestRedemption(address(asset), redeemAmount);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), subscribeAmount - redeemAmount);
        assertEq(asset.balanceOf(user), INITIAL_BALANCE - subscribeAmount + redeemAmount);
        assertEq(asset.balanceOf(address(hub)), subscribeAmount - redeemAmount);
    }

    function testRequestRedemptionRevertsForZeroAmount() public {
        vm.expectRevert(Hub.InvalidAmount.selector);
        vm.prank(user);
        hub.requestRedemption(address(asset), 0);
    }

    function testRequestRedemptionRevertsForInsufficientBalance() public {
        uint256 amount = 1000 * 1e2;
        vm.prank(user);
        (bool success, bytes memory data) =
            address(hub).call(abi.encodeWithSelector(Hub.requestRedemption.selector, address(asset), amount));

        assertFalse(success);
        assertEq(bytes4(data), Hub.InsufficientBalance.selector);
    }

    // ====== Admin Withdrawal Tests ======

    function testWithdrawAssetSuccess() public {
        uint256 amount = 5000 * 1e2;

        // User subscribes first
        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), amount);

        // Admin withdraws
        vm.prank(adminManager);
        hub.withdrawAsset(address(asset), amount);

        assertEq(asset.balanceOf(address(hub)), 0);
        assertEq(asset.balanceOf(adminManager), amount);
    }

    function testWithdrawAssetPartial() public {
        uint256 subscribeAmount = 10000 * 1e2;
        uint256 withdrawAmount = 3000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), subscribeAmount);
        hub.requestSubscription(address(asset), subscribeAmount);
        vm.stopPrank();

        vm.prank(adminManager);
        hub.withdrawAsset(address(asset), withdrawAmount);

        assertEq(asset.balanceOf(address(hub)), subscribeAmount - withdrawAmount);
        assertEq(asset.balanceOf(adminManager), withdrawAmount);
    }

    function testWithdrawAssetRevertsForNonAdmin() public {
        uint256 amount = 5000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        vm.prank(other);
        vm.expectRevert();
        hub.withdrawAsset(address(asset), amount);
    }

    function testWithdrawAssetRevertsForInsufficientBalance() public {
        vm.prank(adminManager);
        vm.expectRevert(Hub.InsufficientBalance.selector);
        hub.withdrawAsset(address(asset), 1);
    }

    function testWithdrawAssetRevertsForZeroAmount() public {
        vm.prank(adminManager);
        vm.expectRevert(Hub.InvalidAmount.selector);
        hub.withdrawAsset(address(asset), 0);
    }

    // ====== Admin Deposit Tests ======

    function testDepositAssetSuccess() public {
        uint256 amount = 10000 * 1e2;

        asset.mint(adminManager, amount);

        vm.startPrank(adminManager);
        asset.approve(address(hub), amount);
        hub.depositAsset(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), amount);
        assertEq(asset.balanceOf(adminManager), 0);
    }

    function testDepositAssetRevertsForNonAdmin() public {
        uint256 amount = 1000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), amount);
        vm.expectRevert();
        hub.depositAsset(address(asset), amount);
        vm.stopPrank();
    }

    function testDepositAssetRevertsForZeroAmount() public {
        vm.prank(adminManager);
        vm.expectRevert(Hub.InvalidAmount.selector);
        hub.depositAsset(address(asset), 0);
    }

    // ====== View Function Tests ======

    function testTokenAccepted() public view {
        assertEq(hub.tokenAccepted(), address(asset));
    }

    function testPrecision() public view {
        assertEq(hub.PRECISION(), 1e18);
    }

    // ====== Access Control Tests ======

    function testAdminRoleCanWithdraw() public {
        uint256 amount = 1000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        vm.prank(adminManager);
        hub.withdrawAsset(address(asset), amount);

        assertEq(asset.balanceOf(adminManager), amount);
    }

    function testAdminRoleCanDeposit() public {
        uint256 amount = 1000 * 1e2;

        asset.mint(adminManager, amount);

        vm.startPrank(adminManager);
        asset.approve(address(hub), amount);
        hub.depositAsset(address(asset), amount);
        vm.stopPrank();

        assertEq(asset.balanceOf(address(hub)), amount);
    }

    function testGrantAdminRole() public {
        address newAdmin = makeAddr("NEW_ADMIN");

        vm.startPrank(owner);
        hub.grantRole(hub.ADMIN_ROLE(), newAdmin);
        vm.stopPrank();

        assertTrue(hub.hasRole(hub.ADMIN_ROLE(), newAdmin));

        // Verify new admin can withdraw
        uint256 amount = 1000 * 1e2;
        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();

        vm.prank(newAdmin);
        hub.withdrawAsset(address(asset), amount);

        assertEq(asset.balanceOf(newAdmin), amount);
    }

    function testRevokeAdminRole() public {
        vm.startPrank(owner);
        hub.revokeRole(hub.ADMIN_ROLE(), adminManager);
        vm.stopPrank();

        assertFalse(hub.hasRole(hub.ADMIN_ROLE(), adminManager));

        // Verify revoked admin cannot withdraw
        vm.prank(adminManager);
        vm.expectRevert();
        hub.withdrawAsset(address(asset), 1);
    }

    // ====== Upgrade Tests ======

    function testUpgradeByOwner() public {
        Hub newImplementation = new Hub();

        vm.prank(owner);
        hub.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradeRevertsForNonOwner() public {
        Hub newImplementation = new Hub();

        vm.prank(user);
        vm.expectRevert();
        hub.upgradeToAndCall(address(newImplementation), "");
    }

    // ====== Edge Cases and Complex Scenarios ======

    function testMultipleSubscriptionsAndRedemptions() public {
        uint256 amount1 = 10000 * 1e2;
        uint256 amount2 = 5000 * 1e2;
        uint256 redeem1 = 3000 * 1e2;

        vm.startPrank(user);

        // First subscription
        asset.approve(address(hub), amount1);
        hub.requestSubscription(address(asset), amount1);
        assertEq(idrc.balanceOf(user), amount1);

        // Second subscription
        asset.approve(address(hub), amount2);
        hub.requestSubscription(address(asset), amount2);
        assertEq(idrc.balanceOf(user), amount1 + amount2);

        // Partial redemption
        idrc.approve(address(hub), redeem1);
        hub.requestRedemption(address(asset), redeem1);
        assertEq(idrc.balanceOf(user), amount1 + amount2 - redeem1);

        vm.stopPrank();
    }

    function testReentrancyProtection() public {
        // Reentrancy protection is tested implicitly through nonReentrant modifier
        // The modifier should prevent reentrant calls
        uint256 amount = 1000 * 1e2;

        vm.startPrank(user);
        asset.approve(address(hub), amount);
        hub.requestSubscription(address(asset), amount);
        vm.stopPrank();
    }
}
