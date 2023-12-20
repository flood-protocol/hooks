// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {UnwrapHook} from "src/native/UnwrapHook.sol";
import {TokenFixture} from "../utils/TokenFixture.sol";

contract UnwrapHookTest is TokenFixture {
    UnwrapHook hook;

    function setUp() public {
        hook = new UnwrapHook(weth, address(this));
    }

    function testUnwrap() public {
        address recipient = address(42);
        deal(address(weth), address(hook), 100 ether);
        uint256 balancePre = recipient.balance;
        (bool s,) = address(hook).call(abi.encodePacked(recipient));
        assertTrue(s);
        assertEq(recipient.balance, balancePre + 100 ether);
    }
}
