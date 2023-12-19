// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2 as console} from "forge-std/Test.sol";
import {FloodPlain} from "flood-contracts/FloodPlain.sol";
import {FloodFixture} from "test/utils/FloodFixture.sol";
import {TokenFixture} from "test/utils/TokenFixture.sol";

import {
    NativeTrader,
    IFloodPlain,
    NativeTrader__WrongOfferer,
    NativeTrader__WrongValue,
    NativeTrader__WrongReplacement,
    NativeTrader__WrongTokens,
    NativeTrader__WrongSignature
} from "src/native/NativeTrader.sol";

contract NativeTraderTest is TokenFixture, FloodFixture {
    NativeTrader trader;
    Account alice = makeAccount("alice");
    Account bob = makeAccount("bob");

    function setUp() public override {
        super.setUp();
        trader = new NativeTrader(weth, flood);
    }

    function prepareTestOrder() internal view returns (IFloodPlain.Order memory order) {
        IFloodPlain.Item[] memory offer = new IFloodPlain.Item[](1);
        offer[0] = IFloodPlain.Item({token: address(weth), amount: 1 ether});
        order = IFloodPlain.Order({
            offerer: address(trader),
            zone: address(2),
            offer: offer,
            consideration: IFloodPlain.Item({token: address(usdc), amount: 1e6}),
            deadline: type(uint256).max,
            nonce: 0,
            recipient: alice.addr,
            preHooks: new IFloodPlain.Hook[](0),
            postHooks: new IFloodPlain.Hook[](0)
        });
    }

    function testSubmitOrder() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        vm.prank(alice.addr);
        deal(alice.addr, order.offer[0].amount);
        trader.submitOrder{value: order.offer[0].amount}(order);

        // Signature should be valid at this point.
        assertEq(trader.isValidSignature(hashAsMessage(order), bytes("")), trader.isValidSignature.selector);
        // Trader contract should have wrapped ether.
        assertEq(weth.balanceOf(address(trader)), order.offer[0].amount);
    }

    function testSubmitWrongTokens() public {
        IFloodPlain.Order memory order = prepareTestOrder();

        order.offer[0] = IFloodPlain.Item({token: address(9), amount: order.offer[0].amount});
        vm.prank(alice.addr);
        deal(alice.addr, order.offer[0].amount);
        vm.expectRevert(NativeTrader__WrongTokens.selector);
        trader.submitOrder{value: order.offer[0].amount}(order);
    }

    function testSubmitWrongAmount() public {
        IFloodPlain.Order memory order = prepareTestOrder();

        vm.prank(alice.addr);
        deal(alice.addr, order.offer[0].amount);
        vm.expectRevert(NativeTrader__WrongValue.selector);
        trader.submitOrder{value: order.offer[0].amount - 1}(order);
    }

    function testSubmitWrongOfferer() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        order.offerer = alice.addr;
        vm.prank(alice.addr);
        deal(alice.addr, order.offer[0].amount);
        vm.expectRevert(NativeTrader__WrongOfferer.selector);
        trader.submitOrder{value: order.offer[0].amount}(order);
    }

    function testSubmitMultipleItems() public {
        IFloodPlain.Item[] memory offer = new IFloodPlain.Item[](2);
        offer[0] = IFloodPlain.Item({token: address(weth), amount: 1 ether});
        offer[1] = IFloodPlain.Item({token: address(usdc), amount: 1e6});
        IFloodPlain.Order memory order = prepareTestOrder();
        order.offer = offer;
        vm.startPrank(alice.addr);
        usdc.approve(address(trader), 1e6);
        deal(address(usdc), alice.addr, order.offer[1].amount);
        deal(alice.addr, order.offer[0].amount);
        trader.submitOrder{value: order.offer[0].amount}(order);
        vm.stopPrank();

        // Signature should be valid at this point.
        assertEq(trader.isValidSignature(hashAsMessage(order), bytes("")), trader.isValidSignature.selector);
        // Trader contract should have wrapped ether.
        assertEq(weth.balanceOf(address(trader)), order.offer[0].amount);
        // Trader contract should have tokens.
        assertEq(usdc.balanceOf(address(trader)), order.offer[1].amount);
    }

    function testCancelOrder() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        testSubmitOrder();

        bytes memory cancelSig = getCancelSignature(order, alice);

        IFloodPlain.SignedOrder memory signedOrder = IFloodPlain.SignedOrder({order: order, signature: cancelSig});

        trader.cancelOrder(signedOrder);
        // Alice has her balance back.
        assertEq(alice.addr.balance, order.offer[0].amount);
        // Order is no longer fillable.
        assertEq(trader.isValidSignature(hashAsMessage(order), bytes("")), bytes4(0));
    }

    function testCancelWrongSigner() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        testSubmitOrder();

        bytes memory cancelSig = getCancelSignature(order, bob);

        IFloodPlain.SignedOrder memory signedOrder = IFloodPlain.SignedOrder({order: order, signature: cancelSig});
        vm.expectRevert(NativeTrader__WrongSignature.selector);
        trader.cancelOrder(signedOrder);
    }

    function testCancelWrongOrder() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        testSubmitOrder();

        order.nonce = 10;
        bytes memory cancelSig = getCancelSignature(order, alice);

        IFloodPlain.SignedOrder memory signedOrder = IFloodPlain.SignedOrder({order: order, signature: cancelSig});
        vm.expectRevert(NativeTrader__WrongSignature.selector);
        trader.cancelOrder(signedOrder);
    }

    function testReplaceOrder() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        testSubmitOrder();

        IFloodPlain.SignedOrder memory oldOrder =
            IFloodPlain.SignedOrder({order: order, signature: getCancelSignature(order, alice)});

        IFloodPlain.Order memory newBaseOrder = IFloodPlain.Order({
            offerer: order.offerer,
            zone: order.zone,
            recipient: order.recipient,
            offer: order.offer,
            consideration: IFloodPlain.Item({token: address(usdt), amount: 1e6}),
            preHooks: order.preHooks,
            postHooks: order.postHooks,
            nonce: order.nonce,
            deadline: order.deadline
        });

        IFloodPlain.SignedOrder memory newOrder =
            IFloodPlain.SignedOrder({order: newBaseOrder, signature: getSignature(newBaseOrder, alice)});

        trader.replaceOrder(oldOrder, newOrder);

        // Check that the old order is not fillable anymore
        assertEq(trader.isValidSignature(hashAsMessage(order), bytes("")), bytes4(0), "old order is still valid.");
        // Check that the new order is fillable
        assertEq(
            trader.isValidSignature(hashAsMessage(newBaseOrder), bytes("")),
            trader.isValidSignature.selector,
            "replaced order is not valid."
        );
    }

    function testReplaceWrongSignature() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        testSubmitOrder();

        IFloodPlain.SignedOrder memory oldOrder =
            IFloodPlain.SignedOrder({order: order, signature: getCancelSignature(order, alice)});

        IFloodPlain.Order memory newBaseOrder = IFloodPlain.Order({
            offerer: order.offerer,
            zone: order.zone,
            recipient: order.recipient,
            offer: order.offer,
            consideration: IFloodPlain.Item({token: address(usdt), amount: 1e6}),
            preHooks: order.preHooks,
            postHooks: order.postHooks,
            nonce: order.nonce,
            deadline: order.deadline
        });

        IFloodPlain.SignedOrder memory newOrder =
            IFloodPlain.SignedOrder({order: newBaseOrder, signature: getSignature(newBaseOrder, bob)});

        vm.expectRevert(NativeTrader__WrongSignature.selector);
        trader.replaceOrder(oldOrder, newOrder);
    }

    function testReplaceWrongReplacement() public {
        IFloodPlain.Order memory order = prepareTestOrder();
        testSubmitOrder();

        IFloodPlain.SignedOrder memory oldOrder =
            IFloodPlain.SignedOrder({order: order, signature: getCancelSignature(order, alice)});

        IFloodPlain.Item[] memory newOffer = new IFloodPlain.Item[](1);
        newOffer[0] = IFloodPlain.Item({token: address(weth), amount: 2 ether});
        IFloodPlain.Order memory newBaseOrder = IFloodPlain.Order({
            offerer: order.offerer,
            zone: order.zone,
            recipient: order.recipient,
            offer: newOffer,
            consideration: IFloodPlain.Item({token: address(usdt), amount: 1e6}),
            preHooks: order.preHooks,
            postHooks: order.postHooks,
            nonce: order.nonce,
            deadline: order.deadline
        });

        IFloodPlain.SignedOrder memory newOrder =
            IFloodPlain.SignedOrder({order: newBaseOrder, signature: getSignature(newBaseOrder, bob)});

        vm.expectRevert(NativeTrader__WrongReplacement.selector);
        trader.replaceOrder(oldOrder, newOrder);
    }
}
