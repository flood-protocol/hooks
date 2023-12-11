// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2 as console} from "forge-std/Script.sol";
import {UnwrapHook, WETH} from "src/native/UnwrapHook.sol";
import {NativeTrader, IFloodPlain} from "src/native/NativeTrader.sol";

contract NativeScript is Script {
    function run() public {
        vm.broadcast();
    }

    function deployUnwrapHook(WETH weth, address floodPlain) public {
        vm.broadcast();
        new UnwrapHook(weth, floodPlain);
    }

    function deployNativeTrader(WETH weth, IFloodPlain floodPlain) public {
        vm.broadcast();
        new NativeTrader(weth, floodPlain);
    }
}
