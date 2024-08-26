// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { WenFoundry } from "./WenFoundry.sol";
import { IUniswapV2Factory } from "./interfaces/IUniswapV2Factory.sol";

error Forbidden();

/// @title External entities registry. Primarily used to check and restrict pre-graduation token transfers to specific entities like Uniswap V2 pairs.
/// @author strobie <@0xstrobe>
/// @notice Refer to the WenToken template contract to verify that the restriction is lifted after graduation.
contract ExternalEntities {
    address public immutable weth;

    IUniswapV2Factory[] public knownFactories;
    mapping(address => bool) public pregradRestricted;
    address public owner;

    constructor(address _owner, address _weth) {
        owner = _owner;
        weth = _weth;
    }

    function addFactory(address factory) external {
        if (msg.sender != owner) revert Forbidden();

        knownFactories.push(IUniswapV2Factory(factory));
    }

    function removeFactory(address factory) external {
        if (msg.sender != owner) revert Forbidden();

        for (uint256 i = 0; i < knownFactories.length; i++) {
            if (address(knownFactories[i]) == factory) {
                knownFactories[i] = knownFactories[knownFactories.length - 1];
                knownFactories.pop();
                break;
            }
        }
    }

    function addPregradRestricted(address to) external {
        if (msg.sender != owner) revert Forbidden();

        pregradRestricted[to] = true;
    }

    function removePregradRestricted(address to) external {
        if (msg.sender != owner) revert Forbidden();

        pregradRestricted[to] = false;
    }

    function computeUniV2Pair(IUniswapV2Factory factory, address tokenA, address tokenB) public view returns (address pair, bool exists) {
        pair = factory.getPair(tokenA, tokenB);
        if (pair != address(0)) {
            return (pair, true);
        }

        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        // both uniswap and quickswap v2 are using the same init code hash
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
                        )
                    )
                )
            )
        );

        return (pair, false);
    }

    function isPregradRestricted(address token, address to) external view returns (bool) {
        for (uint256 i = 0; i < knownFactories.length; i++) {
            (address pair,) = computeUniV2Pair(knownFactories[i], token, weth);
            if (pair == to) {
                return true;
            }
        }

        return pregradRestricted[to];
    }
}
