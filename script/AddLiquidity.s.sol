// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Actions} from "v4-periphery/src/libraries/Actions.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}

contract AddLiquidity is Script {

    address constant POSITION_MANAGER = 0x58daec3116aae6D93017bAAea7749052E8a04fA7;
    address constant STREAM_TOKEN     = 0x0E10991577e5F1C88998520D1e3c208816D9FC46;
    address constant HOOK             = 0xb77e331d3388C65daE62af1db5D2b50B0F0000cc;
    address constant PERMIT2          = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint24 constant LP_FEE       = 10000;
    int24  constant TICK_SPACING = 200;
    int24  constant TICK_LOWER   = -887200;
    int24  constant TICK_UPPER   = 887200;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Adding liquidity to ETH/STREAM pool...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // Step 1: Approve STREAM to Permit2
        IERC20(STREAM_TOKEN).approve(PERMIT2, type(uint256).max);

        // Step 2: Approve Permit2 to PositionManager
        IPermit2(PERMIT2).approve(
            STREAM_TOKEN,
            POSITION_MANAGER,
            type(uint160).max,
            type(uint48).max
        );

        uint256 ethAmount = 0.005 ether;

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(STREAM_TOKEN),
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(HOOK)
        });

        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR)
        );

        bytes[] memory params = new bytes[](2);

        params[0] = abi.encode(
            key,
            TICK_LOWER,
            TICK_UPPER,
            100,               // small liquidity for testing
            type(uint128).max, // max STREAM
            type(uint128).max, // max ETH
            deployer,
            bytes("")
        );

        params[1] = abi.encode(
            Currency.wrap(address(0)),
            Currency.wrap(STREAM_TOKEN)
        );

        IPositionManager(POSITION_MANAGER).modifyLiquidities{value: ethAmount}(
            abi.encode(actions, params),
            block.timestamp + 60
        );

        console.log("Liquidity added successfully!");

        vm.stopBroadcast();

        console.log("=== Liquidity Added ===");
        console.log("Token:", STREAM_TOKEN);
        console.log("Hook: ", HOOK);
        console.log("Pool is ready for trading!");
    }
}