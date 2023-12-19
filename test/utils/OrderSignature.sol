// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {OrderHash} from "flood-contracts/libraries/OrderHash.sol";
import {IFloodPlain} from "flood-contracts/interfaces/IFloodPlain.sol";

contract OrderSignature is Test {
    function hash(IFloodPlain.Item calldata item) public pure returns (bytes32) {
        return OrderHash.hash(item);
    }

    function hash(IFloodPlain.Hook calldata hook) public pure returns (bytes32) {
        return OrderHash.hash(hook);
    }

    function hash(IFloodPlain.Order calldata order) public pure returns (bytes32) {
        return OrderHash.hash(order);
    }

    function hashAsWitness(IFloodPlain.Order calldata order, address spender) public pure returns (bytes32) {
        return OrderHash.hashAsWitness(order, spender);
    }

    function hashAsMessage(IFloodPlain.Order calldata order, bytes32 domainSeparator, address spender)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, OrderHash.hashAsWitness(order, spender)));
    }

    function hashAsCancelMessage(IFloodPlain.Order calldata order, bytes32 domainSeparator)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, OrderHash.hash(order)));
    }

    function getSignature(
        IFloodPlain.Order calldata order,
        uint256 privateKey,
        bytes32 domainSeparator,
        address spender
    ) public pure returns (bytes memory) {
        bytes32 msgHash = hashAsMessage(order, domainSeparator, spender);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }

    function getCancelSignature(IFloodPlain.Order calldata order, uint256 privateKey, bytes32 domainSeparator)
        public
        pure
        returns (bytes memory)
    {
        bytes32 msgHash = hashAsCancelMessage(order, domainSeparator);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, msgHash);
        return bytes.concat(r, s, bytes1(v));
    }
}
