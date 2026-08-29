// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {StreamFactory} from "../src/StreamFactory.sol";

contract TestFactory is Script {

    address constant FACTORY    = 0x977e1b69Ca89fB9F33e56f1AcAa18Ed409FDb643;
    address constant TEST_TOKEN = 0x0E10991577e5F1C88998520D1e3c208816D9FC46;

    address constant NVDA  = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant AAPL  = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address constant GOOGL = 0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3;
    address constant META  = 0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35;

    // Hook address: 0x0530A83576CCe2AD7F1eb0441d137C58bb2100CC
    bytes32 constant HOOK_SALT = bytes32(uint256(58576));

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Testing StreamFactory.deploy()...");
        console.log("Factory:", FACTORY);
        console.log("Test token:", TEST_TOKEN);
        console.log("Hook salt:", uint256(HOOK_SALT));

        address[] memory stocks = new address[](4);
        stocks[0] = NVDA;
        stocks[1] = AAPL;
        stocks[2] = GOOGL;
        stocks[3] = META;

        vm.startBroadcast(deployerKey);

        (address hook, address treasury, address distributor) = StreamFactory(FACTORY).deploy(
            TEST_TOKEN,
            stocks,
            HOOK_SALT
        );

        vm.stopBroadcast();

        console.log("\n=== StreamFactory Test Complete ===");
        console.log("Hook:        ", hook);
        console.log("Treasury:    ", treasury);
        console.log("Distributor: ", distributor);
        console.log("===================================");
    }
}