// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {DAODeployer} from "../src/factories/DAODeployer.sol";
import {GovernorRegistry} from "../src/factories/GovernorRegistry.sol";
import {DAOTokenFactory} from "../src/factories/DAOTokenFactory.sol";
import {DAORoleConfigurator} from "../src/factories/DAORoleConfigurator.sol";

contract GovernorFactoryScript is Script {
    DAODeployer public governorFactory;
    GovernorRegistry public governorRegistry;
    DAOTokenFactory public tokenFactory;
    DAORoleConfigurator public roleConfigurator;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        governorRegistry = new GovernorRegistry();
        tokenFactory = new DAOTokenFactory();
        roleConfigurator = new DAORoleConfigurator();
        governorFactory = new DAODeployer(address(governorRegistry), address(tokenFactory), address(roleConfigurator));

        vm.stopBroadcast();
    }
}

// forge script script/DeployScript.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast --etherscan-api-key $ETHERSCAN_API_KEY --verify -vvvv
