// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IFloodPlain} from "flood-contracts/interfaces/IFloodPlain.sol";
import {OrderHash} from "flood-contracts/libraries/OrderHash.sol";
import {WETH} from "solady/tokens/WETH.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC1271} from "src/IERC1271.sol";
import {IEIP712} from "permit2/src/interfaces/IEIP712.sol";

error NativeTrader__WrongOfferer();
error NativeTrader__WrongValue();
error NativeTrader__WrongTokens();
error NativeTrader__WrongSignature();
error NativeTrader__WrongReplacement();

/// @title Native Trader
/// @notice This contracts receives ETH and then trades it on Flood for a token of the sender's choice.
contract NativeTrader is IERC1271 {
    using OrderHash for IFloodPlain.Order;
    using ECDSA for bytes32;
    using SafeTransferLib for address;
    using SafeTransferLib for address payable;

    WETH immutable weth;
    IFloodPlain immutable floodPlain;
    bytes32 immutable domainSeparator;

    /// A mapping from permit hashes to the order signer.
    mapping(bytes32 permitHash => address user) public orders;

    constructor(WETH _weth, IFloodPlain _floodPlain) {
        weth = _weth;
        floodPlain = _floodPlain;
        address permit2 = address(floodPlain.PERMIT2());
        domainSeparator = IEIP712(permit2).DOMAIN_SEPARATOR();
        weth.approve(permit2, type(uint256).max);
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
        if (orders[hash] != address(0)) {
            return this.isValidSignature.selector;
        }
    }

    /// @notice Replaces an order with a different one but with the same offer.
    /// @dev We have users sign the order hash instead of the full permit hash to cancel an order. This is done so that cancellations require 1 additional signature.
    /// @param oldOrder The order to replace and the signature of the order hash.
    /// @param newOrder The order to replace with and the signature of the permit hash.
    function replaceOrder(IFloodPlain.SignedOrder calldata oldOrder, IFloodPlain.SignedOrder calldata newOrder)
        external
    {
        bytes32 permitHash = newOrderHash(oldOrder.order);
        address user = orders[permitHash];

        // Check wether the user signed the order hash, indicating that they want to replace the order.
        if (user == address(0) || user != cancelOrderHash(oldOrder.order).recoverCalldata(oldOrder.signature)) {
            revert NativeTrader__WrongSignature();
        }

        // Check wether the old user offer is the same as the new user offer.
        if (oldOrder.order.offer.length != newOrder.order.offer.length) {
            revert NativeTrader__WrongReplacement();
        }
        uint256 length = oldOrder.order.offer.length;
        for (uint256 i = 0; i < length; ++i) {
            if (oldOrder.order.offer[i].token != newOrder.order.offer[i].token) {
                revert NativeTrader__WrongReplacement();
            }
            if (oldOrder.order.offer[i].amount != newOrder.order.offer[i].amount) {
                revert NativeTrader__WrongReplacement();
            }
        }

        bytes32 newPermitHash = newOrderHash(newOrder.order);
        // Check wether the new user signed the permit hash, indicating that they want to replace the order.
        if (newPermitHash.recoverCalldata(newOrder.signature) != user) {
            revert NativeTrader__WrongSignature();
        }

        // Delete the old order and add the new one.
        delete orders[permitHash];
        orders[newPermitHash] = user;
    }

    /// @notice Cancels an order, making it unfillable and returning tokens and ETH to the user.
    /// @dev We have users sign the order hash instead of the full permit hash to cancel an order. This is done so that cancellations require 1 additional signature.
    /// @param order The order to cancel and the signature of the order hash.
    function cancelOrder(IFloodPlain.SignedOrder calldata order) external {
        bytes32 permitHash = newOrderHash(order.order);
        address user = orders[permitHash];

        // Check wether the user signed the order hash, indicating that they want to cancel the order.
        if (user == address(0) || user != cancelOrderHash(order.order).recoverCalldata(order.signature)) {
            revert NativeTrader__WrongSignature();
        }
        delete orders[permitHash];
        // Transfer the tokens back to the user.
        uint256 length = order.order.offer.length;
        // Unwrap the WETH and transfer it back to the user.
        weth.withdraw(order.order.offer[0].amount);
        payable(user).safeTransferETH(order.order.offer[0].amount);
        for (uint256 i = 1; i < length; ++i) {
            order.order.offer[i].token.safeTransfer(user, order.order.offer[i].amount);
        }
    }

    /// @notice Allows ETH as part of an order on Flood.
    /// @dev We require WETH to be the first token in the offer.
    function submitOrder(IFloodPlain.Order calldata order) external payable {
        if (order.offerer != address(this)) {
            revert NativeTrader__WrongOfferer();
        }
        if (order.offer[0].token != address(weth)) {
            revert NativeTrader__WrongTokens();
        }
        if (msg.value != order.offer[0].amount) {
            revert NativeTrader__WrongValue();
        }

        orders[newOrderHash(order)] = msg.sender;
        weth.deposit{value: order.offer[0].amount}();
        uint256 length = order.offer.length;
        // Deposit the rest of the tokens.
        for (uint256 i = 1; i < length; ++i) {
            order.offer[i].token.safeTransferFrom(msg.sender, address(this), order.offer[i].amount);
        }
    }

    receive() external payable {}

    function cancelOrderHash(IFloodPlain.Order calldata order) private view returns (bytes32) {
        return keccak256(abi.encodePacked(abi.encodePacked("\x19\x01", domainSeparator, order.hash())));
    }

    function newOrderHash(IFloodPlain.Order calldata order) private view returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, OrderHash.hashAsWitness(order, address(floodPlain)))
        );
    }
}
