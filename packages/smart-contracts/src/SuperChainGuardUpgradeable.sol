// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IGuard} from "../interfaces/IGuard.sol";
import {Enum} from "../libraries/Enum.sol";
import {BaseGuard} from "../utils/BaseGuard.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title SuperChainGuardUpgradeable - A guard contract that prevents unauthorized operations on SuperChain accounts.
 * @dev Prevents adding/removing owners, swapping owners, changing threshold, and setting guard.
 * @custom:oz-upgrades-from SuperChainGuard
 */
contract SuperChainGuardUpgradeable is
    Initializable,
    BaseGuard,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    // Changed from immutable to constant since these are fixed values
    bytes4 private constant ADD_OWNER_WITH_THRESHOLD_SELECTOR = 0x0d582f13;
    bytes4 private constant REMOVE_OWNER_SELECTOR = 0xf8dc5dd9;
    bytes4 private constant SWAP_OWNER_SELECTOR = 0xe318b52b;
    bytes4 private constant CHANGE_THRESHOLD_SELECTOR = 0x694e80c3;
    bytes4 private constant SET_GUARD = 0xe19a9dd9;

    error UnableToAddOwnersToSCSA();
    error UnableToRemoveOwnersFromSCSA();
    error UnableToSwapOwnersInSCSA();
    error UnableToChangeThresholdInSCSA();
    error UnableToSetGuardInSCSA();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the upgradeable contract.
     * @param owner The owner of the contract.
     */
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
    }

    fallback() external {
        // We don't revert on fallback to avoid issues in case of a Safe upgrade
        // E.g. The expected check method might change and then the Safe would be locked.
    }

    /**
     * @notice Called by the Safe contract before a transaction is executed.
     * @dev Reverts if the transaction is related to update treshold owner.
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
        // solhint-disable-next-line no-unused-vars
        address payable,
        bytes memory,
        address
    ) external override {
        if (data.length >= 4) {
            bytes4 selector;
            assembly {
                selector := mload(add(data, 0x20))
            }
            if (selector == ADD_OWNER_WITH_THRESHOLD_SELECTOR) {
                revert UnableToAddOwnersToSCSA();
            }
            if (selector == REMOVE_OWNER_SELECTOR) {
                revert UnableToAddOwnersToSCSA();
            }
            if (selector == SWAP_OWNER_SELECTOR) {
                revert UnableToAddOwnersToSCSA();
            }
            if (selector == CHANGE_THRESHOLD_SELECTOR) {
                revert UnableToAddOwnersToSCSA();
            }
            if (selector == SET_GUARD) {
                revert UnableToSetGuardInSCSA();
            }
        }
    }

    function checkModuleTransaction(
        address,
        uint256,
        bytes memory,
        Enum.Operation,
        address
    ) external override returns (bytes32 moduleTxHash) {}

    /**
     * @notice Called by the Safe contract after a module transaction is executed.
     * @dev No-op.
     */
    function checkAfterModuleExecution(bytes32, bool) external override {}

    /**
     * @notice Called by the Safe contract after a transaction is executed.
     * @dev No-op.
     */
    function checkAfterExecution(bytes32, bool) external view override {}

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
