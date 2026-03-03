// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISafe} from "../interfaces/ISafe.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ISuperChainModule.sol";

/**
 * @title EcoAccountsModule
 * @notice Manages eco-friendly accounts tied to Safe wallets with points and level progression
 * @dev UUPS upgradeable module that handles account creation, data source management, and points tracking
 */
contract EcoAccountsModule is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                TYPES
    //////////////////////////////////////////////////////////////*/

    struct Account {
        address safe;
        string superChainID;
        uint256 points;
        uint16 level;
        NounMetadata noun;
    }

    /// @custom:storage-location erc7201:openzeppelin.storage.eco_accounts_module
    struct EcoAccountsStorage {
        /// @dev Address of the EcoAccountBadges contract (only caller for incrementSuperChainPoints)
        address badgesContract;
        /// @dev Tier thresholds for level progression
        uint256[] tierTreshold;
        /// @dev Mapping from Safe address to Account data
        mapping(address safe => Account account) accounts;
        /// @dev Mapping from Safe to its connected data sources
        mapping(address safe => address[] dataSources) safeToDataSources;
        /// @dev Index tracking for efficient data source removal (1-indexed)
        mapping(address safe => mapping(address dataSource => uint256)) dataSourceIndex;
        /// @dev Pending data source invites for each Safe
        mapping(address safe => address[]) safeToDataSourceInvites;
        /// @dev Index tracking for pending invites (1-indexed)
        mapping(address safe => mapping(address owner => uint256)) pendingInviteIndex;
        /// @dev Tracks taken SuperChain IDs
        mapping(bytes32 idHash => bool) isSuperChainIdTaken;
        /// @dev Mapping from Safe to its SuperChain ID
        mapping(address safe => string superChainID) safeToSuperChainID;
        /// @dev Mapping from data source to its original Safe (once bound, cannot be added to another Safe)
        mapping(address dataSource => address originalSafe) dataSourceOriginalSafe;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.eco_accounts_module")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant ECO_ACCOUNTS_MODULE_STORAGE_LOCATION =
        0x7e99e3b7bb5df66cbf7f1a67d0927b69c78bf659395e1b6b65d042a151f12f00;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event EcoAccountCreated(address indexed safe, string superChainID, NounMetadata noun);
    event DataSourceAddRequested(address indexed safe, address indexed dataSource);
    event DataSourceAddRequestRemoved(address indexed safe, address indexed dataSource);
    event DataSourceAdded(address indexed safe, address indexed dataSource, string superChainID);
    event DataSourceRemoved(address indexed safe, address indexed dataSource);
    event TierTresholdAdded(uint256 treshold);
    event TierTresholdUpdated(uint256 index, uint256 newTreshold);
    event PointsIncremented(address indexed recipient, uint256 points, bool levelUp);
    event BadgesContractSet(address indexed badgesContract);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error MaxLvlReached();
    error SuperChainIdAlreadyTaken();
    error InvalidSuperChainIdSuffix();
    error NotSafeOwner();
    error DataSourceAlreadyAdded();
    error DataSourceAlreadyPending();
    error NotDataSource();
    error DataSourceNotPending();
    error DataSourceNotAdded();
    error DataSourceBoundToAnotherSafe();
    error AccountNotFound();
    error IndexOutOfBounds();
    error InvalidThresholdUpdate();
    error ThresholdMustBeHigher();
    error NotBadgesContract();


    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the upgradeable contract
     * @param owner The owner address that will have admin rights
     */
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
    }

    /*//////////////////////////////////////////////////////////////
                          ACCOUNT SETUP
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets up an EcoAccount for a Safe wallet
     * @param _noun The noun metadata for the account avatar
     * @param _superChainID The unique SuperChain identifier (without .superchain suffix)
     */
    function setupEcoAccount(
        NounMetadata calldata _noun,
        string calldata _superChainID
    ) external {
        EcoAccountsStorage storage $ = _getStorage();
        address _safe = msg.sender;

        if ($.isSuperChainIdTaken[keccak256(abi.encode(_superChainID))]) {
            revert SuperChainIdAlreadyTaken();
        }
        if (_isInvalidSuperChainId(_superChainID)) {
            revert InvalidSuperChainIdSuffix();
        }

        $.safeToSuperChainID[_safe] = string.concat(_superChainID, ".superchain");
        $.isSuperChainIdTaken[keccak256(abi.encode(_superChainID))] = true;

        $.accounts[_safe] = Account({
            safe: _safe,
            superChainID: _superChainID,
            points: 0,
            level: 0,
            noun: _noun
        });

        emit EcoAccountCreated(_safe, _superChainID, _noun);
    }

    /*//////////////////////////////////////////////////////////////
                        DATA SOURCE MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Requests to add a data source to a Safe
     * @dev Only Safe owners can request. Creates a pending invite for the data source
     * @param _safe The Safe address
     * @param _newDataSource The data source address to invite
     */
    function requestAddDataSource(address _safe, address _newDataSource) external {
        EcoAccountsStorage storage $ = _getStorage();

        if (!ISafe(_safe).isOwner(msg.sender)) revert NotSafeOwner();
        if (_isDataSourceAdded($, _safe, _newDataSource)) revert DataSourceAlreadyAdded();
        if (_isDataSourcePending($, _safe, _newDataSource)) revert DataSourceAlreadyPending();

        $.safeToDataSourceInvites[_safe].push(_newDataSource);
        $.pendingInviteIndex[_safe][_newDataSource] = $.safeToDataSourceInvites[_safe].length;

        emit DataSourceAddRequested(_safe, _newDataSource);
    }

    /**
     * @notice Accepts a pending data source invite
     * @dev Only the invited data source can accept. Once bound to a Safe, cannot be added to another
     * @param _safe The Safe address that sent the invite
     * @param _dataSource The data source accepting (must be msg.sender)
     */
    function acceptAddDataSourceRequest(address _safe, address _dataSource) external {
        EcoAccountsStorage storage $ = _getStorage();

        if (msg.sender != _dataSource) revert NotDataSource();
        if (!_isDataSourcePending($, _safe, _dataSource)) revert DataSourceNotPending();

        // Check if data source is bound to another Safe
        address originalSafe = $.dataSourceOriginalSafe[_dataSource];
        if (originalSafe != address(0) && originalSafe != _safe) {
            revert DataSourceBoundToAnotherSafe();
        }

        // Bind data source to this Safe permanently (only on first addition)
        if (originalSafe == address(0)) {
            $.dataSourceOriginalSafe[_dataSource] = _safe;
        }

        // Add to active data sources
        $.safeToDataSources[_safe].push(_dataSource);
        $.dataSourceIndex[_safe][_dataSource] = $.safeToDataSources[_safe].length;

        // Remove from pending invites (swap and pop)
        _removePendingInvite($, _safe, _dataSource);

        emit DataSourceAdded(_safe, _dataSource, $.safeToSuperChainID[_safe]);
    }

    /**
     * @notice Removes a pending data source invite
     * @dev Only Safe owners can remove pending invites
     * @param _safe The Safe address
     * @param _dataSource The data source to remove from pending
     */
    function removeAddDataSourceRequest(address _safe, address _dataSource) external {
        EcoAccountsStorage storage $ = _getStorage();

        if (!ISafe(_safe).isOwner(msg.sender)) revert NotSafeOwner();
        if (!_isDataSourcePending($, _safe, _dataSource)) revert DataSourceNotPending();

        _removePendingInvite($, _safe, _dataSource);

        emit DataSourceAddRequestRemoved(_safe, _dataSource);
    }

    /**
     * @notice Removes an active data source from a Safe
     * @dev Only Safe owners can remove data sources
     * @param _safe The Safe address
     * @param _dataSource The data source to remove
     */
    function removeDataSource(address _safe, address _dataSource) external {
        EcoAccountsStorage storage $ = _getStorage();

        if (!ISafe(_safe).isOwner(msg.sender)) revert NotSafeOwner();
        if (!_isDataSourceAdded($, _safe, _dataSource)) revert DataSourceNotAdded();

        _removeDataSource($, _safe, _dataSource);

        emit DataSourceRemoved(_safe, _dataSource);
    }

    /*//////////////////////////////////////////////////////////////
                          POINTS & LEVELS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Increments points for a recipient account
     * @dev Only callable by EcoAccountBadges contract. Updates level if threshold is crossed
     * @param _points The number of points to add
     * @param recipient The Safe address to credit
     * @return levelUp Whether the account leveled up
     */
    function incrementSuperChainPoints(
        uint256 _points,
        address recipient
    ) external returns (bool levelUp) {
        EcoAccountsStorage storage $ = _getStorage();
        if (msg.sender != $.badgesContract) revert NotBadgesContract();
        Account storage _account = $.accounts[recipient];

        if (_account.safe == address(0)) revert AccountNotFound();

        _account.points += _points;
        levelUp = _updateLevel($, _account);

        emit PointsIncremented(recipient, _points, levelUp);
        return levelUp;
    }

    /**
     * @notice Simulates point increment without modifying state
     * @param _points The number of points to simulate adding
     * @param recipient The Safe address to check
     * @return levelUp Whether the account would level up
     */
    function simulateIncrementSuperChainPoints(
        uint256 _points,
        address recipient
    ) external view returns (bool levelUp) {
        EcoAccountsStorage storage $ = _getStorage();
        Account memory _account = $.accounts[recipient];

        if (_account.safe == address(0)) revert AccountNotFound();

        _account.points += _points;

        for (uint16 i = uint16($.tierTreshold.length); i > 0; i--) {
            uint16 index = i - 1;
            if ($.tierTreshold[index] <= _account.points) {
                if (_account.level != index + 1) {
                    levelUp = true;
                }
                break;
            }
        }
        return levelUp;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the EcoAccountBadges contract address
     * @param _badgesContract The badges contract address
     */
    function setBadgesContract(address _badgesContract) external onlyOwner {
        EcoAccountsStorage storage $ = _getStorage();
        $.badgesContract = _badgesContract;
        emit BadgesContractSet(_badgesContract);
    }

    /**
     * @notice Adds multiple tier thresholds
     * @dev Each threshold must be higher than the previous
     * @param _tresholds Array of thresholds to add
     */
    function addTiersTreshold(uint256[] memory _tresholds) external onlyOwner {
        for (uint256 i = 0; i < _tresholds.length; i++) {
            _addTierTreshold(_tresholds[i]);
        }
    }

    /**
     * @notice Updates an existing tier threshold
     * @dev Must maintain ascending order of thresholds
     * @param index The index of the threshold to update
     * @param newThreshold The new threshold value
     */
    function updateTierThreshold(uint256 index, uint256 newThreshold) external onlyOwner {
        EcoAccountsStorage storage $ = _getStorage();

        if (index >= $.tierTreshold.length) revert IndexOutOfBounds();
        if (!((index == 0 || $.tierTreshold[index - 1] < newThreshold) &&
                (index == $.tierTreshold.length - 1 || newThreshold < $.tierTreshold[index + 1]))) {
            revert InvalidThresholdUpdate();
        }

        $.tierTreshold[index] = newThreshold;
        emit TierTresholdUpdated(index, newThreshold);
    }

    /*//////////////////////////////////////////////////////////////
                          VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the account data for a Safe
     * @param _safe The Safe address
     * @return The Account struct
     */
    function getAccount(address _safe) external view returns (Account memory) {
        EcoAccountsStorage storage $ = _getStorage();
        return $.accounts[_safe];
    }

    /**
     * @notice Gets the EcoAccountBadges contract address
     * @return The badges contract address
     */
    function getBadgesContract() external view returns (address) {
        EcoAccountsStorage storage $ = _getStorage();
        return $.badgesContract;
    }

    /**
     * @notice Gets the SuperChain ID for a Safe
     * @param _safe The Safe address
     * @return The SuperChain ID string
     */
    function getSuperChainID(address _safe) external view returns (string memory) {
        EcoAccountsStorage storage $ = _getStorage();
        return $.safeToSuperChainID[_safe];
    }

    /**
     * @notice Gets the active data sources for a Safe
     * @param _safe The Safe address
     * @return Array of data source addresses
     */
    function getDataSources(address _safe) external view returns (address[] memory) {
        EcoAccountsStorage storage $ = _getStorage();
        return $.safeToDataSources[_safe];
    }

    /**
     * @notice Gets the pending data source invites for a Safe
     * @param _safe The Safe address
     * @return Array of pending data source addresses
     */
    function getPendingDataSources(address _safe) external view returns (address[] memory) {
        EcoAccountsStorage storage $ = _getStorage();
        return $.safeToDataSourceInvites[_safe];
    }

    /**
     * @notice Gets the original Safe a data source is bound to
     * @param _dataSource The data source address
     * @return The Safe address (address(0) if not bound)
     */
    function getDataSourceOriginalSafe(address _dataSource) external view returns (address) {
        EcoAccountsStorage storage $ = _getStorage();
        return $.dataSourceOriginalSafe[_dataSource];
    }

    /**
     * @notice Gets the points needed for the next level
     * @param _safe The Safe address
     * @return The threshold for the next level
     */
    function getNextLevelPoints(address _safe) external view returns (uint256) {
        EcoAccountsStorage storage $ = _getStorage();
        if ($.accounts[_safe].level >= $.tierTreshold.length) {
            revert MaxLvlReached();
        }
        return $.tierTreshold[$.accounts[_safe].level];
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the storage pointer for the module
     */
    function _getStorage() internal pure returns (EcoAccountsStorage storage s) {
        bytes32 position = ECO_ACCOUNTS_MODULE_STORAGE_LOCATION;
        assembly {
            s.slot := position
        }
    }

    /**
     * @dev Adds a new tier threshold
     * @param _treshold The threshold value to add
     */
    function _addTierTreshold(uint256 _treshold) internal {
        EcoAccountsStorage storage $ = _getStorage();
        if ($.tierTreshold.length > 0 && $.tierTreshold[$.tierTreshold.length - 1] >= _treshold) {
            revert ThresholdMustBeHigher();
        }
        $.tierTreshold.push(_treshold);
        emit TierTresholdAdded(_treshold);
    }

    /**
     * @dev Updates the account level based on current points
     * @param $ Storage pointer
     * @param _account The account to update
     * @return levelUp Whether the level changed
     */
    function _updateLevel(
        EcoAccountsStorage storage $,
        Account storage _account
    ) internal returns (bool levelUp) {
        for (uint16 i = uint16($.tierTreshold.length); i > 0; i--) {
            uint16 index = i - 1;
            if ($.tierTreshold[index] <= _account.points) {
                if (_account.level != index + 1) {
                    _account.level = index + 1;
                    levelUp = true;
                }
                break;
            }
        }
        return levelUp;
    }

    /**
     * @dev Removes a pending invite using swap and pop
     * @param $ Storage pointer
     * @param _safe The Safe address
     * @param _dataSource The data source to remove
     */
    function _removePendingInvite(
        EcoAccountsStorage storage $,
        address _safe,
        address _dataSource
    ) internal {
        uint256 index = $.pendingInviteIndex[_safe][_dataSource] - 1;
        address lastDataSource = $.safeToDataSourceInvites[_safe][
            $.safeToDataSourceInvites[_safe].length - 1
        ];

        $.safeToDataSourceInvites[_safe][index] = lastDataSource;
        $.pendingInviteIndex[_safe][lastDataSource] = index + 1;

        $.safeToDataSourceInvites[_safe].pop();
        delete $.pendingInviteIndex[_safe][_dataSource];
    }

    /**
     * @dev Removes an active data source using swap and pop
     * @param $ Storage pointer
     * @param _safe The Safe address
     * @param _dataSource The data source to remove
     */
    function _removeDataSource(
        EcoAccountsStorage storage $,
        address _safe,
        address _dataSource
    ) internal {
        uint256 index = $.dataSourceIndex[_safe][_dataSource] - 1;
        address lastDataSource = $.safeToDataSources[_safe][
            $.safeToDataSources[_safe].length - 1
        ];

        $.safeToDataSources[_safe][index] = lastDataSource;
        $.dataSourceIndex[_safe][lastDataSource] = index + 1;

        $.safeToDataSources[_safe].pop();
        delete $.dataSourceIndex[_safe][_dataSource];
    }

    /**
     * @dev Checks if a data source is already added to a Safe
     */
    function _isDataSourceAdded(
        EcoAccountsStorage storage $,
        address _safe,
        address _dataSource
    ) internal view returns (bool) {
        return $.dataSourceIndex[_safe][_dataSource] != 0;
    }

    /**
     * @dev Checks if a data source has a pending invite
     */
    function _isDataSourcePending(
        EcoAccountsStorage storage $,
        address _safe,
        address _dataSource
    ) internal view returns (bool) {
        return $.pendingInviteIndex[_safe][_dataSource] != 0;
    }

    /**
     * @dev Validates that a SuperChain ID doesn't end with ".superchain"
     */
    function _isInvalidSuperChainId(string memory str) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(".superchain");

        if (strBytes.length < suffixBytes.length) {
            return false;
        }

        for (uint i = 0; i < suffixBytes.length; i++) {
            if (strBytes[strBytes.length - suffixBytes.length + i] != suffixBytes[i]) {
                return false;
            }
        }

        return true;
    }

    /**
     * @dev Authorizes contract upgrades (only owner)
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
