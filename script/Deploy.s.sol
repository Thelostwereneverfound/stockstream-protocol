// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StreamStockToken} from "../src/StreamStockToken.sol";
import {StockTreasury} from "../src/StockTreasury.sol";
import {StockDistributor} from "../src/StockDistributor.sol";

contract Deploy is Script {

    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deploying StockStream protocol...");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerKey);

        StreamStockToken token = new StreamStockToken(POOL_MANAGER);
        console.log("StreamStockToken deployed:", address(token));

        StockTreasury treasury = new StockTreasury(
            IPoolManager(POOL_MANAGER),
            deployer
        );
        console.log("StockTreasury deployed:", address(treasury));

        StockDistributor distributor = new StockDistributor(
            address(token),
            deployer
        );
        console.log("StockDistributor deployed:", address(distributor));

        vm.stopBroadcast();

        console.log("\n=== Step 1 Complete ===");
        console.log("Token:       ", address(token));
        console.log("Treasury:    ", address(treasury));
        console.log("Distributor: ", address(distributor));
        console.log("======================");
        console.log("Now run DeployHook.s.sol then Wire.s.sol");
    }
}