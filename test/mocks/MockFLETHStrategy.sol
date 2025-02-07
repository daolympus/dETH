// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IFLETHStrategy} from "@fleth-interfaces/IFLETHStrategy.sol";

contract MockFLETHStrategy is IFLETHStrategy {
    bool public isUnwinding;
    address public owner;

    constructor() {
        owner = msg.sender;
        isUnwinding = false;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    receive() external payable {
    }

    function convertETHToLST() external payable {
        require(!isUnwinding, "Strategy is unwinding");
    }

    function withdrawETH(uint256 amount, address receiver) external {
        require(amount <= address(this).balance, "Insufficient balance");
        (bool success, ) = receiver.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function balanceInETH() external view returns (uint256) {
        return address(this).balance;
    }

    function setIsUnwinding(bool isUnwinding_) external onlyOwner {
        isUnwinding = isUnwinding_;
    }

    function unwindToETH(uint256 ethAmount) external onlyOwner {
        // Mock implementation - in reality would convert LST back to ETH
        require(ethAmount <= address(this).balance, "Insufficient balance");
    }

    function emergencyRescue() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool success, ) = owner.call{value: balance}("");
        require(success, "ETH transfer failed");
    }
}
