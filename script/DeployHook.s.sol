// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StreamStockFeeHook} from "../src/StreamStockFeeHook.sol";

/// @notice Deploys StreamStockFeeHook with the pre-mined CREATE2 salt.
/// @dev    Run AFTER MineHook.s.sol. Update HOOK_SALT and TREASURY before running.
///         NEVER deploy hook in same script as other contracts.
contract DeployHook is Script {

    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    // ⚠️ UPDATE THESE BEFORE RUNNING ⚠️
    address constant TREASURY  = address(0);        // ← from Deploy.s.sol output
    bytes32 constant HOOK_SALT = bytes32(uint256(0)); // ← from MineHook.s.sol output

    function run() external {
        require(TREASURY  != address(0),       "DeployHook: TREASURY not set");
        require(HOOK_SALT != bytes32(uint256(0)), "DeployHook: HOOK_SALT not set");

        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);

        console.log("Deploying StreamStockFeeHook...");
        console.log("Deployer:", deployer);
        console.log("Treasury:", TREASURY);
        console.log("Salt:", uint256(HOOK_SALT));

        vm.startBroadcast(deployerKey);

        StreamStockFeeHook hook = new StreamStockFeeHook{salt: HOOK_SALT}(
            IPoolManager(POOL_MANAGER),
            TREASURY
        );

        vm.stopBroadcast();

        console.log("\n=== StreamStockFeeHook Deployed ===");
        console.log("Hook address:", address(hook));
        console.log("Treasury:", hook.treasury());
        console.log("Fee BPS:", hook.FEE_BPS());
        console.log("===================================");
    }
}
