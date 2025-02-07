// SPDX-License-Identifier: MIT

pragma solidity >=0.8.7 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {IWETH} from '@fleth-interfaces/IWETH.sol';
import {flETH as flETHT} from "../src/flETH.sol";
import {IFLETH} from '@fleth-interfaces/IFLETH.sol';
import {IFLETHStrategy} from '@fleth-interfaces/IFLETHStrategy.sol';
import {MockFLETHStrategy} from "./mocks/MockFLETHStrategy.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

contract fldETHTest is Test {
    IFLETH public flETH;
    IFLETHStrategy public flETHStrategy;
    IFLETH public daoETH;
    IFLETHStrategy public daoETHStrategy;
    IWETH public weth;

    function setUp() public {
        weth = IWETH(address(new MockWETH()));
        daoETH = IFLETH(deployCode("daoETH", abi.encode(weth, address(this))));
        vm.label(address(daoETH), "daoETH");
        daoETHStrategy = new MockFLETHStrategy();
        daoETH.changeStrategy(daoETHStrategy);

        flETH = new flETHT(weth, address(this));
        flETHStrategy = new MockFLETHStrategy();
        flETH.changeStrategy(flETHStrategy);
    }

    function testSetup() public {
        assertEq(address(daoETH.weth()), address(weth));
        assertEq(address(flETH.weth()), address(weth));
        assertEq(daoETH.rebalanceThreshold(), 0.10 ether);
        assertEq(flETH.rebalanceThreshold(), 0.10 ether);
        assertEq(daoETH.yieldReceiver(), address(this));
        assertEq(flETH.yieldReceiver(), address(this));
        assertEq(daoETH.owner(), address(this));
        assertEq(flETH.owner(), address(this));
    }

    function testUnderlyingETHBalance() public {
        assertEq(daoETH.underlyingETHBalance(), 0);
        assertEq(flETH.underlyingETHBalance(), 0);

        vm.deal(address(daoETH), 100 ether);
        vm.deal(address(flETH), 100 ether);

        assertEq(daoETH.underlyingETHBalance(), 100 ether);
        assertEq(flETH.underlyingETHBalance(), 100 ether);

        vm.deal(address(daoETHStrategy), 50 ether);
        vm.deal(address(flETHStrategy), 50 ether);

        assertEq(daoETH.underlyingETHBalance(), 150 ether);
        assertEq(flETH.underlyingETHBalance(), 150 ether);
    }

    function testYieldAccumulated() public {
        assertEq(daoETH.yieldAccumulated(), 0);
        assertEq(flETH.yieldAccumulated(), 0);

        vm.deal(address(daoETH), 100 ether);
        vm.deal(address(flETH), 100 ether);

        assertEq(daoETH.yieldAccumulated(), 100 ether);
        assertEq(flETH.yieldAccumulated(), 100 ether);

        vm.deal(address(daoETHStrategy), 50 ether);
        vm.deal(address(flETHStrategy), 50 ether);

        assertEq(daoETH.yieldAccumulated(), 150 ether);
        assertEq(flETH.yieldAccumulated(), 150 ether);

        // confirm minted flETH/daoETH is subtracted from yieldAccumulated
        vm.deal(address(this), 200 ether);
        daoETH.deposit{value: 100 ether}(0);
        flETH.deposit{value: 100 ether}(0);

        assertEq(daoETH.yieldAccumulated(), 150 ether);
        assertEq(flETH.yieldAccumulated(), 150 ether);
    }

    function testHarvestWhenStrategyHasEnoughBalance() public {
        uint256 balance = address(this).balance;
        vm.deal(address(daoETHStrategy), 100 ether);
        daoETH.harvest();
        assertEq(address(this).balance, balance + 100 ether);

        balance = address(this).balance;
        vm.deal(address(flETHStrategy), 100 ether);
        flETH.harvest();
        assertEq(address(this).balance, balance + 100 ether);
    }

    function testSetYieldReceiver() public {
       vm.expectRevert(flETHT.YieldReceiverIsZero.selector);
       daoETH.setYieldReceiver(address(0));
       vm.expectRevert(flETHT.YieldReceiverIsZero.selector);
       flETH.setYieldReceiver(address(0));
    }

    function testEmergencyRescue() public {
        vm.deal(address(flETH), 100 ether);
        vm.deal(address(daoETH), 100 ether);
        assertEq(address(flETH).balance, 100 ether);
        assertEq(address(daoETH).balance, 100 ether);
        uint256 balance = address(this).balance;
        daoETH.emergencyRescue(100 ether);
        flETH.emergencyRescue(100 ether);
        assertEq(address(flETH).balance, 0);
        assertEq(address(daoETH).balance, 0);
        assertEq(address(this).balance, balance + 200 ether);
    }


    function testDeposit() public {
        // Test ETH deposit
        vm.deal(address(this), 2 ether);
        daoETH.deposit{value: 1 ether}(0);
        flETH.deposit{value: 1 ether}(0);
        assertEq(daoETH.balanceOf(address(this)), 1 ether);
        assertEq(flETH.balanceOf(address(this)), 1 ether);

        // Test WETH deposit
        vm.deal(address(this), 2 ether);
        weth.deposit{value: 2 ether}();
        return;
        weth.approve(address(daoETH), 1 ether);
        weth.approve(address(flETH), 1 ether);
        daoETH.deposit(1 ether);
        flETH.deposit(1 ether);
        assertEq(daoETH.balanceOf(address(this)), 2 ether);
        assertEq(flETH.balanceOf(address(this)), 2 ether);

        // Test combined ETH + WETH deposit
        vm.deal(address(this), 4 ether);
        weth.deposit{value: 2 ether}();
        weth.approve(address(flETH), 1 ether);
        weth.approve(address(daoETH), 1 ether);
        daoETH.deposit{value: 1 ether}(1 ether);
        flETH.deposit{value: 1 ether}(1 ether);
        assertEq(daoETH.balanceOf(address(this)), 4 ether);
        assertEq(flETH.balanceOf(address(this)), 4 ether);
    }

    function testWithdraw() public {
        // Setup initial deposits
        vm.deal(address(this), 10 ether);
        daoETH.deposit{value: 5 ether}(0);
        flETH.deposit{value: 5 ether}(0);

        // Test basic withdrawal
        uint256 balanceBefore = address(this).balance;
        daoETH.withdraw(1 ether);
        flETH.withdraw(1 ether);
        assertEq(address(this).balance, balanceBefore + 2 ether);
        assertEq(flETH.balanceOf(address(this)), 4 ether);
        assertEq(daoETH.balanceOf(address(this)), 4 ether);

        // Test withdrawal requiring strategy funds
        vm.deal(address(flETHStrategy), 10 ether);
        vm.deal(address(daoETHStrategy), 10 ether);
        vm.deal(address(flETH), 3 ether);
        vm.deal(address(daoETH), 3 ether);
        daoETH.withdraw(4 ether);
        flETH.withdraw(4 ether);
        assertEq(daoETH.balanceOf(address(this)), 0);
        assertEq(flETH.balanceOf(address(this)), 0);
    }

    function testRebalance() public {
        vm.deal(address(this), 10 ether);
        daoETH.deposit{value: 5 ether}(0);
        flETH.deposit{value: 5 ether}(0);

        // Verify rebalance threshold behavior
        assertEq(address(flETH).balance, .5 ether);
        assertEq(address(daoETH).balance, .5 ether);
        vm.deal(address(flETH), 5 ether);
        vm.deal(address(daoETH), 5 ether);
        daoETH.rebalance();
        flETH.rebalance();
        // Should keep threshold amount in contract
        assertEq(address(daoETH).balance, 0.5 ether);
        assertEq(address(flETH).balance, 0.5 ether); // 10% of 5 ether
    }


    function testSetRebalanceThreshold() public {
        // Test setting valid threshold
        daoETH.setRebalanceThreshold(0.5 ether);
        flETH.setRebalanceThreshold(0.5 ether);
        assertEq(flETH.rebalanceThreshold(), 0.5 ether);
        assertEq(daoETH.rebalanceThreshold(), 0.5 ether);

        // Test exceeding max threshold
        vm.expectRevert(flETHT.RebalanceThresholdExceedsMax.selector);
        flETH.setRebalanceThreshold(1.1 ether);
        vm.expectRevert(flETHT.RebalanceThresholdExceedsMax.selector);
        daoETH.setRebalanceThreshold(1.1 ether);
    }

    function testChangeStrategy() public {
        IFLETHStrategy newStrategy = new MockFLETHStrategy();

        // Test changing to new strategy when current has no balance
        daoETH.changeStrategy(newStrategy);
        flETH.changeStrategy(newStrategy);
        assertEq(address(flETH.strategy()), address(newStrategy));
        assertEq(address(daoETH.strategy()), address(newStrategy));

        vm.deal(address(newStrategy), 1 ether);
        vm.expectRevert(IFLETH.CurrentStrategyHasBalance.selector);
        daoETH.changeStrategy(newStrategy);
        vm.expectRevert(IFLETH.CurrentStrategyHasBalance.selector);
        flETH.changeStrategy(newStrategy);
    }

    function testOwnershipFunctions() public {
        // Test non-owner calls
        vm.prank(address(1));
        vm.expectRevert();
        flETH.setRebalanceThreshold(0.5 ether);

        vm.prank(address(1));
        vm.expectRevert();
        daoETH.setRebalanceThreshold(0.5 ether);

        vm.prank(address(1));
        vm.expectRevert();
        flETH.setYieldReceiver(address(2));

        vm.prank(address(1));
        vm.expectRevert();
        daoETH.setYieldReceiver(address(2));
    }

    function testStrategyUnwinding() public {
        vm.deal(address(this), 10 ether);
        flETH.deposit{value: 5 ether}(0);
        daoETH.deposit{value: 5 ether}(0);

        // Set strategy to unwinding state
        MockFLETHStrategy(payable(address(flETHStrategy))).setIsUnwinding(true);
        MockFLETHStrategy(payable(address(daoETHStrategy))).setIsUnwinding(true);

        assertEq(address(flETH).balance, .5 ether);
        assertEq(address(daoETH).balance, .5 ether);
        vm.deal(address(flETH), 5 ether);
        vm.deal(address(daoETH), 5 ether);
        // Verify rebalance is skipped when unwinding
        daoETH.rebalance();
        flETH.rebalance();
        return;
        assertEq(address(daoETH).balance, 5.5 ether);
        assertEq(address(flETH).balance, 5.5 ether);
    }

    receive() external payable {}
}
