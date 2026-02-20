// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Enum} from "../libraries/Enum.sol";
import {BaseGuard} from "../utils/BaseGuard.sol";

/**
 * @title EcoAccountsGuard
 * @notice Guard that prevents removing the EcoAccountsModule or changing the guard
 */
contract EcoAccountsGuard is BaseGuard {
    /// @dev setGuard(address) selector
    bytes4 private constant SET_GUARD_SELECTOR = 0xe19a9dd9;
    /// @dev disableModule(address,address) selector
    bytes4 private constant DISABLE_MODULE_SELECTOR = 0xe009cfde;

    /// @notice The EcoAccountsModule address that cannot be removed
    address public immutable ecoAccountsModule;

    error CannotChangeGuard();
    error CannotRemoveEcoAccountsModule();

    constructor(address _ecoAccountsModule) {
        ecoAccountsModule = _ecoAccountsModule;
    }

    fallback() external {
        // Don't revert on fallback to avoid issues if Safe upgrades
    }

    /**
     * @notice Called by the Safe before a transaction is executed
     * @dev Reverts if trying to setGuard or disable the EcoAccountsModule
     */
    function checkTransaction(
        address,
        uint256,
        bytes memory data,
        Enum.Operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external view override {
        if (data.length < 4) return;

        bytes4 selector;
        assembly {
            selector := mload(add(data, 0x20))
        }

        if (selector == SET_GUARD_SELECTOR) {
            revert CannotChangeGuard();
        }

        if (selector == DISABLE_MODULE_SELECTOR) {
            // disableModule(address prevModule, address module)
            // module is at offset 36 (4 selector + 32 prevModule)
            address moduleToRemove;
            assembly {
                moduleToRemove := mload(add(data, 0x44))
            }
            if (moduleToRemove == ecoAccountsModule) {
                revert CannotRemoveEcoAccountsModule();
            }
        }
    }

    function checkModuleTransaction(
        address,
        uint256,
        bytes memory,
        Enum.Operation,
        address
    ) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function checkAfterModuleExecution(bytes32, bool) external override {}

    function checkAfterExecution(bytes32, bool) external view override {}
}
