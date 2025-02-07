# pragma version ^0.4.0

from snekmate.auth import ownable
from snekmate.tokens import erc20
from ethereum.ercs import IERC20
import iweth
import iflethstrategy

initializes: ownable
initializes: erc20[ownable := ownable]

weth: public(immutable(address))

rebalanceThreshold: public(uint256)
MAX_REBALANCE_THRESHOLD: constant(uint256) = 1 * 10 ** 18 # 1 ETH

strategy: public(iflethstrategy)
yieldReceiver: public(address)

exports: (
    ownable.owner,
    erc20.balanceOf,
)

@payable
@deploy
def __init__(_weth: address, yieldReceiver: address):
    self.rebalanceThreshold = 1 * 10 ** 17 # 0.1 ETH
    weth = _weth
    self.yieldReceiver = yieldReceiver
    ownable.__init__()
    erc20.__init__("DAOlympus ETH", "dETH", 18, "DAOlympus ETH", "1.0")

@payable
@external
def deposit(wethAmt: uint256 = 0):
    ethToDeposit: uint256 = msg.value
    if wethAmt > 0:
        extcall IERC20(weth).transferFrom(msg.sender, self, wethAmt)
        extcall iweth(weth).withdraw(wethAmt)
        ethToDeposit += wethAmt

    self._mintdETHAndRebalance(msg.sender, ethToDeposit)

@internal
def _rebalance():
    if self.strategy.address == empty(address):
        return
    if staticcall self.strategy.isUnwinding():
        return

    ethBalance: uint256 = self.balance
    ethThreshold: uint256 = (self.rebalanceThreshold * erc20.totalSupply) // 10 ** 18

    if ethBalance > ethThreshold:
        extcall self.strategy.convertETHToLST(value=ethBalance - ethThreshold)

@external
def rebalance():
    self._rebalance()

@external
def withdraw(amount: uint256):
    erc20._burn(msg.sender, amount)
    currentETHBalance: uint256 = self.balance

    # Check if we are requesting more ETH than is currently held in the contract
    if amount > currentETHBalance:
        # This is only possible when the strategy exists
        if self.strategy.address == empty(address):
            raw_revert(method_id("AmountExceedsETHBalance()"))

        # we are forced to withdraw from the strategy in this case. So withdrawing
        # more such that the raw eth balance stays at the threshold, post withdrawal
        newTotalSupply: uint256 = erc20.totalSupply
        expectedNewEthBalance: uint256 = (self.rebalanceThreshold * newTotalSupply) // 10 ** 18

        # if the new eth balance shold be less than the current eth balance, then this
        # contract can transfer some eth directory to teh user and only the remaining amount
        # is withdrawn from the strategy
        if expectedNewEthBalance <= currentETHBalance:
            rawEthToTransfer: uint256 = currentETHBalance - expectedNewEthBalance
            strategyEthToWithdraw: uint256 = amount - rawEthToTransfer

            send(msg.sender, rawEthToTransfer)

            extcall self.strategy.withdrawETH(strategyEthToWithdraw, msg.sender)
        # if the new eth balance should be more than the current eth balance, we need to
        # withdraw the entire amount from the strategy to:
        # 1. bring the raw eth balance to the threshold
        # 2. also to also fulfill the user's request
        else:
            rawEthRequiredToReachThreshold: uint256 = expectedNewEthBalance - currentETHBalance

            # withdraw eth to this contract
            extcall self.strategy.withdrawETH(rawEthRequiredToReachThreshold, self)

            # transfer the requested amount to the user, leaving the raw eth balance
            # at the threshold
            send(msg.sender, amount)
    # if the amount to withdraw is less than the current eth balance, then the contract
    # can directly transfer the eth to the user
    else:
        send(msg.sender, amount)
@external
def harvest():
    ethYield: uint256 = self._yieldAccumulated()
    strategyETHBalance: uint256 = staticcall self.strategy.balanceInETH()

    if strategyETHBalance >= ethYield:
        extcall self.strategy.withdrawETH(ethYield, self.yieldReceiver)
    else:
        delta: uint256 = ethYield - strategyETHBalance
        extcall self.strategy.withdrawETH(strategyETHBalance, self.yieldReceiver)
        send(self.yieldReceiver, delta)

@view
@internal
def _yieldAccumulated() -> uint256:
    return self._underlyingETHBalance() - erc20.totalSupply

@view
@external
def yieldAccumulated() -> uint256:
    return self._yieldAccumulated()

@view
@internal
def _underlyingETHBalance() -> uint256:
    return self.balance + staticcall self.strategy.balanceInETH()

@view
@external
def underlyingETHBalance() -> uint256:
    return self._underlyingETHBalance()


@internal
def _mintdETHAndRebalance(receiver: address, amount: uint256):
    erc20._mint(receiver, amount)
    self._rebalance()

@external
def setRebalanceThreshold(newThreshold: uint256):
    ownable._check_owner()
    if newThreshold > MAX_REBALANCE_THRESHOLD:
        raw_revert(method_id("RebalanceThresholdExceedsMax()"))
    self.rebalanceThreshold = newThreshold

@external
def setYieldReceiver(yieldReceiver: address):
    ownable._check_owner()
    if yieldReceiver == empty(address):
        raw_revert(method_id("YieldReceiverIsZero()"))
    self.yieldReceiver = yieldReceiver

@external
def changeStrategy(newStrategy: iflethstrategy):
    ownable._check_owner()
    if self.strategy.address != empty(address) and staticcall self.strategy.balanceInETH() != 0:
        raw_revert(method_id("CurrentStrategyHasBalance()"))
    self.strategy = newStrategy

@external
def emergencyRescue(amount: uint256):
    ownable._check_owner()
    send(msg.sender, amount)

@payable
@external
def __default__():
    return
