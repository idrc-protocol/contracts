// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IHub {
    // Constants
    function ADMIN_ROLE() external view returns (bytes32);
    function PRECISION() external view returns (uint256);

    // Events
    event RequestedSubscription(address indexed user, uint256 amount, uint256 shares);
    event RequestedRedemption(address indexed user, uint256 shares, uint256 amount);
    event PriceUpdated(uint256 indexed priceId, uint256 price);

    // Errors
    error AssetNotSupported();
    error InvalidAmount();
    error InsufficientBalance();

    function tokenAccepted() external view returns (address);
    function tvl() external view returns (uint256);

    // Functions
    function initialize(address _asset, address _idrc, address _adminRole) external;

    function requestSubscription(address tokenIn, uint256 amount) external;

    function requestRedemption(address tokenOut, uint256 shares) external;

    function depositAsset(address tokenIn, uint256 amount) external;

    function withdrawAsset(address tokenOut, uint256 amount) external;
}
