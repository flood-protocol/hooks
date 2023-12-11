// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IWrapped, UnwrapHook} from "src/native/UnwrapHook.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

contract MockWeth is Test {
    function withdraw(uint256 amount) external {
        vm.deal(msg.sender, amount);
    }

    function balanceOf(address) external pure returns (uint256) {
        return 100 ether;
    }
}

contract UnwrapHookTest is Test {
    address floodPlain = address(1);
    MockWeth weth = new MockWeth();
    UnwrapHook hook = new UnwrapHook(address(weth), floodPlain);

    function testUnwrap(address recipient) public {
        vm.prank(floodPlain);
        (bool s,) = address(hook).call(abi.encodePacked(recipient));
        assertTrue(s);
        assertEq(recipient.balance, 100 ether);
    }
}
