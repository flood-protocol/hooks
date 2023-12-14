// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Script, console2 as console} from "forge-std/Script.sol";
import {BetterScript} from "./BetterScript.s.sol";
import {UnwrapHook, WETH} from "src/native/UnwrapHook.sol";
import {NativeTrader, IFloodPlain} from "src/native/NativeTrader.sol";

contract NativeScript is BetterScript {
    function deployUnwrapHook(WETH weth, address floodPlain) public {
        bytes32 salt = bytes32(0xe312ba886ebb062d6230c385687badf67809de670f2cc521818f00000000b71e);

        uint256 key = vm.envUint("ALT_ADMIN_KEY");
        vm.broadcast(key);
        console.log(
            "Deployed UnwrapHook at", deploy3(type(UnwrapHook).creationCode, salt, abi.encode(weth, floodPlain))
        );
    }

    function deployNativeTrader(WETH weth, IFloodPlain floodPlain) public {
        bytes32 salt = bytes32(0xe312ba886ebb062d6230c385687badf67809de67261e13702f62000000025ed8);
        uint256 key = vm.envUint("ALT_ADMIN_KEY");
        vm.broadcast(key);
        console.log(
            "Deployed Native Trader at", deploy3(type(NativeTrader).creationCode, salt, abi.encode(weth, floodPlain))
        );
    }
}
