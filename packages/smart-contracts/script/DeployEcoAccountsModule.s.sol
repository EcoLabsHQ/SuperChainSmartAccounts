// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {EcoAccountsModule} from "../src/EcoAccountsModule.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployEcoAccountsModule
 * @notice Deploys EcoAccountsModule using CREATE2 for deterministic addresses across chains
 * @dev Uses Foundry's native CREATE2 syntax. Same deployer + same salt + same owner = same address
 *
 * Usage:
 *   forge script script/DeployEcoAccountsModule.s.sol:DeployEcoAccountsModule \
 *     --rpc-url <RPC_URL> \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 */
contract DeployEcoAccountsModule is Script {
    /// @dev Salt for CREATE2 deployment - change this to deploy new versions
    bytes32 constant SALT = keccak256("EcoAccountsModule.v1");

    function setUp() public {}

    /**
     * @notice Main deployment function
     * @param owner The owner address for the module
     * @return proxy The address of the deployed proxy
     */
    function run(address owner) public returns (address proxy) {
        vm.startBroadcast();
        proxy = deploy(owner);
        vm.stopBroadcast();

        return proxy;
    }

    /**
     * @notice Core deployment logic using CREATE2
     * @param owner The owner address for the module
     * @return proxyAddress The address of the deployed proxy
     */
    function deploy(address owner) public returns (address proxyAddress) {
        // Deploy implementation with CREATE2
        EcoAccountsModule implementation = new EcoAccountsModule{salt: SALT}();
        console.log("Implementation:", address(implementation));

        // Deploy proxy with CREATE2
        bytes memory initData = abi.encodeCall(EcoAccountsModule.initialize, (owner));
        ERC1967Proxy proxy = new ERC1967Proxy{salt: SALT}(address(implementation), initData);
        
        proxyAddress = address(proxy);
        console.log("Proxy:", proxyAddress);

        return proxyAddress;
    }

    /**
     * @notice Setup initial tier thresholds after deployment
     * @param proxyAddress The proxy address to configure
     */
    function setupTiers(address proxyAddress) public {
        EcoAccountsModule module = EcoAccountsModule(proxyAddress);
        
        uint256[] memory thresholds = new uint256[](10);
        thresholds[0] = 50;
        thresholds[1] = 150;
        thresholds[2] = 400;
        thresholds[3] = 750;
        thresholds[4] = 1250;
        thresholds[5] = 2000;
        thresholds[6] = 3250;
        thresholds[7] = 5000;
        thresholds[8] = 7000;
        thresholds[9] = 10000;
        
        module.addTiersTreshold(thresholds);
        console.log("Tier thresholds configured");
    }

    /**
     * @notice Full deployment with tier setup
     * @param owner The owner address for the module
     * @return proxy The address of the deployed proxy
     */
    function deployAndSetup(address owner) public returns (address proxy) {
        vm.startBroadcast();
        proxy = deploy(owner);
        setupTiers(proxy);
        vm.stopBroadcast();
        return proxy;
    }
}
