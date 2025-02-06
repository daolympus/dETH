// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {IFLETHStrategy} from "@fleth-interfaces/IFLETHStrategy.sol";
import {IWETH} from "@fleth-interfaces/IWETH.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFLETH is IERC20 {
    error UnableToSendETH();
    error CurrentStrategyHasBalance();
    error AmountExceedsETHBalance();

    function weth() external view returns (IWETH);

    function rebalanceThreshold() external view returns (uint256);

    function strategy() external view returns (IFLETHStrategy);

    function yieldReceiver() external view returns (address);

    function deposit(uint256 wethAmount) external payable;

    /**
     * @notice Rebalances ETH balance above the threshold into LSTs
     */
    function rebalance() external;

    function withdraw(uint256 amount) external;

    function harvest() external;

    function yieldAccumulated() external view returns (uint256);

    function underlyingETHBalance() external view returns (uint256);

    function owner() external view returns (address);

    function setRebalanceThreshold(uint256 rebalanceThreshold_) external;

    function setYieldReceiver(address yieldReceiver_) external;

    function changeStrategy(IFLETHStrategy strategy_) external;

    function emergencyRescue(uint256 amount) external;
}
