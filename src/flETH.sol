// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import {Ownable} from "@solady/auth/Ownable.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IFLETH} from "@fleth-interfaces/IFLETH.sol";
import {IFLETHStrategy} from "@fleth-interfaces/IFLETHStrategy.sol";
import {IWETH} from "@fleth-interfaces/IWETH.sol";

/**
 * The flETH token.
 *
 *    ______/\\\\\__/\\\\\\_____/\\\\\\\\\\\\\\\__/\\\\\\\\\\\\\\\___/\\\________/\\\__________
 *    _____/\\\///__\////\\\____\/\\\///////////__\///////\\\/////___\/\\\_______\/\\\_________
 *    _____/\\\_________\/\\\____\/\\\___________________\/\\\________\/\\\_______\/\\\________
 *    ___/\\\\\\\\\______\/\\\____\/\\\\\\\\\\\___________\/\\\________\/\\\\\\\\\\\\\\\_______
 *    ___\////\\\//_______\/\\\____\/\\\///////____________\/\\\________\/\\\/////////\\\______
 *    _______\/\\\_________\/\\\____\/\\\___________________\/\\\________\/\\\_______\/\\\_____
 *    ________\/\\\_________\/\\\____\/\\\___________________\/\\\________\/\\\_______\/\\\____
 *    _________\/\\\_______/\\\\\\\\\_\/\\\\\\\\\\\\\\\_______\/\\\________\/\\\_______\/\\\___
 *    __________\///_______\/////////__\///////////////________\///_________\///________\///___
 */
