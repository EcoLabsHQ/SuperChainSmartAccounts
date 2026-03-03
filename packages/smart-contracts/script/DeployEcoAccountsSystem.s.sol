// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {EcoAccountsModule} from "../src/EcoAccountsModule.sol";
import {EcoAccountsBadges} from "../src/EcoAccountsBadges.sol";
import {EcoAccountsGuard} from "../src/EcoAccountsGuard.sol";
import {
    ERC1967Proxy
} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployEcoAccountsSystem
 * @notice Deploys the complete EcoAccounts system with deterministic addresses
 * @dev Deploys: EcoAccountsModule, EcoAccountsBadges, EcoAccountsGuard
 *      Links them together and configures tier thresholds
 *
 * Usage:
 *   forge script script/DeployEcoAccountsSystem.s.sol:DeployEcoAccountsSystem \
 *     --rpc-url <RPC_URL> \
 *     --broadcast \
 *     --verify \
 *     -vvvv
 */
contract DeployEcoAccountsSystem is Script {
    /*//////////////////////////////////////////////////////////////
                              SALTS
    //////////////////////////////////////////////////////////////*/

    string constant VERSION = "v1.0.5";

    bytes32 constant MODULE_IMPL_SALT =
        keccak256(abi.encodePacked("EcoAccountsModule.impl.", VERSION));
    bytes32 constant MODULE_PROXY_SALT =
        keccak256(abi.encodePacked("EcoAccountsModule.proxy.", VERSION));
    bytes32 constant BADGES_IMPL_SALT =
        keccak256(abi.encodePacked("EcoAccountsBadges.impl.", VERSION));
    bytes32 constant BADGES_PROXY_SALT =
        keccak256(abi.encodePacked("EcoAccountsBadges.proxy.", VERSION));
    bytes32 constant GUARD_SALT =
        keccak256(abi.encodePacked("EcoAccountsGuard.", VERSION));

    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT RESULTS
    //////////////////////////////////////////////////////////////*/

    struct DeploymentResult {
        address moduleImpl;
        address moduleProxy;
        address badgesImpl;
        address badgesProxy;
        address guard;
    }

    /*//////////////////////////////////////////////////////////////
                          MAIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function setUp() public {}

    /**
     * @notice Full deployment with all configurations
     * @return result The deployed contract addresses
     */
    function run() public returns (DeploymentResult memory result) {
        address owner = msg.sender;
        vm.startBroadcast();
        result = deployAll(owner);
        configureAll(result);
        setupTiers(result.moduleProxy);
        vm.stopBroadcast();

        _logDeployment(result);
        return result;
    }

    /**
     * @notice Deploy all contracts without configuration (for testing)
     * @param owner The owner address for all contracts
     * @return result The deployed contract addresses
     */
    function deployAll(
        address owner
    ) public returns (DeploymentResult memory result) {
        // 1. Deploy EcoAccountsModule
        (result.moduleImpl, result.moduleProxy) = deployModule(owner);

        // 2. Deploy EcoAccountsBadges
        (result.badgesImpl, result.badgesProxy) = deployBadges(owner);

        // 3. Deploy EcoAccountsGuard (needs module address)
        result.guard = deployGuard(result.moduleProxy);

        return result;
    }

    /**
     * @notice Configure all contract links
     * @param result The deployment result with addresses
     */
    function configureAll(DeploymentResult memory result) public {
        // Link Module -> Badges
        EcoAccountsModule(result.moduleProxy).setBadgesContract(
            result.badgesProxy
        );
        console.log("Module linked to Badges");

        // Link Badges -> Module
        EcoAccountsBadges(result.badgesProxy).setEcoAccountsModule(
            result.moduleProxy
        );
        console.log("Badges linked to Module");
    }

    /*//////////////////////////////////////////////////////////////
                        INDIVIDUAL DEPLOYMENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deploy EcoAccountsModule with proxy
     * @param owner The owner address
     * @return impl Implementation address
     * @return proxy Proxy address
     */
    function deployModule(
        address owner
    ) public returns (address impl, address proxy) {
        // Deploy implementation
        EcoAccountsModule implementation = new EcoAccountsModule{
            salt: MODULE_IMPL_SALT
        }();
        impl = address(implementation);
        console.log("EcoAccountsModule Implementation:", impl);

        // Deploy proxy
        bytes memory initData = abi.encodeCall(
            EcoAccountsModule.initialize,
            (owner)
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy{salt: MODULE_PROXY_SALT}(
            impl,
            initData
        );
        proxy = address(proxyContract);
        console.log("EcoAccountsModule Proxy:", proxy);

        return (impl, proxy);
    }

    /**
     * @notice Deploy EcoAccountsBadges with proxy
     * @param owner The owner address
     * @return impl Implementation address
     * @return proxy Proxy address
     */
    function deployBadges(
        address owner
    ) public returns (address impl, address proxy) {
        // Deploy implementation
        EcoAccountsBadges implementation = new EcoAccountsBadges{
            salt: BADGES_IMPL_SALT
        }();
        impl = address(implementation);
        console.log("EcoAccountsBadges Implementation:", impl);

        // Deploy proxy
        bytes memory initData = abi.encodeCall(
            EcoAccountsBadges.initialize,
            (owner)
        );
        ERC1967Proxy proxyContract = new ERC1967Proxy{salt: BADGES_PROXY_SALT}(
            impl,
            initData
        );
        proxy = address(proxyContract);
        console.log("EcoAccountsBadges Proxy:", proxy);

        return (impl, proxy);
    }

    /**
     * @notice Deploy EcoAccountsGuard
     * @param moduleProxy The EcoAccountsModule proxy address
     * @return guard The guard address
     */
    function deployGuard(address moduleProxy) public returns (address guard) {
        EcoAccountsGuard guardContract = new EcoAccountsGuard{salt: GUARD_SALT}(
            moduleProxy
        );
        guard = address(guardContract);
        console.log("EcoAccountsGuard:", guard);
        return guard;
    }

    /*//////////////////////////////////////////////////////////////
                          CONFIGURATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Setup tier thresholds on the module
     * @param moduleProxy The module proxy address
     */
    function setupTiers(address moduleProxy) public {
        EcoAccountsModule module = EcoAccountsModule(moduleProxy);

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
        console.log("Tier thresholds configured (10 levels)");
    }

    /*//////////////////////////////////////////////////////////////
                            HELPERS
    //////////////////////////////////////////////////////////////*/

    function _logDeployment(DeploymentResult memory result) internal pure {
        console.log("");
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("");
        console.log("EcoAccountsModule:");
        console.log("  Implementation:", result.moduleImpl);
        console.log("  Proxy:", result.moduleProxy);
        console.log("");
        console.log("EcoAccountsBadges:");
        console.log("  Implementation:", result.badgesImpl);
        console.log("  Proxy:", result.badgesProxy);
        console.log("");
        console.log("EcoAccountsGuard:", result.guard);
        console.log("");
        console.log("All contracts linked and configured!");
    }
}
