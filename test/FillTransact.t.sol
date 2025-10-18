// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../script/FillTransact.s.sol";

contract FillTransactTest is Test {
    FillTransact fillTransactScript;

    function setUp() public {
        fillTransactScript = new FillTransact();
    }

    function testFillTransact() public {
        fillTransactScript.run();
    }
}