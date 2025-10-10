// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IIDRC is IERC20 {
    // Events
    event MintedByHub(address indexed to, uint256 amount);
    event BurnedByHub(address indexed from, uint256 amount);

    // Errors
    error Unauthorized();
    error InvalidAddressOrAmount();

    // Functions
    function hub() external view returns (address);

    function initialize(address _asset, address _hub) external;

    function mintByHub(address to, uint256 amount) external;

    function burnByHub(address from, uint256 amount) external;
}
