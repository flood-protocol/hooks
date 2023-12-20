// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IFloodPlain} from "flood-contracts/interfaces/IFloodPlain.sol";
import {OrderHash as OrderHashCalldata} from "flood-contracts/libraries/OrderHash.sol";
import {ERC20} from "solady/tokens/ERC20.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IEIP712} from "permit2/src/interfaces/IEIP712.sol";
import {IERC1271} from "permit2/src/interfaces/IERC1271.sol";
import {OrderHashMemory} from "../OrderHashMemory.sol";

interface AcrossMessageHandler {
    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address relayer,
        bytes memory message
    ) external;
}

error AcrossTrader__BadCaller();
error AcrossTrader__WrongSignature();
error AcrossTrader__WrongReplacement();

/// @title Across Trader
/// @notice This contracts receives tokens from an Across relay and then trades them on Flood for a token of the sender's choice.
contract AcrossTrader is IERC1271, AcrossMessageHandler {
    using OrderHashCalldata for IFloodPlain.Order;
    using OrderHashMemory for IFloodPlain.Order;
    using ECDSA for bytes32;
    using SafeTransferLib for address;
    using SafeTransferLib for address payable;

    IFloodPlain immutable floodPlain;
    bytes32 immutable domainSeparator;
    address immutable acrossSpokePool;

    /// A mapping from permit hashes to the order signer.
    mapping(bytes32 permitHash => address user) public orders;

    constructor(IFloodPlain _floodPlain, address _acrossSpokePool) {
        floodPlain = _floodPlain;
        address permit2 = address(floodPlain.PERMIT2());
        domainSeparator = IEIP712(permit2).DOMAIN_SEPARATOR();
        acrossSpokePool = _acrossSpokePool;
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
            revert AcrossTrader__WrongSignature();
        }

        // Check wether the old user offer is the same as the new user offer.
        if (oldOrder.order.offer.length != newOrder.order.offer.length) {
            revert AcrossTrader__WrongReplacement();
        }
        uint256 length = oldOrder.order.offer.length;
        for (uint256 i = 0; i < length; ++i) {
            if (oldOrder.order.offer[i].token != newOrder.order.offer[i].token) {
                revert AcrossTrader__WrongReplacement();
            }
            if (oldOrder.order.offer[i].amount != newOrder.order.offer[i].amount) {
                revert AcrossTrader__WrongReplacement();
            }
        }

        bytes32 newPermitHash = newOrderHash(newOrder.order);
        // Check wether the new user signed the permit hash, indicating that they want to replace the order.
        if (newPermitHash.recoverCalldata(newOrder.signature) != user) {
            revert AcrossTrader__WrongSignature();
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
            revert AcrossTrader__WrongSignature();
        }
        delete orders[permitHash];
        // Transfer the tokens back to the user.
        uint256 length = order.order.offer.length;

        for (uint256 i = 0; i < length; ++i) {
            order.order.offer[i].token.safeTransfer(user, order.order.offer[i].amount);
        }
    }

    /// @notice Receives tokens from an Across relay, then markes an order as valid, making it fillable for Flood fulfillers.
    /// @dev We don't support Basket Liquidations in this example. To do so, one could probably save an additional counter in storage and increment it each time an Across relay with an offer token completes.
    /// @dev The Signature of the Flood order should be passed offchain to the Flood Fulfiller, once the relay completes.
    function handleAcrossMessage(
        address tokenSent,
        uint256 amount,
        bool fillCompleted,
        address, /*relayer*/
        bytes memory message
    ) external {
        if (msg.sender != acrossSpokePool) {
            revert AcrossTrader__BadCaller();
        }

        if (!fillCompleted) {
            return;
        }

        // The user here is not strictly necessary as can be recovered from the signature. But since people mess signatures up all the time, we double check to prevent a loss of funds.
        (
            address zone,
            address recipient,
            IFloodPlain.Item memory consideration,
            uint256 nonce,
            uint256 deadline,
            IFloodPlain.Hook[] memory preHooks,
            IFloodPlain.Hook[] memory postHooks,
            address user
        ) = abi.decode(
            message,
            (address, address, IFloodPlain.Item, uint256, uint256, IFloodPlain.Hook[], IFloodPlain.Hook[], address)
        );

        // Reconstruct the offer
        IFloodPlain.Item[] memory offer = new IFloodPlain.Item[](1);
        offer[0] = IFloodPlain.Item({token: tokenSent, amount: amount});
        IFloodPlain.Order memory order = IFloodPlain.Order({
            offerer: address(this),
            zone: zone,
            recipient: recipient,
            offer: offer,
            consideration: consideration,
            nonce: nonce,
            deadline: deadline,
            preHooks: preHooks,
            postHooks: postHooks
        });
        bytes32 permitHash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, OrderHashMemory.hashAsWitness(order, address(floodPlain)))
        );

        orders[permitHash] = user;
    }

    function cancelOrderHash(IFloodPlain.Order calldata order) private view returns (bytes32) {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, OrderHashCalldata.hash(order)));
    }

    function newOrderHash(IFloodPlain.Order calldata order) private view returns (bytes32) {
        return keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, OrderHashCalldata.hashAsWitness(order, address(floodPlain)))
        );
    }
}
