// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../script/Deploy.s.sol";

contract DeployTest is Test {
    Deploy deployScript;

    function setUp() public {
        deployScript = new Deploy();
    }

    function testDeployment() public {
        deployScript.run();
    }
}
