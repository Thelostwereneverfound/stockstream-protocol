// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "./utils/BaseHook.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {SafeCast} from "v4-core/src/libraries/SafeCast.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary, toBeforeSwapDelta} from "v4-core/src/types/BeforeSwapDelta.sol";
import {SwapParams, ModifyLiquidityParams} from "v4-core/src/types/PoolOperation.sol";

/// @title StreamStockFeeHook
/// @notice Takes a 1% native-ETH fee on both directions of the ETH/STREAM
/// Uniswap V4 pool and forwards it to StockTreasury, which buys tokenized
/// stocks and sends them to StockDistributor for pro-rata payout to holders.
/// @dev Hook address MUST end in 0xCC (= 204). Mine a CREATE2 salt to achieve this.
///      Permission flags: beforeSwap(128) + afterSwap(64) +
///                        beforeSwapReturnDelta(8) + afterSwapReturnDelta(4) = 204 = 0xCC
contract StreamStockFeeHook is BaseHook {
    using SafeCast for uint256;

    uint256 public constant FEE_BPS = 100;    // 1% fee
    uint256 internal constant BPS   = 10_000;

    address public immutable treasury;

    error ZeroAddress();

    constructor(IPoolManager pm, address treasury_) BaseHook(pm) {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
    }

    // ── Hook permissions ─────────────────────────────────────────────────────

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize:              false,
            afterInitialize:               false,
            beforeAddLiquidity:            false,
            afterAddLiquidity:             false,
            beforeRemoveLiquidity:         false,
            afterRemoveLiquidity:          false,
            beforeSwap:                    true,
            afterSwap:                     true,
            beforeDonate:                  false,
            afterDonate:                   false,
            beforeSwapReturnDelta:         true,
            afterSwapReturnDelta:          true,
            afterAddLiquidityReturnDelta:  false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // ── Required overrides (no-op) ───────────────────────────────────────────

    function afterAddLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        return (IHooks.afterAddLiquidity.selector, BalanceDelta.wrap(0));
    }

    function afterRemoveLiquidity(
        address,
        PoolKey calldata,
        ModifyLiquidityParams calldata,
        BalanceDelta,
        BalanceDelta,
        bytes calldata
    ) external override returns (bytes4, BalanceDelta) {
        return (IHooks.afterRemoveLiquidity.selector, BalanceDelta.wrap(0));
    }

    // ── Fee logic ────────────────────────────────────────────────────────────

    /// @dev Returns true when the swap amount is specified in ETH terms.
    function _ethSpecified(SwapParams calldata p) internal pure returns (bool) {
        return (p.amountSpecified < 0) == p.zeroForOne;
    }

    /// @dev Runs before swap. Captures 1% fee when ETH is the input token.
    function _beforeSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        bytes calldata
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        // Only act on ETH-input swaps (currency0 = native ETH, amount specified in ETH)
        if (!key.currency0.isAddressZero() || !_ethSpecified(params)) {
            return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
        }
        uint256 amt = params.amountSpecified < 0
            ? uint256(-params.amountSpecified)
            : uint256(params.amountSpecified);
        uint256 fee = (amt * FEE_BPS) / BPS;
        if (fee == 0) return (this.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);

        poolManager.take(key.currency0, treasury, fee);
        return (this.beforeSwap.selector, toBeforeSwapDelta(fee.toInt128(), 0), 0);
    }

    /// @dev Runs after swap. Captures 1% fee when ETH is the output token.
    function _afterSwap(
        address,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata
    ) internal override returns (bytes4, int128) {
        // Only act on ETH-output swaps
        if (!key.currency0.isAddressZero() || _ethSpecified(params)) {
            return (this.afterSwap.selector, 0);
        }
        int128 a0  = delta.amount0();
        uint256 amt = a0 < 0 ? uint256(uint128(-a0)) : uint256(uint128(a0));
        uint256 fee = (amt * FEE_BPS) / BPS;
        if (fee == 0) return (this.afterSwap.selector, 0);

        poolManager.take(key.currency0, treasury, fee);
        return (this.afterSwap.selector, fee.toInt128());
    }
}
