// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {StreamStockFeeHook} from "../src/StreamStockFeeHook.sol";

/// @notice Mines a CREATE2 salt that gives StreamStockFeeHook an address ending in 0xCC.
/// @dev    Run ONCE after treasury is deployed. NEVER deploy hook in same script as other contracts.
///
/// FOR $STREAM HOOK (mainnet deploy):
///   DEPLOYER = Create2Deployer = 0x4e59b44847b379578588920cA78FbF26c0B4956C
///   TREASURY = address from Deploy.s.sol output
///
/// FOR STREAMFACTORY HOOK:
///   DEPLOYER = StreamFactory address (factory deploys the hook, not Create2Deployer)
///   TREASURY = cast compute-address --nonce 1 <FACTORY_ADDRESS>
contract MineHook is Script {

    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    // ⚠️ UPDATE THESE BEFORE EACH RUN ⚠️
    // For $STREAM mainnet: DEPLOYER = Create2Deployer, TREASURY = from Deploy.s.sol
    // For StreamFactory:   DEPLOYER = factory address, TREASURY = predicted treasury
    address constant DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C; // Create2Deployer (for $STREAM)
    address constant TREASURY = address(0); // ← FILL THIS after Deploy.s.sol runs

    uint160 constant REQUIRED_FLAGS = 204; // 0xCC = beforeSwap + afterSwap + beforeSwapReturnDelta + afterSwapReturnDelta

    function run() external view {
        require(TREASURY != address(0), "MineHook: TREASURY not set");

        console.log("Mining StreamStockFeeHook address...");
        console.log("Deployer:", DEPLOYER);
        console.log("Treasury:", TREASURY);
        console.log("Required flags (0xCC):", REQUIRED_FLAGS);

        bytes memory creationCode = abi.encodePacked(
            type(StreamStockFeeHook).creationCode,
            abi.encode(IPoolManager(POOL_MANAGER), TREASURY)
        );
        bytes32 creationCodeHash = keccak256(creationCode);

        uint256 nonce = 0;
        while (true) {
            bytes32 salt        = bytes32(nonce);
            address hookAddress = _computeCreate2Address(DEPLOYER, salt, creationCodeHash);

            if (uint160(hookAddress) & 0xFFFF == REQUIRED_FLAGS) {
                console.log("\n=== SALT FOUND ===");
                console.log("Hook address:", hookAddress);
                console.log("Salt (uint256):", nonce);
                console.log("=================");
                break;
            }
            unchecked { ++nonce; }
        }
    }

    function _computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 creationCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            creationCodeHash
        )))));
    }
}
