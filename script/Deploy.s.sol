// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {Hub} from "../src/Hub.sol";
import {Reward} from "../src/RewardDistributor.sol";
import {IDRC} from "../src/IDRC.sol";
import {IDRX} from "../src/IDRX.sol";
import {ERC1967Proxy} from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        address predictedIdrcImpl;
        address predictedHubImpl;
        address predictedRewardImpl;
        address predictedRewardProxy;
        address predictedIdrcProxy;
        address predictedHubProxy;

        {
            uint256 currentNonce = vm.getNonce(deployer);
            // currentNonce will be used by IDRX deployment
            predictedIdrcImpl = vm.computeCreateAddress(deployer, currentNonce + 1);
            predictedHubImpl = vm.computeCreateAddress(deployer, currentNonce + 2);
            predictedRewardImpl = vm.computeCreateAddress(deployer, currentNonce + 3);
            predictedRewardProxy = vm.computeCreateAddress(deployer, currentNonce + 4);
            predictedIdrcProxy = vm.computeCreateAddress(deployer, currentNonce + 5);
            predictedHubProxy = vm.computeCreateAddress(deployer, currentNonce + 6);
        }

        vm.startBroadcast(deployerKey);

        address idrxAddr;
        {
            IDRX idrx = new IDRX("IDRX Token", "IDRX", 2);
            idrxAddr = address(idrx);
            console.log("Deployed IDRX token at", idrxAddr);
        }

        address idrcImplAddr;
        address hubImplAddr;
        address rewardImplAddr;

        {
            IDRC idrcImpl = new IDRC();
            idrcImplAddr = address(idrcImpl);
            console.log("Deployed IDRC implementation at", idrcImplAddr);

            Hub hubImpl = new Hub();
            hubImplAddr = address(hubImpl);
            console.log("Deployed Hub implementation at", hubImplAddr);

            Reward rewardImpl = new Reward();
            rewardImplAddr = address(rewardImpl);
            console.log("Deployed Reward implementation at", rewardImplAddr);

            require(idrcImplAddr == predictedIdrcImpl, "IDRC impl mismatch");
            require(hubImplAddr == predictedHubImpl, "Hub impl mismatch");
            require(rewardImplAddr == predictedRewardImpl, "Reward impl mismatch");
        }

        address rewardProxyAddr;
        address idrcProxyAddr;
        address hubProxyAddr;

        {
            address adminManager = vm.envAddress("ADMIN_MANAGER");
            bytes memory initData =
                abi.encodeWithSelector(Reward.initialize.selector, predictedHubProxy, predictedIdrcProxy, adminManager);
            ERC1967Proxy rewardProxy = new ERC1967Proxy(rewardImplAddr, initData);
            rewardProxyAddr = address(rewardProxy);
            console.log("Deployed Reward proxy at", rewardProxyAddr);
        }

        {
            bytes memory initData =
                abi.encodeWithSelector(IDRC.initialize.selector, predictedHubProxy, predictedRewardProxy);
            ERC1967Proxy idrcProxy = new ERC1967Proxy(idrcImplAddr, initData);
            idrcProxyAddr = address(idrcProxy);
            console.log("Deployed IDRC proxy at", idrcProxyAddr);
        }

        {
            address adminManager = vm.envAddress("ADMIN_MANAGER");
            bytes memory initData =
                abi.encodeWithSelector(Hub.initialize.selector, idrxAddr, predictedIdrcProxy, adminManager);
            ERC1967Proxy hubProxy = new ERC1967Proxy(hubImplAddr, initData);
            hubProxyAddr = address(hubProxy);
            console.log("Deployed Hub proxy at", hubProxyAddr);
        }

        require(rewardProxyAddr == predictedRewardProxy, "Reward proxy mismatch");
        require(idrcProxyAddr == predictedIdrcProxy, "IDRC proxy mismatch");
        require(hubProxyAddr == predictedHubProxy, "Hub proxy mismatch");

        vm.stopBroadcast();

        console.log("Hub implementation", hubImplAddr);
        console.log("Hub proxy", hubProxyAddr);
        console.log("IDRC implementation", idrcImplAddr);
        console.log("IDRC proxy", idrcProxyAddr);
        console.log("Reward implementation", rewardImplAddr);
        console.log("Reward proxy", rewardProxyAddr);
    }
}
