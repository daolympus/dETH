# dETH

This repository contains implementations of a liquid staking ETH token - one in Solidity (flETH, by the flaunch.gg team) and one in Vyper (dETH) implemented for DAOlympus.

## Overview

Both flETH and dETH implement a liquid staking token that:

- Accepts ETH and WETH deposits, minting equivalent token amounts
- Allows withdrawals by burning tokens
- Maintains a configurable ETH buffer (rebalance threshold) 
- Delegates excess ETH to a strategy contract for yield generation
- Separates yield from principal, directing yield to a designated receiver
- Includes safety features like emergency rescues and strategy migration

The contracts are functionally identical (aside from gas performance, where dETH is more performant), demonstrating how the same logic can be expressed in both Solidity and Vyper.

Key features:
- Rebalance threshold (default 10%) keeps some ETH liquid for withdrawals
- Strategy contract interface allows pluggable yield generation
- Yield is calculated as: underlying ETH balance - total token supply
- Owner can update yield receiver, threshold, and migrate strategies
- Emergency rescue functions allow recovery of trapped funds

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

## Gas Comparison

| Test                                      | flETH (Solidity) | dETH (Vyper) | % Improvement |
|-------------------------------------------|------------------|--------------|---------------|
| testChangeStrategy()                      | 346828           | 345611       | 0.35%         |
| testDeposit()                             | 271490           | 271212       | 0.10%         |
| testEmergencyRescue()                     | 16986            | 16655        | 1.95%         |
| testHarvestWhenStrategyHasEnoughBalance() | 26753            | 26062        | 2.58%         |
| testHarvestWhenStrategyHasLowBalance()    | 31956            | 31096        | 2.69%         |
| testOwnershipFunctions()                  | 14633            | 14588        | 0.31%         |
| testRebalance()                           | 90491            | 89533        | 1.06%         |
| testSetRebalanceThreshold()               | 17875            | 17414        | 2.58%         |
| testSetYieldReceiver()                    | 10695            | 10449        | 2.30%         |
| testSetup()                               | 20906            | 20294        | 2.93%         |
| testStrategyUnwinding()                   | 87874            | 87088        | 0.89%         |
| testUnderlyingETHBalance()                | 20771            | 19730        | 5.01%         |
| testWithdraw()                            | 94383            | 92852        | 1.62%         |
| testYieldAccumulated()                    | 90923            | 88856        | 2.28%         |
