//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken public rebaseToken;
    Vault public vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 _rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: _rewardAmount}("");
    }

    function testDepositLinear(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, _amount);
        vault.deposit{value: _amount}();

        uint256 startBalance = rebaseToken.balanceOf(user);
        console.log("startBalance", startBalance);
        assertEq(startBalance, _amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assertGt(middleBalance, startBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);

        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, _amount);
        vault.deposit{value: _amount}();
        assertEq(rebaseToken.balanceOf(user), _amount);
        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(address(user).balance, _amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 _depositAmount, uint256 _time) public {
        _time = bound(_time, 1000, type(uint32).max);
        _depositAmount = bound(_depositAmount, 1e5, type(uint96).max);
        vm.deal(user, _depositAmount);
        vm.prank(user);
        vault.deposit{value: _depositAmount}();

        vm.warp(block.timestamp + _time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        vm.deal(owner, balanceAfterSomeTime - _depositAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - _depositAmount);

        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;

        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, _depositAmount);
    }

    function testTransfer(uint256 _amount, uint256 _amountToSend) public {
        _amount = bound(_amount, 1e5 + 1e5, type(uint96).max);
        _amountToSend = bound(_amountToSend, 1e5, _amount - 1e5);

        vm.deal(user, _amount);
        vm.prank(user);
        vault.deposit{value: _amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, _amount);
        assertEq(user2Balance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, _amountToSend);
        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, _amount - _amountToSend);
        assertEq(user2BalanceAfterTransfer, _amountToSend);

        assertEq(rebaseToken.getUsersInterestRate(user), 5e10);
        assertEq(rebaseToken.getUsersInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRate(uint256 _newInterestRate) public {
        vm.prank(user);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(_newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        vm.prank(user);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        uint256 interestRate = rebaseToken.getInterestRate();
        rebaseToken.mint(user, 100, interestRate);
        vm.expectPartialRevert(bytes4(IAccessControl.AccessControlUnauthorizedAccount.selector));
        rebaseToken.burn(user, 100);
    }

    function testGetPrincipalAmount(uint256 _amount) public {
        _amount = bound(_amount, 1e5, type(uint96).max);
        vm.deal(user, _amount);
        vm.prank(user);
        vault.deposit{value: _amount}();
        assertEq(rebaseToken.principalBalanceOf(user), _amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalanceOf(user), _amount);

        vm.warp(block.timestamp + 1 hours);
        assertEq(rebaseToken.principalBalanceOf(user), _amount);
    }

    function testGetRebaseTokenAddress() public view {
        assertEq(address(rebaseToken), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 _newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        _newInterestRate = bound(_newInterestRate, initialInterestRate, type(uint96).max);
        vm.prank(owner);
        vm.expectPartialRevert(RebaseToken.RabaseToken__InterestRateCanOnlyDecrease.selector);
        rebaseToken.setInterestRate(_newInterestRate);
        assertEq(rebaseToken.getInterestRate(), initialInterestRate);
    }
}
