// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/ERC20.sol";

contract FON20 is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint initialSupply
    ) ERC20(_name, _symbol) {
        _mint(msg.sender, initialSupply);
    }
}