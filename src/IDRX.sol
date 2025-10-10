// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract IDRX is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function mint(address to, uint256 amount) external returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external returns (bool) {
        _burn(from, amount);
        return true;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
