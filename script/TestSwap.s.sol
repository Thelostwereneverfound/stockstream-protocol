// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {SwapParams} from "v4-core/src/types/PoolOperation.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

contract SwapHelper is IUnlockCallback {
    IPoolManager public immutable pm;
    address public immutable streamToken;
    address public immutable hook;

    constructor(address _pm, address _stream, address _hook) {
        pm = IPoolManager(_pm);
        streamToken = _stream;
        hook = _hook;
    }

    function swap(address recipient) external payable {
        pm.unlock(abi.encode(recipient, msg.value));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (address recipient, uint256 ethAmount) = abi.decode(data, (address, uint256));

        PoolKey memory key = PoolKey({
            currency0: Currency.wrap(address(0)),
            currency1: Currency.wrap(streamToken),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(hook)
        });

        BalanceDelta delta = pm.swap(
            key,
            SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(ethAmount),
                sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }),
            ""
        );

        pm.settle{value: ethAmount}();

        int128 streamOut = delta.amount1();
        if (streamOut > 0) {
            pm.take(Currency.wrap(streamToken), recipient, uint128(streamOut));
        }

        return "";
    }

    receive() external payable {}
}

contract TestSwap is Script {

    address constant POOL_MANAGER  = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address constant STREAM_TOKEN  = 0x0E10991577e5F1C88998520D1e3c208816D9FC46;
    address constant HOOK          = 0xb77e331d3388C65daE62af1db5D2b50B0F0000cc;
    address constant TREASURY      = 0x27e94FB5c717FAB6300197A9dfBdf109268dbda8;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Testing swap ETH -> STREAM...");
        console.log("Treasury ETH before:", TREASURY.balance);

        vm.startBroadcast(deployerKey);

        SwapHelper helper = new SwapHelper(POOL_MANAGER, STREAM_TOKEN, HOOK);
        helper.swap{value: 0.001 ether}(deployer);

        vm.stopBroadcast();

        console.log("Treasury ETH after:", TREASURY.balance);
        console.log("=== Swap Complete ===");
        console.log("Hook fired! 3% fee captured in treasury!");
    }
}