// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {UnwrapHook} from "src/native/UnwrapHook.sol";
import {WETH} from "solady/tokens/WETH.sol";

contract UnwrapHookTest is Test {
    WETH weth;
    UnwrapHook hook;

    function setUp() public {
        weth = new WETH();
        hook = new UnwrapHook(weth, address(this));
    }

    function testUnwrap(address recipient) public {
        bound(uint256(uint160(recipient)), 100, type(uint160).max);

        deal(address(weth), address(hook), 100 ether);
        uint256 balancePre = recipient.balance;
        (bool s,) = address(hook).call(abi.encodePacked(recipient));
        assertTrue(s);
        assertEq(recipient.balance, balancePre + 100 ether);
    }
}
