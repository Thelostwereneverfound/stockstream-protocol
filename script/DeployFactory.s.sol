// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {StreamFactory} from "../src/StreamFactory.sol";

contract DeployFactory is Script {

    address constant POOL_MANAGER   = 0x8366a39CC670B4001A1121B8F6A443A643e40951;

    // $STREAM treasury — receives 0.5% from all StreamFactory integrations
    address constant STREAM_TREASURY = 0x27e94FB5c717FAB6300197A9dfBdf109268dbda8;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Deploying StreamFactory...");
        console.log("Deployer:", deployer);
        console.log("Pool Manager:", POOL_MANAGER);
        console.log("STREAM Treasury:", STREAM_TREASURY);

        vm.startBroadcast(deployerKey);

        StreamFactory factory = new StreamFactory(
            POOL_MANAGER,
            STREAM_TREASURY,
            deployer
        );

        vm.stopBroadcast();

        console.log("\n=== StreamFactory Deployed ===");
        console.log("StreamFactory:", address(factory));
        console.log("Protocol fee recipient:", STREAM_TREASURY);
        console.log("Protocol fee: 0.5%");
        console.log("==============================");
    }
}