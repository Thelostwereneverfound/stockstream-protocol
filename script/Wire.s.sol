// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {StockTreasury} from "../src/StockTreasury.sol";
import {StockDistributor} from "../src/StockDistributor.sol";

contract Wire is Script {

    address constant TREASURY    = 0x27e94FB5c717FAB6300197A9dfBdf109268dbda8;
    address constant DISTRIBUTOR = 0x04AFc82D62b0017376d2101F83FeC22A87435481;

    address constant NVDA  = 0xd0601CE157Db5bdC3162BbaC2a2C8aF5320D9EEC;
    address constant AAPL  = 0xaF3D76f1834A1d425780943C99Ea8A608f8a93f9;
    address constant GOOGL = 0x2e0847E8910a9732eB3fb1bb4b70a580ADAD4FE3;
    address constant META  = 0xc0D6457C16Cc70d6790Dd43521C899C87ce02f35;

    uint24 constant STOCK_FEE          = 3000;
    int24  constant STOCK_TICK_SPACING = 60;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console.log("Wiring StockStream...");

        vm.startBroadcast(deployerKey);

        StockTreasury treasury       = StockTreasury(payable(TREASURY));
        StockDistributor distributor = StockDistributor(payable(DISTRIBUTOR));

        treasury.setDistributor(DISTRIBUTOR);
        treasury.setKeeper(deployer, true);
        distributor.setKeeper(deployer, true);

        treasury.addStock(NVDA,  STOCK_FEE, STOCK_TICK_SPACING, address(0));
        treasury.addStock(AAPL,  STOCK_FEE, STOCK_TICK_SPACING, address(0));
        treasury.addStock(GOOGL, STOCK_FEE, STOCK_TICK_SPACING, address(0));
        treasury.addStock(META,  STOCK_FEE, STOCK_TICK_SPACING, address(0));

        distributor.addStock(NVDA);
        distributor.addStock(AAPL);
        distributor.addStock(GOOGL);
        distributor.addStock(META);

        vm.stopBroadcast();

        console.log("Wiring complete!");
        console.log("Treasury:    ", TREASURY);
        console.log("Distributor: ", DISTRIBUTOR);
    }
}