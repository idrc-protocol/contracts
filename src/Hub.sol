// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20Upgradeable} from "@openzeppelin-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

import {HubStorage} from "./libraries/HubStorage.sol";
import {IIDRC} from "./interfaces/IIDRC.sol";

contract Hub is Initializable, OwnableUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public constant PRECISION = 1e18;

    event RequestedSubscription(address indexed user, uint256 amount, uint256 shares);
    event RequestedRedemption(address indexed user, uint256 shares, uint256 amount);
    event PriceUpdated(uint256 indexed priceId, uint256 price);

    error AssetNotSupported();
    error InvalidAmount();
    error InsufficientBalance();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _asset, address _idrc, address _adminRole) external initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, _adminRole);

        HubStorage.MainStorage storage $ = HubStorage._getMainStorage();
        $.assets[_asset] = true;
        $.idrc = IIDRC(_idrc);
    }

    function requestSubscription(address tokenIn, uint256 amount) external {
        if (amount == 0) revert InvalidAmount();
        HubStorage.MainStorage storage $ = HubStorage._getMainStorage();
        if (!$.assets[tokenIn]) revert AssetNotSupported();

        IERC20(tokenIn).transferFrom(msg.sender, address(this), amount);

        uint256 shares = (amount / $.prices[$.currentPriceId]) * PRECISION;
        $.idrc.mintByHub(msg.sender, shares);

        emit RequestedSubscription(msg.sender, amount, shares);
    }

    function requestRedemption(address tokenOut, uint256 shares) external {
        if (shares == 0) revert InvalidAmount();
        HubStorage.MainStorage storage $ = HubStorage._getMainStorage();
        if ($.idrc.balanceOf(msg.sender) < shares) revert InsufficientBalance();

        $.idrc.transferFrom(msg.sender, address(this), shares);
        uint256 amount = (shares * $.prices[$.currentPriceId]) / PRECISION;

        $.idrc.burnByHub(address(this), shares);
        IERC20(tokenOut).transfer(msg.sender, amount);

        emit RequestedRedemption(msg.sender, shares, amount);
    }

    function convertToShares(uint256 amount) external view returns (uint256) {
        HubStorage.MainStorage storage $ = HubStorage._getMainStorage();
        return (amount / $.prices[$.currentPriceId]) * PRECISION;
    }

    function getPrice() external view returns (uint256) {
        HubStorage.MainStorage storage $ = HubStorage._getMainStorage();
        return $.prices[$.currentPriceId];
    }

    function setPrice(uint256 price) external onlyRole(ADMIN_ROLE) {
        HubStorage.MainStorage storage $ = HubStorage._getMainStorage();
        uint256 priceId = ++$.currentPriceId;
        $.prices[priceId] = price;

        emit PriceUpdated(priceId, price);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
