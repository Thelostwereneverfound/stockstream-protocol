// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";

/// @title StockTreasury
/// @notice Accumulates native-ETH taxes from FlowStockFeeHook and on keeper
/// call buys NVDA/AAPL/GOOGL/META stock tokens through their Uniswap v4
/// ETH pools. Bought stock goes straight to StockDistributor.
/// Supports optional protocol fee for StreamFactory integrations.
contract StockTreasury is Ownable, IUnlockCallback {
    IPoolManager public immutable poolManager;

    address public distributor;
    mapping(address => bool) public keeper;

    // ── Protocol fee (StreamFactory) ──────────────────────────────────────
    address public protocolFeeRecipient;
    uint256 public protocolFeeBps; // 50 = 0.5%, 100 = 1%, max 1000 = 10%

    struct Stock {
        address token;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    Stock[] public stocks;

    event StockAdded(address indexed token, uint24 fee, int24 tickSpacing, address hooks);
    event StockRemoved(address indexed token);
    event KeeperSet(address indexed keeper, bool on);
    event DistributorSet(address indexed distributor);
    event StocksBought(uint256 ethSpent, uint256 stockCount);
    event ProtocolFeeSet(address indexed recipient, uint256 bps);
    event ProtocolFeeSent(address indexed recipient, uint256 amount);

    error OnlyKeeper();
    error OnlyPoolManager();
    error NoStocks();
    error NothingToSpend();
    error LengthMismatch();
    error Slippage(uint256 i, uint256 out, uint256 minOut);
    error ZeroAddress();
    error FeeTooHigh();

    constructor(IPoolManager _pm, address owner_) Ownable(owner_) {
        poolManager = _pm;
    }

    function setDistributor(address d) external onlyOwner {
        if (d == address(0)) revert ZeroAddress();
        distributor = d;
        emit DistributorSet(d);
    }

    function setKeeper(address k, bool on) external onlyOwner {
        if (k == address(0)) revert ZeroAddress();
        keeper[k] = on;
        emit KeeperSet(k, on);
    }

    // ── Protocol fee — called by StreamFactory after deploy ───────────────
    function setProtocolFee(address recipient, uint256 bps) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        if (bps > 1000) revert FeeTooHigh(); // max 10%
        protocolFeeRecipient = recipient;
        protocolFeeBps = bps;
        emit ProtocolFeeSet(recipient, bps);
    }

    function addStock(
        address token,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) external onlyOwner {
        stocks.push(Stock(token, fee, tickSpacing, hooks));
        emit StockAdded(token, fee, tickSpacing, hooks);
    }

    function removeStock(uint256 i) external onlyOwner {
        emit StockRemoved(stocks[i].token);
        stocks[i] = stocks[stocks.length - 1];
        stocks.pop();
    }

    function stocksLength() external view returns (uint256) {
        return stocks.length;
    }

    function stockTokenAt(uint256 i) external view returns (address) {
        return stocks[i].token;
    }

    /// @notice Buy each registered stock with an equal slice of held ETH.
    /// @param minOuts Minimum token units received per stock (slippage protection).
    function buyStocks(uint256[] calldata minOuts) external {
        if (!keeper[msg.sender] && msg.sender != owner()) revert OnlyKeeper();
        uint256 n = stocks.length;
        if (n == 0) revert NoStocks();
        if (minOuts.length != n) revert LengthMismatch();

        uint256 balance = address(this).balance;
        if (balance == 0) revert NothingToSpend();

        // ── Deduct protocol fee before buying stocks ───────────────────────
        uint256 ethToSpend = balance;
        if (protocolFeeBps > 0 && protocolFeeRecipient != address(0)) {
            uint256 feeAmount = (balance * protocolFeeBps) / 10000;
            if (feeAmount > 0) {
                ethToSpend = balance - feeAmount;
                (bool ok, ) = protocolFeeRecipient.call{value: feeAmount}("");
                if (ok) emit ProtocolFeeSent(protocolFeeRecipient, feeAmount);
            }
        }

        uint256 per = ethToSpend / n;
        if (per == 0) revert NothingToSpend();

        poolManager.unlock(abi.encode(per, minOuts));
        emit StocksBought(per * n, n);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != address(poolManager)) revert OnlyPoolManager();
        (uint256 per, uint256[] memory minOuts) = abi.decode(data, (uint256, uint256[]));

        for (uint256 i; i < stocks.length; ++i) {
            Stock memory s = stocks[i];
            PoolKey memory key = PoolKey({
                currency0: Currency.wrap(address(0)),
                currency1: Currency.wrap(s.token),
                fee: s.fee,
                tickSpacing: s.tickSpacing,
                hooks: IHooks(s.hooks)
            });
            BalanceDelta delta = poolManager.swap(
                key,
                SwapParams({
                    zeroForOne: true,
                    amountSpecified: -int256(per),
                    sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
                }),
                ""
            );
            uint256 out = uint256(uint128(delta.amount1()));
            if (out < minOuts[i]) revert Slippage(i, out, minOuts[i]);
            poolManager.settle{value: per}();
            poolManager.take(Currency.wrap(s.token), distributor, out);
        }
        return "";
    }

    receive() external payable {}
}