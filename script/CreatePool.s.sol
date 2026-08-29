// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CreatePool is Script {

    address constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant STREAM_TOKEN = 0x0E10991577e5F1C88998520D1e3c208816D9FC46;
    address constant HOOK          = 0xb77e331d3388C65daE62af1db5D2b50B0F0000cc;

    uint24  constant LP_FEE            = 10000;
    int24   constant TICK_SPACING      = 200;
    uint160 constant INITIAL_SQRT_PRICE = 79228162514264337593543950;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Creating ETH/STREAM pool...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        IERC20(STREAM_TOKEN).approve(POOL_MANAGER, type(uint256).max);

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(STREAM_TOKEN),
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK)
        });

        IPoolManager(POOL_MANAGER).initialize(key, INITIAL_SQRT_PRICE);
        console.log("Pool initialized!");

        vm.stopBroadcast();

        console.log("=== Pool Created ===");
        console.log("ETH/STREAM pool live on testnet!");
        console.log("Token:", STREAM_TOKEN);
        console.log("Hook: ", HOOK);
    }
}