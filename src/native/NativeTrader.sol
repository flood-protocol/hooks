// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IFloodPlain} from "flood-contracts/interfaces/IFloodPlain.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {ERC20} from "solady/tokens/ERC20.sol";

error NativeTrader__WrongValue();
error NativeTrader__WrongTokens();

interface IERC1271 {
    function isValidSignature(bytes32 hash, bytes calldata signature) external view returns (bytes4 magicValue);
}

/// @title Native Trader
/// @notice This contracts receives ETH and then trades it on Flood for a token of the sender's choice.
contract NativeTrader is IERC1271 {
    WETH immutable weth;
    IFloodPlain immutable floodPlain;

    /// A mapping from permit hashes to the order signer.
    mapping(bytes32 permitHash => bool present) public orders;

    constructor(WETH _weth, IFloodPlain _floodPlain) {
        weth = _weth;
        floodPlain = _floodPlain;
    }

    /// @notice Max approves a token to Permit2.
    /// @param token The token to approve.
    function approveToken(ERC20 token) external {
        token.approve(address(floodPlain.PERMIT2()), type(uint256).max);
    }

    /// @notice Will be called by Permit2 before transferring tokens.
    /// We consider all orders seen as valid, without checking the signature. This is because ownership of the account is required to send ETH to this contract in the first place.
    /// Furthermore, replay attacks and double spends are not possible as the permit hash is unique for each nonce.
    function isValidSignature(bytes32 hash, bytes calldata /* signature */ )
        external
        view
        override
        returns (bytes4 magicValue)
    {
        if (orders[hash]) {
            return this.isValidSignature.selector;
        }
    }

    /// @notice Allows ETH as part of an order on Flood.
    /// @dev We require WETH to be the first token in the offer.
    function trade(IFloodPlain.Order calldata order) external payable {
        if (order.offer[0].token != address(weth)) {
            revert NativeTrader__WrongTokens();
        }
        if (msg.value != order.offer[0].amount) {
            revert NativeTrader__WrongValue();
        }

        orders[floodPlain.getPermitHash(order)] = true;
        weth.deposit{value: order.offer[0].amount}();
        uint256 length = order.offer.length;
        // Deposit the rest of the tokens.
        for (uint256 i = 1; i < length; ++i) {
            ERC20(order.offer[i].token).transferFrom(msg.sender, address(this), order.offer[i].amount);
        }
    }
}
