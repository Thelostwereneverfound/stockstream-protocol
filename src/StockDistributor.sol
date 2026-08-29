// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IFlowStockToken {
    function holderCount() external view returns (uint256);
    function holderAt(uint256 i) external view returns (address);
    function balanceOf(address a) external view returns (uint256);
}

/// @title StockDistributor
/// @notice Receives stock tokens from StockTreasury and distributes them
/// pro-rata to FLST holders every cycle. Keeper-gated snapshot and payout
/// prevents flash-loan weight inflation.
contract StockDistributor is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ── constants ──────────────────────────────────────────────────────────
    uint256 public constant DISTRIBUTION_INTERVAL = 15 minutes;

    // ── immutables ─────────────────────────────────────────────────────────
    IFlowStockToken public immutable flowStockToken;

    // ── config ─────────────────────────────────────────────────────────────
    mapping(address => bool) public keeper;

    struct Stock {
        address token;
    }

    Stock[] public stocks;
    mapping(address => bool) public isStock;

    // ── snapshot state ─────────────────────────────────────────────────────
    // Packed: (balance << 160) | uint160(holder)
    uint256[] private _snap;
    address[] private _cycleStocks;
    uint256[] private _cyclePots;
    uint256 public eligible;
    uint256 public cursor;
    bool public cycleActive;
    uint256 public nextDistribution;
    uint256 public snapCount;
    bool public snapPending;
    mapping(address => uint256) private _seenEpoch;
    uint256 private _snapEpoch;

    // ── events ─────────────────────────────────────────────────────────────
    event KeeperSet(address indexed keeper, bool on);
    event StockAdded(address indexed token);
    event StockRemoved(address indexed token);
    event HoldersSnapshotted(uint256 snapCount, uint256 holderCount);
    event CycleStarted(uint256 holders, uint256 eligible, uint256 stocks);
    event BatchPaid(uint256 from, uint256 to);
    event CycleCompleted(uint256 holders);
    event PayoutSkipped(address indexed stock, address indexed holder, uint256 amount);
    event CycleAborted(uint256 cursor, uint256 holders);
    event ForeignSwept(address indexed token, address indexed to, uint256 amount);

    // ── errors ─────────────────────────────────────────────────────────────
    error OnlyKeeper();
    error CycleInProgress();
    error NoCycle();
    error TooEarly();
    error NoStocks();
    error NoEligibleHolders();
    error NoDistributionPot();
    error SnapshotIncomplete();
    error InvalidBatchSize();
    error ZeroAddress();
    error NotSweepable();

    modifier onlyKeeper() {
        if (!keeper[msg.sender] && msg.sender != owner()) revert OnlyKeeper();
        _;
    }

    constructor(address flowStockToken_, address owner_) Ownable(owner_) {
        if (flowStockToken_ == address(0)) revert ZeroAddress();
        flowStockToken = IFlowStockToken(flowStockToken_);
    }

    // ── owner config ───────────────────────────────────────────────────────

    function setKeeper(address k, bool on) external onlyOwner {
        if (k == address(0)) revert ZeroAddress();
        keeper[k] = on;
        emit KeeperSet(k, on);
    }

    function addStock(address token) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (isStock[token]) return;
        stocks.push(Stock(token));
        isStock[token] = true;
        emit StockAdded(token);
    }

    function removeStock(uint256 i) external onlyOwner {
        address token = stocks[i].token;
        stocks[i] = stocks[stocks.length - 1];
        stocks.pop();
        isStock[token] = false;
        emit StockRemoved(token);
    }

    function stocksLength() external view returns (uint256) {
        return stocks.length;
    }

    // ── snapshot ───────────────────────────────────────────────────────────

    function snapshotHolders(uint256 count) external nonReentrant onlyKeeper {
        if (cycleActive) revert CycleInProgress();
        if (block.timestamp < nextDistribution) revert TooEarly();
        if (count == 0) revert InvalidBatchSize();

        if (!snapPending) {
            if (!_hasPot()) revert NoDistributionPot();
            delete _snap;
            delete _cycleStocks;
            delete _cyclePots;
            eligible = 0;
            snapCount = 0;
            snapPending = true;
            unchecked { ++_snapEpoch; }
        }

        uint256 epoch = _snapEpoch;
        uint256 n = flowStockToken.holderCount();
        uint256 end = snapCount + count;
        if (end > n) end = n;
        uint256 elig = eligible;

        for (uint256 i = snapCount; i < end; ++i) {
            address h = flowStockToken.holderAt(i);
            if (_seenEpoch[h] == epoch) continue;
            _seenEpoch[h] = epoch;
            uint256 b = flowStockToken.balanceOf(h);
            if (b == 0) continue;
            _snap.push((b << 160) | uint256(uint160(h)));
            elig += b;
        }

        eligible = elig;
        if (end > snapCount) snapCount = end;
        emit HoldersSnapshotted(snapCount, n);
    }

    function snapshotRemaining() external view returns (uint256) {
        uint256 n = flowStockToken.holderCount();
        uint256 done = snapPending ? snapCount : 0;
        return n > done ? n - done : 0;
    }

    // ── cycle ──────────────────────────────────────────────────────────────

    function startCycle() external nonReentrant onlyKeeper {
        if (cycleActive) revert CycleInProgress();
        if (block.timestamp < nextDistribution) revert TooEarly();

        if (snapPending) {
            if (snapCount < flowStockToken.holderCount()) revert SnapshotIncomplete();
            snapPending = false;
        } else {
            if (!_hasPot()) revert NoDistributionPot();
            delete _snap;
            uint256 n = flowStockToken.holderCount();
            uint256 elig;
            for (uint256 i; i < n; ++i) {
                address h = flowStockToken.holderAt(i);
                uint256 b = flowStockToken.balanceOf(h);
                if (b == 0) continue;
                _snap.push((b << 160) | uint256(uint160(h)));
                elig += b;
            }
            eligible = elig;
        }

        if (eligible == 0) revert NoEligibleHolders();

        delete _cycleStocks;
        delete _cyclePots;
        uint256 m = stocks.length;
        uint256 totalPot;
        for (uint256 k; k < m; ++k) {
            address tok = stocks[k].token;
            uint256 pot = _safeBalanceOf(tok);
            _cycleStocks.push(tok);
            _cyclePots.push(pot);
            totalPot += pot;
        }
        if (totalPot == 0) revert NoDistributionPot();

        nextDistribution = block.timestamp + DISTRIBUTION_INTERVAL;
        cursor = 0;
        cycleActive = true;
        emit CycleStarted(_snap.length, eligible, m);
    }

    function distributeBatch(uint256 count) external nonReentrant onlyKeeper {
        if (!cycleActive) revert NoCycle();
        if (count == 0) revert InvalidBatchSize();

        uint256 n = _snap.length;
        uint256 end = cursor + count;
        if (end > n) end = n;

        uint256 elig = eligible;
        address[] memory stockArr = _cycleStocks;
        uint256[] memory pots = _cyclePots;
        uint256 m = stockArr.length;
        IFlowStockToken idxT = flowStockToken;

        for (uint256 i = cursor; i < end;) {
            uint256 word = _snap[i];
            uint256 b = word >> 160;
            if (b != 0) {
                address h = address(uint160(word));
                // Flash-loan guard: pay on smaller of snapshot and live balance
                uint256 live = idxT.balanceOf(h);
                uint256 w = live < b ? live : b;
                if (w != 0) {
                    for (uint256 k; k < m;) {
                        uint256 amt = (pots[k] * w) / elig;
                        if (amt != 0) {
                            _trySend(stockArr[k], h, amt);
                        }
                        unchecked { ++k; }
                    }
                }
            }
            unchecked { ++i; }
        }

        emit BatchPaid(cursor, end);
        cursor = end;

        if (end == n) {
            cycleActive = false;
            emit CycleCompleted(n);
        }
    }

    function abortCycle() external onlyOwner {
        uint256 hadCursor = cursor;
        uint256 hadHolders = _snap.length;
        delete _snap;
        delete _cycleStocks;
        delete _cyclePots;
        eligible = 0;
        snapCount = 0;
        snapPending = false;
        cursor = 0;
        cycleActive = false;
        emit CycleAborted(hadCursor, hadHolders);
    }

    // ── emergency ──────────────────────────────────────────────────────────

    function sweepForeign(address token, address to) external onlyOwner {
        if (isStock[token]) revert NotSweepable();
        uint256 bal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(to, bal);
        emit ForeignSwept(token, to, bal);
    }

    // ── views ──────────────────────────────────────────────────────────────

    function canStart() external view returns (bool) {
        return !cycleActive && block.timestamp >= nextDistribution;
    }

    function remaining() external view returns (uint256) {
        return cycleActive ? _snap.length - cursor : 0;
    }

    // ── internal ───────────────────────────────────────────────────────────

    function _hasPot() private view returns (bool) {
        uint256 m = stocks.length;
        for (uint256 k; k < m; ++k) {
            if (_safeBalanceOf(stocks[k].token) > 0) return true;
        }
        return false;
    }

    function _safeBalanceOf(address token) private view returns (uint256 bal) {
        bytes memory payload = abi.encodeCall(IERC20.balanceOf, (address(this)));
        assembly {
            let ok := staticcall(gas(), token, add(payload, 0x20), mload(payload), 0x00, 0x20)
            if and(ok, iszero(lt(returndatasize(), 32))) { bal := mload(0x00) }
        }
    }

    function _trySend(address token, address to, uint256 amt) private returns (bool paid) {
        bytes memory payload = abi.encodeCall(IERC20.transfer, (to, amt));
        assembly {
            let ok := call(gas(), token, 0, add(payload, 0x20), mload(payload), 0x00, 0x20)
            let rds := returndatasize()
            paid := and(ok, or(iszero(rds), and(iszero(lt(rds, 32)), iszero(iszero(mload(0x00))))))
        }
        if (!paid) emit PayoutSkipped(token, to, amt);
    }
}