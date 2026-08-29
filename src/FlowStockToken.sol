// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract FlowStockToken is ERC20, Ownable {

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000e18;
    uint256 public minShareBalance = 10_000e18;

    mapping(address => bool) public rewardsExcluded;

    address[] private _holders;
    mapping(address => uint256) private _holderIdx;

    event MinShareBalanceSet(uint256 previous, uint256 current);
    event RewardsExcludedSet(address indexed account, bool excluded);
    event HolderAdded(address indexed account);
    event HolderRemoved(address indexed account);

    error ZeroAddress();

    constructor(address poolManager) ERC20("StockStream", "STREAM") Ownable(msg.sender) {
        if (poolManager == address(0)) revert ZeroAddress();
        rewardsExcluded[poolManager] = true;
        rewardsExcluded[address(0xdead)] = true;
        rewardsExcluded[address(0)] = true;
        _mint(msg.sender, TOTAL_SUPPLY);
    }

    function setMinShareBalance(uint256 v) external onlyOwner {
        emit MinShareBalanceSet(minShareBalance, v);
        minShareBalance = v;
    }

    function setRewardsExcluded(address a, bool on) external onlyOwner {
        if (a == address(0)) revert ZeroAddress();
        rewardsExcluded[a] = on;
        uint256 idx = _holderIdx[a];
        if (on && idx != 0) _removeHolder(a, idx);
        emit RewardsExcludedSet(a, on);
    }

    function holderCount() external view returns (uint256) {
        return _holders.length;
    }

    function holderAt(uint256 i) external view returns (address) {
        return _holders[i];
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (from != address(0)) _refreshHolder(from);
        if (to != address(0) && to != from) _refreshHolder(to);
    }

    function _refreshHolder(address a) private {
        if (rewardsExcluded[a]) return;
        uint256 idx = _holderIdx[a];
        if (balanceOf(a) >= minShareBalance) {
            if (idx == 0) {
                _holders.push(a);
                _holderIdx[a] = _holders.length;
                emit HolderAdded(a);
            }
        } else if (idx != 0) {
            _removeHolder(a, idx);
        }
    }

    function _removeHolder(address a, uint256 idx) private {
        address last = _holders[_holders.length - 1];
        _holders[idx - 1] = last;
        _holderIdx[last] = idx;
        _holders.pop();
        _holderIdx[a] = 0;
        emit HolderRemoved(a);
    }
}