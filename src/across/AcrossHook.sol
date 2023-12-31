// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC20} from "solady/tokens/ERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IFloodPlain} from "flood-contracts/interfaces/IFloodPlain.sol";

interface AcrossSpokePool {
    function depositNow(
        address recipient,
        address originToken,
        uint256 amount,
        uint256 destinationChainId,
        int64 relayerFeePct,
        bytes memory message,
        uint256 maxCount
    ) external;
}

contract AcrossHook {
    AcrossSpokePool immutable across;
    IFloodPlain immutable flood;

    constructor(AcrossSpokePool _across, IFloodPlain _flood) {
        across = _across;
        flood = _flood;
    }

    function deposit(
        IFloodPlain.Order calldata order,
        uint256 destinationChainId,
        int64 relayerFeePct,
        bytes calldata message
    ) external {
        uint256 considerationReceived = ERC20(order.consideration.token).balanceOf(address(this));

        SafeTransferLib.safeApprove(order.consideration.token, address(across), considerationReceived);
        across.depositNow(
            order.recipient,
            order.consideration.token,
            considerationReceived,
            destinationChainId,
            relayerFeePct,
            message,
            type(uint256).max
        );
    }
}
