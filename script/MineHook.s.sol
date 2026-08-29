// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {FlowStockFeeHook} from "../src/FlowStockFeeHook.sol";

contract MineHook is Script {

    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant TREASURY     = 0x241516118Da99d5B8A854dA129F30268E56622d8;

    // StreamFactory address — this is the actual deployer of the hook
    address constant DEPLOYER     = 0x977e1b69Ca89fB9F33e56f1AcAa18Ed409FDb643;

    uint160 constant REQUIRED_FLAGS = 204;

    function run() external view {
        console.log("Mining hook address...");
        console.log("Deployer (StreamFactory):", DEPLOYER);
        console.log("Required flags:", REQUIRED_FLAGS);

        bytes memory creationCode = abi.encodePacked(
            type(FlowStockFeeHook).creationCode,
            abi.encode(IPoolManager(POOL_MANAGER), TREASURY)
        );
        bytes32 creationCodeHash = keccak256(creationCode);

        uint256 nonce = 0;
        while (true) {
            bytes32 salt = bytes32(nonce);
            address hookAddress = _computeCreate2Address(DEPLOYER, salt, creationCodeHash);

            if (uint160(hookAddress) & 0xFFFF == REQUIRED_FLAGS) {
                console.log("Found hook address:", hookAddress);
                console.log("Salt:", nonce);
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