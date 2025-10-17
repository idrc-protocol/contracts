// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IDRC} from "../src/IDRC.sol";
import {Reward} from "../src/RewardDistributor.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20Errors} from "@openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";

contract IDRCUnitTest is Test {
    IDRC internal idrcImpl;
    IDRC internal idrc;

    Reward internal rewardImpl;
    Reward internal reward;

    address internal owner = makeAddr("OWNER");
    address internal hub = makeAddr("HUB");
    address internal user = makeAddr("USER");
    address internal user2 = makeAddr("USER2");
    address internal other = makeAddr("OTHER");

    event MintedByHub(address indexed to, uint256 amount);
    event BurnedByHub(address indexed from, uint256 amount);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy implementation
        idrcImpl = new IDRC();
        rewardImpl = new Reward();

        // Compute addresses for circular dependency
        uint256 nonce = vm.getNonce(owner);
        address predictedRewardProxy = vm.computeCreateAddress(owner, nonce);
        address predictedIdrcProxy = vm.computeCreateAddress(owner, nonce + 1);

        // Deploy reward proxy first
        bytes memory rewardInitData = abi.encodeWithSelector(Reward.initialize.selector, hub, predictedIdrcProxy, owner);
        ERC1967Proxy rewardProxy = new ERC1967Proxy(address(rewardImpl), rewardInitData);
        reward = Reward(address(rewardProxy));

        // Deploy IDRC proxy
        bytes memory initData = abi.encodeWithSelector(IDRC.initialize.selector, hub, address(reward));
        ERC1967Proxy proxy = new ERC1967Proxy(address(idrcImpl), initData);
        idrc = IDRC(address(proxy));

        vm.stopPrank();
    }

    // ====== Initialization Tests ======

    function testInitializeCorrectly() public view {
        assertEq(idrc.name(), "IDRC");
        assertEq(idrc.symbol(), "IDRC");
        assertEq(idrc.hub(), hub);
        assertEq(idrc.owner(), owner);
        assertEq(idrc.totalSupply(), 0);
    }

    function testCannotInitializeTwice() public {
        vm.expectRevert();
        idrc.initialize(hub, address(reward));
    }

    function testInitializeWithZeroAddressHub() public {
        IDRC newIdrcImpl = new IDRC();
        bytes memory initData = abi.encodeWithSelector(IDRC.initialize.selector, address(0), address(reward));
        ERC1967Proxy proxy = new ERC1967Proxy(address(newIdrcImpl), initData);
        IDRC newIdrc = IDRC(address(proxy));

        assertEq(newIdrc.hub(), address(0));
    }

    // ====== MintByHub Tests ======

    function testMintByHubSuccess() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        vm.expectEmit(true, true, false, true);
        emit MintedByHub(user, amount);
        idrc.mintByHub(user, amount);

        assertEq(idrc.balanceOf(user), amount);
        assertEq(idrc.totalSupply(), amount);
    }

    function testMintByHubMultipleTimes() public {
        uint256 amount1 = 1000 * 1e18;
        uint256 amount2 = 500 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, amount1);
        idrc.mintByHub(user, amount2);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), amount1 + amount2);
        assertEq(idrc.totalSupply(), amount1 + amount2);
    }

    function testMintByHubMultipleUsers() public {
        uint256 amount1 = 1000 * 1e18;
        uint256 amount2 = 2000 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, amount1);
        idrc.mintByHub(user2, amount2);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), amount1);
        assertEq(idrc.balanceOf(user2), amount2);
        assertEq(idrc.totalSupply(), amount1 + amount2);
    }

    function testMintByHubRevertsForNonHub() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(other);
        vm.expectRevert(IDRC.Unauthorized.selector);
        idrc.mintByHub(user, amount);
    }

    function testMintByHubRevertsForOwner() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(owner);
        vm.expectRevert(IDRC.Unauthorized.selector);
        idrc.mintByHub(user, amount);
    }

    function testMintByHubRevertsForZeroAddress() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        vm.expectRevert(IDRC.InvalidAddressOrAmount.selector);
        idrc.mintByHub(address(0), amount);
    }

    function testMintByHubRevertsForZeroAmount() public {
        vm.prank(hub);
        vm.expectRevert(IDRC.InvalidAddressOrAmount.selector);
        idrc.mintByHub(user, 0);
    }

    function testMintByHubEmitsEvents() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user, amount);
        vm.expectEmit(true, false, false, true);
        emit MintedByHub(user, amount);
        idrc.mintByHub(user, amount);
    }

    // ====== BurnByHub Tests ======

    function testBurnByHubSuccess() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 burnAmount = 400 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, mintAmount);

        vm.expectEmit(true, true, false, true);
        emit BurnedByHub(user, burnAmount);
        idrc.burnByHub(user, burnAmount);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), mintAmount - burnAmount);
        assertEq(idrc.totalSupply(), mintAmount - burnAmount);
    }

    function testBurnByHubAllBalance() public {
        uint256 amount = 1000 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, amount);
        idrc.burnByHub(user, amount);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), 0);
        assertEq(idrc.totalSupply(), 0);
    }

    function testBurnByHubMultipleTimes() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 burn1 = 300 * 1e18;
        uint256 burn2 = 200 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, mintAmount);
        idrc.burnByHub(user, burn1);
        idrc.burnByHub(user, burn2);
        vm.stopPrank();

        assertEq(idrc.balanceOf(user), mintAmount - burn1 - burn2);
        assertEq(idrc.totalSupply(), mintAmount - burn1 - burn2);
    }

    function testBurnByHubRevertsForNonHub() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        vm.prank(other);
        vm.expectRevert(IDRC.Unauthorized.selector);
        idrc.burnByHub(user, amount);
    }

    function testBurnByHubRevertsForOwner() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        vm.prank(owner);
        vm.expectRevert(IDRC.Unauthorized.selector);
        idrc.burnByHub(user, amount);
    }

    function testBurnByHubRevertsForZeroAddress() public {
        vm.prank(hub);
        vm.expectRevert(IDRC.InvalidAddressOrAmount.selector);
        idrc.burnByHub(address(0), 100);
    }

    function testBurnByHubRevertsForZeroAmount() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        vm.prank(hub);
        vm.expectRevert(IDRC.InvalidAddressOrAmount.selector);
        idrc.burnByHub(user, 0);
    }

    function testBurnByHubRevertsForInsufficientBalance() public {
        uint256 mintAmount = 500 * 1e18;
        uint256 burnAmount = 1000 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, mintAmount);
        vm.expectRevert();
        idrc.burnByHub(user, burnAmount);
        vm.stopPrank();
    }

    function testBurnByHubEmitsEvents() public {
        uint256 amount = 1000 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, amount);

        vm.expectEmit(true, true, false, true);
        emit Transfer(user, address(0), amount);
        vm.expectEmit(true, false, false, true);
        emit BurnedByHub(user, amount);
        idrc.burnByHub(user, amount);
        vm.stopPrank();
    }

    // ====== TVL Tests ======

    function testTvlInitiallyZero() public view {
        assertEq(idrc.tvl(), 0);
    }

    function testTvlAfterMint() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        assertEq(idrc.tvl(), amount);
    }

    function testTvlAfterMultipleMints() public {
        uint256 amount1 = 1000 * 1e18;
        uint256 amount2 = 2000 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, amount1);
        idrc.mintByHub(user2, amount2);
        vm.stopPrank();

        assertEq(idrc.tvl(), amount1 + amount2);
    }

    function testTvlAfterBurn() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 burnAmount = 300 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, mintAmount);
        idrc.burnByHub(user, burnAmount);
        vm.stopPrank();

        assertEq(idrc.tvl(), mintAmount - burnAmount);
    }

    function testTvlEqualsTotalSupply() public {
        uint256 amount = 5000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        assertEq(idrc.tvl(), idrc.totalSupply());
    }

    // ====== ERC20 Transfer Tests ======

    function testTransferSuccess() public {
        uint256 amount = 1000 * 1e18;
        uint256 transferAmount = 300 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, user2, transferAmount);
        bool success = idrc.transfer(user2, transferAmount);

        assertTrue(success);
        assertEq(idrc.balanceOf(user), amount - transferAmount);
        assertEq(idrc.balanceOf(user2), transferAmount);
    }

    function testTransferAll() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        vm.prank(user);
        idrc.transfer(user2, amount);

        assertEq(idrc.balanceOf(user), 0);
        assertEq(idrc.balanceOf(user2), amount);
    }

    function testTransferRevertsForInsufficientBalance() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        vm.prank(user);
        vm.expectRevert();
        idrc.transfer(user2, amount + 1);
    }

    function testTransferToZeroAddress() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        vm.prank(user);
        vm.expectRevert();
        idrc.transfer(address(0), 100);
    }

    // ====== ERC20 Approval Tests ======

    function testApproveSuccess() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(user);
        vm.expectEmit(true, true, false, true);
        emit Approval(user, user2, amount);
        bool success = idrc.approve(user2, amount);

        assertTrue(success);
        assertEq(idrc.allowance(user, user2), amount);
    }

    function testApproveZeroAmount() public {
        vm.prank(user);
        bool success = idrc.approve(user2, 0);

        assertTrue(success);
        assertEq(idrc.allowance(user, user2), 0);
    }

    function testApproveOverwritesPreviousAllowance() public {
        uint256 amount1 = 1000 * 1e18;
        uint256 amount2 = 500 * 1e18;

        vm.startPrank(user);
        idrc.approve(user2, amount1);
        idrc.approve(user2, amount2);
        vm.stopPrank();

        assertEq(idrc.allowance(user, user2), amount2);
    }

    // ====== ERC20 TransferFrom Tests ======

    function testTransferFromSuccess() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 transferAmount = 300 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, mintAmount);

        vm.prank(user);
        idrc.approve(other, transferAmount);

        vm.prank(other);
        vm.expectEmit(true, true, false, true);
        emit Transfer(user, user2, transferAmount);
        bool success = idrc.transferFrom(user, user2, transferAmount);

        assertTrue(success);
        assertEq(idrc.balanceOf(user), mintAmount - transferAmount);
        assertEq(idrc.balanceOf(user2), transferAmount);
        assertEq(idrc.allowance(user, other), 0);
    }

    function testTransferFromWithInfiniteApproval() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 transferAmount = 300 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, mintAmount);

        vm.prank(user);
        idrc.approve(other, type(uint256).max);

        vm.prank(other);
        idrc.transferFrom(user, user2, transferAmount);

        assertEq(idrc.balanceOf(user2), transferAmount);
        assertEq(idrc.allowance(user, other), type(uint256).max);
    }

    function testTransferFromRevertsForInsufficientAllowance() public {
        uint256 mintAmount = 1000 * 1e18;
        uint256 approveAmount = 200 * 1e18;
        uint256 transferAmount = 300 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, mintAmount);

        vm.prank(user);
        idrc.approve(other, approveAmount);

        vm.prank(other);
        vm.expectRevert();
        idrc.transferFrom(user, user2, transferAmount);
    }

    function testTransferFromRevertsForInsufficientBalance() public {
        uint256 mintAmount = 500 * 1e18;
        uint256 approveAmount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, mintAmount);

        vm.prank(user);
        idrc.approve(other, approveAmount);

        vm.prank(other);
        vm.expectRevert();
        idrc.transferFrom(user, user2, approveAmount);
    }

    // ====== Ownership Tests ======

    function testOwnerIsSetCorrectly() public view {
        assertEq(idrc.owner(), owner);
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("NEW_OWNER");

        vm.prank(owner);
        idrc.transferOwnership(newOwner);

        assertEq(idrc.owner(), newOwner);
    }

    function testTransferOwnershipRevertsForNonOwner() public {
        address newOwner = makeAddr("NEW_OWNER");

        vm.prank(user);
        vm.expectRevert();
        idrc.transferOwnership(newOwner);
    }

    // ====== Upgrade Tests ======

    function testUpgradeByOwner() public {
        IDRC newImplementation = new IDRC();

        vm.prank(owner);
        idrc.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradeRevertsForNonOwner() public {
        IDRC newImplementation = new IDRC();

        vm.prank(user);
        vm.expectRevert();
        idrc.upgradeToAndCall(address(newImplementation), "");
    }

    function testUpgradePreservesState() public {
        uint256 amount = 1000 * 1e18;

        vm.prank(hub);
        idrc.mintByHub(user, amount);

        IDRC newImplementation = new IDRC();

        vm.prank(owner);
        idrc.upgradeToAndCall(address(newImplementation), "");

        assertEq(idrc.balanceOf(user), amount);
        assertEq(idrc.totalSupply(), amount);
        assertEq(idrc.hub(), hub);
    }

    // ====== Edge Cases ======

    function testMintAndBurnCycle() public {
        uint256 amount = 1000 * 1e18;

        vm.startPrank(hub);

        // Mint
        idrc.mintByHub(user, amount);
        assertEq(idrc.balanceOf(user), amount);

        // Burn
        idrc.burnByHub(user, amount);
        assertEq(idrc.balanceOf(user), 0);

        // Mint again
        idrc.mintByHub(user, amount);
        assertEq(idrc.balanceOf(user), amount);

        vm.stopPrank();
    }

    function testMultipleUsersComplexScenario() public {
        uint256 amount1 = 1000 * 1e18;
        uint256 amount2 = 2000 * 1e18;

        vm.startPrank(hub);
        idrc.mintByHub(user, amount1);
        idrc.mintByHub(user2, amount2);
        vm.stopPrank();

        // User transfers to user2
        vm.prank(user);
        idrc.transfer(user2, 200 * 1e18);

        assertEq(idrc.balanceOf(user), 800 * 1e18);
        assertEq(idrc.balanceOf(user2), 2200 * 1e18);

        // Burn from user2
        vm.prank(hub);
        idrc.burnByHub(user2, 500 * 1e18);

        assertEq(idrc.balanceOf(user2), 1700 * 1e18);
        assertEq(idrc.totalSupply(), 2500 * 1e18);
    }

    function testDecimalsIsStandard() public view {
        assertEq(idrc.decimals(), 18);
    }

    // ====== View Function Tests ======

    function testBalanceOfZeroForNewAddress() public {
        address randomAddress = makeAddr("RANDOM");
        assertEq(idrc.balanceOf(randomAddress), 0);
    }

    function testAllowanceZeroByDefault() public view {
        assertEq(idrc.allowance(user, user2), 0);
    }
}
