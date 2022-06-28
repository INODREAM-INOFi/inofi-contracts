// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./libraries/ERC20.sol";
import "./libraries/SafeMath.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/IFON.sol";

contract Stake is ERC20 {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    IERC20 public fon;

    event Staked(
        address indexed account,
        uint amount,
        uint shares
    );
    event Unstaked(
        address indexed account,
        uint amount,
        uint shares
    );

    constructor (
        address newFON,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {
        fon = IERC20(newFON);
    }

    function stake(uint amount) public {
        uint totalBalance = fon.balanceOf(address(this));
        uint shares = totalBalance.mul(totalSupply()) == 0
        ? amount
        : amount
        .mul(totalSupply())
        .div(totalBalance);

        _mint(msg.sender, shares);
        fon.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, shares);
    }

    function unstake(uint shares) public {
        uint amount = shares
        .mul(fon.balanceOf(address(this)))
        .div(totalSupply());

        _burn(msg.sender, shares);
        fon.safeTransfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, shares);
    }
}