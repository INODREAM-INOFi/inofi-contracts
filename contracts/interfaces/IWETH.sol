// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address,uint) external returns (bool);
    function withdraw(uint) external;
}