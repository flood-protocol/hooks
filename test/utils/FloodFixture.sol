// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {FloodPlain, ISignatureTransfer, IFloodPlain} from "flood-contracts/FloodPlain.sol";
import {IEIP712} from "permit2/src/interfaces/IEIP712.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {OrderSignature} from "./OrderSignature.sol";

contract FloodFixture is DeployPermit2 {
    OrderSignature sigLib = new OrderSignature();
    FloodPlain flood;
    ISignatureTransfer permit2;

    function setUp() public virtual {
        permit2 = ISignatureTransfer(deployPermit2());
        flood = new FloodPlain(address(permit2));
    }

    function hashAsMessage(IFloodPlain.Order memory order) internal view returns (bytes32) {
        return sigLib.hashAsMessage(order, IEIP712(address(permit2)).DOMAIN_SEPARATOR(), address(flood));
    }

    function hashAsCancelMessage(IFloodPlain.Order memory order) internal view returns (bytes32) {
        return sigLib.hashAsCancelMessage(order, IEIP712(address(permit2)).DOMAIN_SEPARATOR());
    }

    function getSignature(IFloodPlain.Order memory order, Account memory signer)
        internal
        view
        returns (bytes memory sig)
    {
        sig = sigLib.getSignature(order, signer.key, IEIP712(address(permit2)).DOMAIN_SEPARATOR(), address(flood));
    }

    function getCancelSignature(IFloodPlain.Order memory order, Account memory signer)
        internal
        view
        returns (bytes memory sig)
    {
        sig = sigLib.getCancelSignature(order, signer.key, IEIP712(address(permit2)).DOMAIN_SEPARATOR());
    }
}
