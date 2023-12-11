// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console2 as console} from "forge-std/Test.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

error UnwrapHook__BadCaller();

interface IWrapped {
    function withdraw(uint256 amount) external;
}

/// @title Unwrap Hook
/// @notice This contract unwraps tokens sent to it by the Flood Plain contract.
/// Flood Plain does not support native currencies, so tokens are unwrapped in a post trade hook for the recipient to receive the native currency.
contract UnwrapHook {
    using SafeTransferLib for address;

    address immutable floodPlain;
    IWrapped immutable wrapped;

    bytes1 constant FALLBACK_SELECTOR = bytes1(0x00);

    constructor(address _weth, address _floodPlain) {
        wrapped = IWrapped(_weth);
        floodPlain = _floodPlain;
    }

    fallback() external {
        if (msg.sender != floodPlain) {
            revert UnwrapHook__BadCaller();
        }
        address recipient;
        assembly {
            recipient := shr(96, calldataload(0))
        }

        console.log("Recipient: %s", recipient);

        uint256 amount = ERC20(address(wrapped)).balanceOf(address(this));

        wrapped.withdraw(amount);
        recipient.safeTransferETH(amount);
    }
}
