// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "solady/tokens/ERC20.sol";
import {WETH} from "solady/tokens/WETH.sol";

address constant ARBITRUM_USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;
address constant ARBITRUM_WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
address constant ARBITRUM_DAI = 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1;
address constant ARBITRUM_USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;

contract MockToken is ERC20 {
    string internal innerName;
    string internal innerSymbol;
    uint8 internal immutable innerDecimals;

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        innerName = _name;
        innerSymbol = _symbol;
        innerDecimals = _decimals;
    }

    function decimals() public view override returns (uint8) {
        return innerDecimals;
    }

    function name() public view override returns (string memory) {
        return innerName;
    }

    function symbol() public view override returns (string memory) {
        return innerSymbol;
    }
}

contract TokenFixture is Test {
    ERC20 internal usdc = deployTokenIfEmpty(ARBITRUM_USDC, "USDC", "USDC", 6);
    WETH internal weth = deployWETHIfEmpty(ARBITRUM_WETH);
    ERC20 internal dai = deployTokenIfEmpty(ARBITRUM_DAI, "DAI", "DAI", 18);
    ERC20 internal usdt = deployTokenIfEmpty(ARBITRUM_USDT, "USDT", "USDT", 6);

    function deployWETHIfEmpty(address target) internal returns (WETH) {
        uint256 existingCode = target.code.length;
        if (existingCode > 0) {
            return WETH(payable(target));
        }
        WETH deployed = new WETH();

        return WETH(payable(address(deployed)));
    }

    // Deploys a contract to `target` if the address has no existing code.
    // This is used to deploy contracts in tests ONLY if you're not forking.
    function deployTokenIfEmpty(address target, string memory name, string memory symbol, uint8 decimals)
        internal
        returns (ERC20)
    {
        uint256 existingCode = target.code.length;
        if (existingCode > 0) {
            return ERC20(target);
        }
        MockToken deployed = new MockToken(name, symbol, decimals);

        return ERC20(address(deployed));
    }
}
