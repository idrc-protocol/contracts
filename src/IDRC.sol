// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {IRewardDistributor} from "./interfaces/IRewardDistributor.sol";

contract IDRC is Initializable, ERC20Upgradeable, OwnableUpgradeable, UUPSUpgradeable {
    address public hub;
    IRewardDistributor public rewardDistributor;

    event MintedByHub(address indexed to, uint256 amount);
    event BurnedByHub(address indexed from, uint256 amount);

    error Unauthorized();
    error InvalidAddressOrAmount();

    constructor() {
        _disableInitializers();
    }

    function initialize(address _hub, address _rewardDistributor) public initializer {
        __ERC20_init("IDRC", "IDRC");
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();

        hub = _hub;
        rewardDistributor = IRewardDistributor(_rewardDistributor);
    }

    function mintByHub(address to, uint256 amount) external onlyHub {
        if (to == address(0) || amount == 0) revert InvalidAddressOrAmount();

        _mint(to, amount);
        emit MintedByHub(to, amount);
    }

    function burnByHub(address from, uint256 amount) external onlyHub {
        if (from == address(0) || amount == 0) revert InvalidAddressOrAmount();

        _burn(from, amount);
        emit BurnedByHub(from, amount);
    }

    function tvl() external view returns (uint256) {
        return totalSupply();
    }

    function _update(address from, address to, uint256 amount) internal override {
        // Update rewards BEFORE balance changes
        if (from != address(0)) {
            rewardDistributor.updateReward(from);
        }
        if (to != address(0)) {
            rewardDistributor.updateReward(to);
        }

        super._update(from, to, amount);
    }

    modifier onlyHub() {
        if (msg.sender != hub) revert Unauthorized();
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
