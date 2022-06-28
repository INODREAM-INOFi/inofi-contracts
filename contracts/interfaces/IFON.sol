// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IFON {
    function ownPercentage() external view returns (uint);
    function exitPercentage() external view returns (uint);
    function stakeFeePercentage() external view returns (uint);
    function auctionFeePercentage() external view returns (uint);
    function auctionMinterFeePercentage() external view returns (uint);
    function fon721Fee() external view returns (uint);
    function admin() external view returns (address);
    function receiver() external view returns (address);
    function fon721maker() external view returns (address);
    function stake() external view returns (address);
    function distributor() external view returns (address);
    function fon721() external view returns (address);
    function auction() external view returns (address);
    function ticket() external view returns (address);
    function minters(address) external view returns (bool);
    function auctionMinters(address) external view returns (bool);
    function allowed721(address) external view returns (bool);
    function mint(address,uint) external;
}