// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Hub} from "../src/Hub.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRX} from "../src/IDRX.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract HubTest is Test {
    IDRX internal asset;
    Hub internal hubImpl;
    IDRC internal idrcImpl;
    Hub internal hub;
    IDRC internal idrc;

    address internal owner = makeAddr("OWNER");
    address internal admin = makeAddr("ADMIN");
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
        address predictedIdrcProxy = vm.computeCreateAddress(owner, nonce + 2);
        address predictedHubProxy = vm.computeCreateAddress(owner, nonce + 3);

        idrcImpl = new IDRC();
        hubImpl = new Hub();

        assertEq(address(idrcImpl), predictedIdrcImpl);
        assertEq(address(hubImpl), predictedHubImpl);

        bytes memory idrcInitData = abi.encodeWithSelector(IDRC.initialize.selector, predictedHubProxy);
        ERC1967Proxy idrcProxy = new ERC1967Proxy(address(idrcImpl), idrcInitData);
        ERC1967Proxy hubProxy = new ERC1967Proxy(
            address(hubImpl), abi.encodeWithSelector(Hub.initialize.selector, address(asset), predictedIdrcProxy, admin)
        );

        assertEq(address(idrcProxy), predictedIdrcProxy);
        assertEq(address(hubProxy), predictedHubProxy);

        hub = Hub(address(hubProxy));
        idrc = IDRC(address(idrcProxy));

        vm.stopPrank();

        asset.mint(user, USER_BALANCE);

        vm.prank(admin);
        hub.setPrice(PRICE);
    }

    function testInitializeGrantsRoles() public view {
        assertTrue(hub.hasRole(hub.ADMIN_ROLE(), admin));
        assertTrue(hub.hasRole(hub.DEFAULT_ADMIN_ROLE(), owner));
    }

    function testSetPriceByAdminUpdatesPrice() public {
        uint256 newPrice = 32000 * 1e2;

        vm.prank(admin);
        hub.setPrice(newPrice);

        assertEq(hub.getPrice(), newPrice);
    }

    function testSetPriceRevertsForNonAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, hub.ADMIN_ROLE())
        );
        vm.prank(user);
        hub.setPrice(200);
    }

    function testRequestSubscriptionMintsShares() public {
        uint256 amount = 32000 * 1e2;
        uint256 expectedShares = (amount / PRICE) * hub.PRECISION();

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

    function testRequestRedemptionBurnsSharesAndTransfersAsset() public {
        uint256 amount = 32000 * 1e2;
        uint256 shares = (amount / PRICE) * hub.PRECISION();

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

    function testConvertToSharesReturnsScaledAmount() public view {
        uint256 amount = 32000 * 1e2;
        uint256 expectedShares = (amount / PRICE) * hub.PRECISION();

        assertEq(hub.convertToShares(amount), expectedShares);
    }

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
