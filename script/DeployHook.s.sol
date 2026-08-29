// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {FlowStockFeeHook} from "../src/FlowStockFeeHook.sol";

contract DeployHook is Script {

    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant TREASURY     = 0x27e94FB5c717FAB6300197A9dfBdf109268dbda8;

    // Hook address: 0xb77e331d3388C65daE62af1db5D2b50B0F0000cc
    bytes32 constant HOOK_SALT = bytes32(uint256(29221));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deploying StockStream Hook...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        FlowStockFeeHook hook = new FlowStockFeeHook{salt: HOOK_SALT}(
            IPoolManager(POOL_MANAGER),
            TREASURY
        );
        console.log("Hook deployed:", address(hook));

        vm.stopBroadcast();

        console.log("\n=== Step 2 Complete ===");
        console.log("Hook: ", address(hook));
        console.log("Now run Wire.s.sol");
    }
}