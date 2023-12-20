// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {WETH} from "solady/tokens/WETH.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";

error UnwrapHook__BadCaller();

/// @title Unwrap Hook
/// @notice This contract unwraps tokens sent to it by the Flood Plain contract.
/// Flood Plain does not support native currencies, so tokens are unwrapped in a post trade hook for the recipient to receive the native currency.
contract UnwrapHook {
    using SafeTransferLib for address;

    address immutable floodPlain;
    WETH immutable weth;

    constructor(WETH _weth, address _floodPlain) {
        weth = _weth;
        floodPlain = _floodPlain;
    }

    fallback() external payable {
        if (msg.sender != floodPlain) {
            revert UnwrapHook__BadCaller();
        }
        address recipient;
        assembly {
            recipient := shr(96, calldataload(0))
        }

        uint256 amount = weth.balanceOf(address(this));

        weth.withdraw(amount);
        recipient.safeTransferETH(amount);
    }

    receive() external payable {}
}
