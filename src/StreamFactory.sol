// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StreamStockFeeHook} from "./StreamStockFeeHook.sol";
import {StockTreasury} from "./StockTreasury.sol";
import {StockDistributor} from "./StockDistributor.sol";

/// @title StreamFactory
/// @notice Deploys a complete tokenized stock distribution system for any token
/// on Robinhood Chain in one transaction. 0.5% of all distributions flow to
/// the $STREAM treasury.
contract StreamFactory is Ownable {

    // ── Immutables ───────────────────────────────────────────────────────────
    IPoolManager public immutable poolManager;
    address public immutable streamTreasury; // $STREAM treasury receives 0.5%

    // ── Constants ────────────────────────────────────────────────────────────
    uint256 public constant PROTOCOL_FEE_BPS       = 50;   // 0.5%
    uint24  public constant DEFAULT_STOCK_FEE       = 3000; // 0.3% V4 pool fee
    int24   public constant DEFAULT_STOCK_TICK_SPACING = 60;

    // ── Deployment registry ──────────────────────────────────────────────────
    struct Deployment {
        address token;
        address hook;
        address treasury;
        address distributor;
        address deployer;
        uint256 deployedAt;
    }

    mapping(address => Deployment) public deployments; // token => deployment
    address[] public allTokens;

    // ── Events ───────────────────────────────────────────────────────────────
    event Deployed(
        address indexed token,
        address indexed hook,
        address indexed treasury,
        address distributor,
        address deployer
    );

    // ── Errors ───────────────────────────────────────────────────────────────
    error ZeroAddress();
    error AlreadyDeployed();
    error NoStocks();

    constructor(
        address poolManager_,
        address streamTreasury_,
        address owner_
    ) Ownable(owner_) {
        if (poolManager_    == address(0)) revert ZeroAddress();
        if (streamTreasury_ == address(0)) revert ZeroAddress();
        poolManager    = IPoolManager(poolManager_);
        streamTreasury = streamTreasury_;
    }

    /// @notice Deploy a complete distribution system for any token.
    /// @param token     The token whose holders will earn tokenized stocks.
    /// @param stocks    Stock token addresses to distribute.
    /// @param hookSalt  Pre-mined CREATE2 salt for hook deployment.
    ///                  Mine using StreamFactory address as deployer.
    function deploy(
        address token,
        address[] calldata stocks,
        bytes32 hookSalt
    ) external returns (
        address hook,
        address treasury,
        address distributor
    ) {
        if (token == address(0))             revert ZeroAddress();
        if (stocks.length == 0)              revert NoStocks();
        if (deployments[token].hook != address(0)) revert AlreadyDeployed();

        // Step 1: Deploy treasury (factory owns temporarily)
        StockTreasury _treasury = new StockTreasury(
            poolManager,
            address(this)
        );

        // Step 2: Deploy distributor (factory owns temporarily)
        StockDistributor _distributor = new StockDistributor(
            token,
            address(this)
        );

        // Step 3: Deploy hook with pre-mined CREATE2 salt
        // IMPORTANT: deployer in MineHook must be THIS factory address, not Create2Deployer
        StreamStockFeeHook _hook = new StreamStockFeeHook{salt: hookSalt}(
            poolManager,
            address(_treasury)
        );

        // Step 4: Add stocks to treasury and distributor
        for (uint256 i; i < stocks.length; ++i) {
            _treasury.addStock(
                stocks[i],
                DEFAULT_STOCK_FEE,
                DEFAULT_STOCK_TICK_SPACING,
                address(0) // no hook on stock pools
            );
            _distributor.addStock(stocks[i]);
        }

        // Step 5: Wire contracts together
        _treasury.setDistributor(address(_distributor));
        _treasury.setKeeper(msg.sender, true);
        _distributor.setKeeper(msg.sender, true);

        // Step 6: Set 0.5% protocol fee to $STREAM treasury
        _treasury.setProtocolFee(streamTreasury, PROTOCOL_FEE_BPS);

        // Step 7: Transfer ownership to caller
        _treasury.transferOwnership(msg.sender);
        _distributor.transferOwnership(msg.sender);

        // Step 8: Register deployment
        treasury    = address(_treasury);
        distributor = address(_distributor);
        hook        = address(_hook);

        deployments[token] = Deployment({
            token:       token,
            hook:        hook,
            treasury:    treasury,
            distributor: distributor,
            deployer:    msg.sender,
            deployedAt:  block.timestamp
        });
        allTokens.push(token);

        emit Deployed(token, hook, treasury, distributor, msg.sender);
    }

    // ── Views ────────────────────────────────────────────────────────────────

    function totalDeployments() external view returns (uint256) {
        return allTokens.length;
    }

    function getDeployment(address token) external view returns (Deployment memory) {
        return deployments[token];
    }

    function isDeployed(address token) external view returns (bool) {
        return deployments[token].hook != address(0);
    }
}
