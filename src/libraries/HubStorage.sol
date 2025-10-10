// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IIDRC} from "../interfaces/IIDRC.sol";

library HubStorage {
    struct MainStorage {
        IIDRC idrc;
        mapping(address => bool) assets;
        mapping(uint256 => uint256) prices;
        uint256 currentPriceId;
    }

    // keccak256(abi.encode(uint256(keccak256("idrc.storage.main")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant MAIN_STORAGE_LOCATION = 0x410db8097748b2adc18a3d9c7c820c57f308a38a62322863dc75caf59c7b4000;

    function _getMainStorage() internal pure returns (MainStorage storage $) {
        assembly {
            $.slot := MAIN_STORAGE_LOCATION
        }
    }
}
