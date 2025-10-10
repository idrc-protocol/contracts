// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Hub} from "../src/Hub.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRX} from "../src/IDRX.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        uint256 currentNonce = vm.getNonce(deployer);

        address predictedIdrcImpl = vm.computeCreateAddress(deployer, currentNonce);
        address predictedHubImpl = vm.computeCreateAddress(deployer, currentNonce + 1);
        address predictedIdrcProxy = vm.computeCreateAddress(deployer, currentNonce + 2);
        address predictedHubProxy = vm.computeCreateAddress(deployer, currentNonce + 3);

        vm.startBroadcast(deployerKey);

        IDRX idrx = new IDRX("IDRX Token", "IDRX", 2);
        console.log("Deployed IDRX token at", address(idrx));

        IDRC idrcImpl = new IDRC();
        console.log("Deployed IDRC implementation at", address(idrcImpl));

        Hub hubImpl = new Hub();
        console.log("Deployed Hub implementation at", address(hubImpl));

        require(address(idrcImpl) == predictedIdrcImpl, "IDRC impl mismatch");
        require(address(hubImpl) == predictedHubImpl, "Hub impl mismatch");

        bytes memory idrcInitData = abi.encodeWithSelector(IDRC.initialize.selector, predictedHubProxy);
        ERC1967Proxy idrcProxy = new ERC1967Proxy(address(idrcImpl), idrcInitData);
        console.log("Deployed IDRC proxy at", address(idrcProxy));

        ERC1967Proxy hubProxy = new ERC1967Proxy(
            address(hubImpl),
            abi.encodeWithSelector(Hub.initialize.selector, address(idrx), predictedIdrcProxy, deployer)
        );
        console.log("Deployed Hub proxy at", address(hubProxy));

        Hub hub = Hub(address(hubProxy));
        IDRC idrc = IDRC(address(idrcProxy));

        require(address(idrcProxy) == predictedIdrcProxy, "IDRC proxy mismatch");
        require(address(hubProxy) == predictedHubProxy, "Hub proxy mismatch");

        vm.stopBroadcast();

        console.log("Hub implementation", address(hubImpl));
        console.log("Hub proxy", address(hub));
        console.log("IDRC implementation", address(idrcImpl));
        console.log("IDRC proxy", address(idrc));
    }
}