contract flETH is IFLETH, ERC20, Ownable {
    error YieldReceiverIsZero();
    error RebalanceThresholdExceedsMax();

    /// The WETH token address
    IWETH public immutable override weth;

    /// A raw ETH balance of say 10% and above that should trigger rebalance into LSTs
    uint256 public override rebalanceThreshold = 0.1 ether; // 10%

    /// The maximum rebalance threshold value
    uint256 internal constant MAX_REBALANCE_THRESHOLD = 1 ether;

    /// The FLETH strategy being used to generate yield
    IFLETHStrategy public override strategy;

    /// The recipient address for any yield generated
    address public yieldReceiver;

    /**
     * Set up our contract dependencies and initialise our flETH ERC20.
     *
     * @param weth_ The WETH token address
     * @param yieldReceiver_ The recipient address of yield
     */
    constructor(IWETH weth_, address yieldReceiver_) ERC20("flETH", "flETH") {
        weth = weth_;

        // Ensure that our yield receiver is a non-zero address and set it
        if (yieldReceiver_ == address(0)) revert YieldReceiverIsZero();
        yieldReceiver = yieldReceiver_;

        // Set our {Ownable} owner address
        _initializeOwner(msg.sender);
    }

    /**
     * Makes a deposit into the contract, taking ETH and/or WETH and returning flETH.
     *
     * @dev This function can receive ETH and will give an amount of flETH equal to ETH + WETH.
     *
     * @param wethAmount The amount of WETH to transfer into the function
     */
    function deposit(uint256 wethAmount) external payable override {
        uint256 ethToDeposit = msg.value;

        // If we have WETH specified, then transfer it into the contract and unwrap into ETH
        if (wethAmount != 0) {
            weth.transferFrom(msg.sender, address(this), wethAmount);
            weth.withdraw(wethAmount);
            ethToDeposit += wethAmount;
        }

        _mintFLETHAndRebalance(msg.sender, ethToDeposit);
    }

    /**
     * Rebalances our position against our strategy.
     */
    function rebalance() public override {
        // If we don't have a strategy, or it is currently unwinding, then we can't process further
        if (address(strategy) == address(0) || strategy.isUnwinding()) return;

        uint256 ethBalance = address(this).balance;
        uint256 ethThreshold = (rebalanceThreshold * totalSupply()) / 1 ether;

        // If the raw ETH balance is more than the threshold, convert the excess to LSTs
        if (ethBalance > ethThreshold) {
            unchecked {
                strategy.convertETHToLST{value: ethBalance - ethThreshold}();
            }
        }
    }

    /**
     * Withdraw ETH by sending in flETH.
     */
    function withdraw(uint256 amount) external override {
        // Burn flETH tokens. This will lower the total supply.
        _burn(msg.sender, amount);

        // Capture the current ETH balance held by the contract
        uint256 currentEthBalance = address(this).balance;

        // Check if we are requesting more ETH than is currently held in the contract
        if (amount > currentEthBalance) {
            // This is only possible when the strategy exists
            if (address(strategy) == address(0)) {
                revert AmountExceedsETHBalance();
            }

            // We are forced to withdraw from the strategy in this case. So withdawing more such
            // that the raw eth balance stays at the threshold, post withdrawal.
            uint256 newTotalSupply = totalSupply();
            uint256 expectedNewEthBalance;
            unchecked {
                expectedNewEthBalance = (rebalanceThreshold * newTotalSupply) / 1 ether;
            }

            // If the new ETH balance should be less than the current ETH balance, then this
            // contract can transfer some ETH directly to the user and only the remaining amount
            // is withdrawn from the strategy.
            if (expectedNewEthBalance <= currentEthBalance) {
                // The amount of raw ETH to directly transfer to the user
                uint256 rawEthToTransfer;
                unchecked {
                    rawEthToTransfer = currentEthBalance - expectedNewEthBalance;
                }

                // Get the remaining amount to withdraw from the strategy
                uint256 strategyETHToWithdraw = amount - rawEthToTransfer;

                // Transfer the raw ETH to the user
                _transferETH(msg.sender, rawEthToTransfer);

                // Transfer the remaining amount from the strategy to the user
                strategy.withdrawETH(strategyETHToWithdraw, msg.sender);
            }
            // If the new ETH balance should be more than the current ETH balance, we need to
            // withdraw the entire amount from the strategy to:
            // 1. Bring the raw ETH balance to the threshold
            // 2. Also to also fulfill the user's request
            else {
                uint256 rawEthRequiredToReachThreshold = expectedNewEthBalance - currentEthBalance;

                // Withdraw ETH to this contract
                strategy.withdrawETH(amount + rawEthRequiredToReachThreshold, address(this));

                // Transferring the requested amount to the user, leaving the raw ETH balance
                // at the threshold.
                _transferETH(msg.sender, amount);
            }
        } else {
            // If the amount to withdraw is less than the current ETH balance, then the contract
            // can directly transfer the ETH to the user.
            _transferETH(msg.sender, amount);
        }
    }

    /**
     * Harvest yield from the strategy and send it to our yield recipient
     */
    function harvest() external override {
        uint256 ethYield = yieldAccumulated();
        uint256 strategyETHBalance = strategy.balanceInETH();

        // If strategy has enough balance, then withdraw from there
        if (strategyETHBalance >= ethYield) {
            strategy.withdrawETH(ethYield, yieldReceiver);
        } else {
            // Otherwise, withdraw the remaining from the raw ETH balance
            uint256 delta = ethYield - strategyETHBalance;
            strategy.withdrawETH(strategyETHBalance, yieldReceiver);
            _transferETH(yieldReceiver, delta);
        }
    }

    /**
     * Helper function to find the amount of yield accumulated.
     *
     * @return uint Yield accumulated
     */
    function yieldAccumulated() public view override returns (uint256) {
        // `totalSupply` represents the total ETH deposited by the users
        return underlyingETHBalance() - totalSupply();
    }

    /**
     * Finds the amount of underlying ETH balance by finding current held amounts, as well as the
     * amount held in the strategy.
     *
     * @return uint The amount of underlying ETH held
     */
    function underlyingETHBalance() public view override returns (uint256) {
        return address(this).balance + strategy.balanceInETH();
    }

    /**
     * The owner of the contract that has {Ownable} permissions.
     */
    function owner() public view override(IFLETH, Ownable) returns (address) {
        return Ownable.owner();
    }

    /**
     * Override to return true to make `_initializeOwner` prevent double-initialization.
     *
     * @return bool Set to `true` to prevent owner being reinitialized.
     */
    function _guardInitializeOwner() internal pure override returns (bool) {
        return true;
    }

    /**
     * Mints the flETH token to the receiver and rebalances our strategy position.
     *
     * @param receiver The recipient of the {flETH} token(s)
     * @param amount The amount of {flETH} to mint
     */
    function _mintFLETHAndRebalance(address receiver, uint256 amount) internal {
        _mint(receiver, amount);
        rebalance();
    }

    /**
     * Transfers ETH to the `receiver`, ensuring that the call is successful.
     *
     * @param receiver The recipient of the ETH
     * @param amount The amount of ETH to transfer
     */
    function _transferETH(address receiver, uint256 amount) internal {
        (bool success,) = receiver.call{value: amount}("");
        if (!success) revert UnableToSendETH();
    }

    /**
     * Allows the `rebalanceThreshold` to be updated by the contract owner.
     *
     * @param rebalanceThreshold_ The new `rebalanceThreshold` value
     */
    function setRebalanceThreshold(uint256 rebalanceThreshold_) external override onlyOwner {
        if (rebalanceThreshold_ > MAX_REBALANCE_THRESHOLD) revert RebalanceThresholdExceedsMax();
        rebalanceThreshold = rebalanceThreshold_;
    }

    /**
     * Allows the `yieldReceiver` to be updated by the contract owner.
     *
     * @param yieldReceiver_ The new `yieldReceiver` address
     */
    function setYieldReceiver(address yieldReceiver_) external override onlyOwner {
        if (yieldReceiver_ == address(0)) revert YieldReceiverIsZero();
        yieldReceiver = yieldReceiver_;
    }

    /**
     * Allows the strategy to be updated. This validates that there is no ETH currently held in
     * the strategy to prevent loss of ETH.
     *
     * @param strategy_ The new {IFLETHStrategy} strategy to be used
     */
    function changeStrategy(IFLETHStrategy strategy_) external override onlyOwner {
        if (address(strategy) != address(0) && strategy.balanceInETH() != 0) {
            revert CurrentStrategyHasBalance();
        }

        strategy = strategy_;
    }

    /**
     * Allows potentially trapped ETH funds to be rescued from the contract.
     *
     * @param amount The amount of ETH to rescue
     */
    function emergencyRescue(uint256 amount) external override onlyOwner {
        _transferETH(msg.sender, amount);
    }

    /**
     * Receives ETH from contracts like WETH and strategy.
     */
    receive() external payable {}
}
