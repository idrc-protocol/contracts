// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRCv2} from "../src/IDRCv2.sol";

contract UpgradeScript is Script {
    address proxyAddress = 0xD3723bD07766d4993FBc936bEA1895227B556ea3;
    address hubProxy = 0xf2CCA756D7dE98d54ed00697EA8Cf50D71ea0Dd1;
    address rewardProxy = 0xA77C8059B011Ad0DB426623d1c1B985E53fdb7db;

    function run() external returns (address) {
        vm.createSelectFork(vm.envString("RPC_URL"));
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);

        // Deploy implementation baru
        IDRCv2 newImplementation = new IDRCv2();

        // Call upgradeTo via proxy
        IDRC proxy = IDRC(proxyAddress);
        proxy.upgradeToAndCall(
            address(newImplementation), abi.encodeWithSelector(IDRCv2.initializeV2.selector, hubProxy, rewardProxy)
        );

        vm.stopBroadcast();

        console.log("Upgraded IDRC proxy at", proxyAddress, "to new implementation at", address(newImplementation));

        return proxyAddress;
    }
}
