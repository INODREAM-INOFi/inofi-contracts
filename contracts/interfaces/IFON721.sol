// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFON721 {
    function mint(address,uint) external;
    function totalSupply() external view returns (uint);
    function nextTokenId() external view returns (uint);
    function mintExact(address,uint) external;
    function burn(uint) external;
    function addNextTokenId(uint) external;
    function setCanTransfer(uint,address,address) external;
    function setIsShared(uint) external;
}