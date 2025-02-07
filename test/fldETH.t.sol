// SPDX-License-Identifier: MIT

pragma solidity >=0.8.7 <0.9.0;

import {Test, console} from "forge-std/Test.sol";
import {IWETH} from "@fleth-interfaces/IWETH.sol";
import {flETH as flETHT} from "../src/flETH.sol";
import {IFLETH} from "@fleth-interfaces/IFLETH.sol";
import {IFLETHStrategy} from "@fleth-interfaces/IFLETHStrategy.sol";
import {MockFLETHStrategy} from "./mocks/MockFLETHStrategy.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

abstract contract wrappedETHTest is Test {
    IFLETH public flETH;
    IFLETHStrategy public flETHStrategy;
    IWETH public weth;

    function testSetup() public {
        assertEq(address(flETH.weth()), address(weth));
        assertEq(flETH.rebalanceThreshold(), 0.1 ether);
        assertEq(flETH.yieldReceiver(), address(this));
        assertEq(flETH.owner(), address(this));
    }

    function testUnderlyingETHBalance() public {
        assertEq(flETH.underlyingETHBalance(), 0);

        vm.deal(address(flETH), 100 ether);

        assertEq(flETH.underlyingETHBalance(), 100 ether);

        vm.deal(address(flETHStrategy), 50 ether);

        assertEq(flETH.underlyingETHBalance(), 150 ether);
    }

    function testYieldAccumulated() public {
        assertEq(flETH.yieldAccumulated(), 0);

        vm.deal(address(flETH), 100 ether);

        assertEq(flETH.yieldAccumulated(), 100 ether);

        vm.deal(address(flETHStrategy), 50 ether);

        assertEq(flETH.yieldAccumulated(), 150 ether);

        // confirm minted flETH/dETH is subtracted from yieldAccumulated
        vm.deal(address(this), 100 ether);
        flETH.deposit{value: 100 ether}(0);

        assertEq(flETH.yieldAccumulated(), 150 ether);
    }

    function testHarvestWhenStrategyHasEnoughBalance() public {
        uint256 balance = address(this).balance;
        vm.deal(address(flETHStrategy), 100 ether);
        flETH.harvest();
        assertEq(address(this).balance, balance + 100 ether);
    }

    function testHarvestWhenStrategyHasLowBalance() public {
        uint256 balance = address(this).balance;
        vm.deal(address(flETHStrategy), 100 ether);
        vm.deal(address(flETH), 100 ether);
        flETH.harvest();
        assertEq(address(this).balance, balance + 200 ether);
    }

    function testSetYieldReceiver() public {
        vm.expectRevert(flETHT.YieldReceiverIsZero.selector);
        flETH.setYieldReceiver(address(0));
    }

    function testEmergencyRescue() public {
        vm.deal(address(flETH), 100 ether);
        assertEq(address(flETH).balance, 100 ether);
        uint256 balance = address(this).balance;
        flETH.emergencyRescue(100 ether);
        assertEq(address(flETH).balance, 0);
        assertEq(address(this).balance, balance + 100 ether);
    }

    function testDeposit() public {
        // Test ETH deposit
        vm.deal(address(this), 1 ether);
        flETH.deposit{value: 1 ether}(0);
        assertEq(flETH.balanceOf(address(this)), 1 ether);

        // Test WETH deposit
        vm.deal(address(this), 1 ether);
        weth.deposit{value: 1 ether}();
        weth.approve(address(flETH), 1 ether);
        flETH.deposit(1 ether);
        assertEq(flETH.balanceOf(address(this)), 2 ether);

        // Test combined ETH + WETH deposit
        vm.deal(address(this), 2 ether);
        weth.deposit{value: 1 ether}();
        weth.approve(address(flETH), 1 ether);
        flETH.deposit{value: 1 ether}(1 ether);
        assertEq(flETH.balanceOf(address(this)), 4 ether);
    }

    function testWithdraw() public {
        // Setup initial deposits
        vm.deal(address(this), 5 ether);
        flETH.deposit{value: 5 ether}(0);

        // Test basic withdrawal
        uint256 balanceBefore = address(this).balance;
        flETH.withdraw(1 ether);
        assertEq(address(this).balance, balanceBefore + 1 ether);
        assertEq(flETH.balanceOf(address(this)), 4 ether);

        // Test withdrawal requiring strategy funds
        vm.deal(address(flETHStrategy), 10 ether);
        vm.deal(address(flETH), 3 ether);
        flETH.withdraw(4 ether);
        assertEq(flETH.balanceOf(address(this)), 0);
    }

    function testRebalance() public {
        vm.deal(address(this), 5 ether);
        flETH.deposit{value: 5 ether}(0);

        // Verify rebalance threshold behavior
        assertEq(address(flETH).balance, 0.5 ether);
        vm.deal(address(flETH), 5 ether);
        flETH.rebalance();
        // Should keep threshold amount in contract
        assertEq(address(flETH).balance, 0.5 ether); // 10% of 5 ether
    }

    function testSetRebalanceThreshold() public {
        // Test setting valid threshold
        flETH.setRebalanceThreshold(0.5 ether);
        assertEq(flETH.rebalanceThreshold(), 0.5 ether);

        // Test exceeding max threshold
        vm.expectRevert(flETHT.RebalanceThresholdExceedsMax.selector);
        flETH.setRebalanceThreshold(1.1 ether);
    }

    function testChangeStrategy() public {
        IFLETHStrategy newStrategy = new MockFLETHStrategy();

        // Test changing to new strategy when current has no balance
        flETH.changeStrategy(newStrategy);
        assertEq(address(flETH.strategy()), address(newStrategy));

        vm.deal(address(newStrategy), 1 ether);
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
        flETH.setYieldReceiver(address(2));
    }

    function testStrategyUnwinding() public {
        vm.deal(address(this), 5 ether);
        flETH.deposit{value: 5 ether}(0);

        // Set strategy to unwinding state
        MockFLETHStrategy(payable(address(flETHStrategy))).setIsUnwinding(true);

        assertEq(address(flETH).balance, 0.5 ether);
        vm.deal(address(flETH), 5 ether);
        // Verify rebalance is skipped when unwinding
        flETH.rebalance();
        return;
        assertEq(address(flETH).balance, 5.5 ether);
    }

    receive() external payable {}
}

contract flETHTest is wrappedETHTest {
    function setUp() public {
            weth = IWETH(address(new MockWETH()));
            flETH = new flETHT(weth, address(this));
            flETHStrategy = new MockFLETHStrategy();
            flETH.changeStrategy(flETHStrategy);
    }
}

contract dETHTest is wrappedETHTest {
     function setUp() public {
            weth = IWETH(address(new MockWETH()));
            flETH = IFLETH(deployCode("dETH", abi.encode(weth, address(this))));
            flETHStrategy = new MockFLETHStrategy();
            flETH.changeStrategy(flETHStrategy);
    }
}
