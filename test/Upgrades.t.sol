// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../script/Upgrades.s.sol";

contract UpgradeTest is Test {
    UpgradeScript upgradeScript;

    function setUp() public {
        upgradeScript = new UpgradeScript();
    }

    function testUpgrade() public {
        address upgradedProxy = upgradeScript.run();
    }
}
