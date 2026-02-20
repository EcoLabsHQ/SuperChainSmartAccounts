// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
import {ISafe} from "../interfaces/ISafe.sol";
import {Enum} from "../libraries/Enum.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ISuperChainModule.sol";

contract SuperChainModuleUpgradeable is
    Initializable,
    ISuperChainModule,
    OwnableUpgradeable,
    UUPSUpgradeable
{
    /// @custom:storage-location erc7201:openzeppelin.storage.superchain_module
    struct SuperChainStorage {
        mapping(address => mapping(address => bool)) _isPopulatedAddOwnerWithThreshold;
        mapping(address => address[]) populatedAddOwnersWithTreshold;
        mapping(address => Account) superChainAccount;
        mapping(address => address) userSuperChainAccount;
        mapping(address => bool) hasFirstOwnerYet;
        mapping(string => bool) superChainIDRegistered;
        address _resolver;
        uint256[] _tierTreshold;
    }
    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.superchain_module")) - 1)) & ~bytes32(uint256(0xff));
    bytes32 private constant SUPERCHAIN_MODULE_STORAGE_LOCATION =
        0x0b2be64e6582d1593e5ce87fbed66eec9268226484384723dab2b56b70de0600;

    function superChainStorage()
        private
        pure
        returns (SuperChainStorage storage $)
    {
        assembly {
            $.slot := SUPERCHAIN_MODULE_STORAGE_LOCATION
        }
    }

    function initialize(address resolver, address owner) public initializer {
        __Ownable_init(owner);
        __UUPSUpgradeable_init();
        SuperChainStorage storage s = superChainStorage();
        s._resolver = resolver;
    }

    modifier firstOwnerSet(address _safe) {
        SuperChainStorage storage s = superChainStorage();
        require(s.hasFirstOwnerYet[_safe], "Initial owner not set yet");
        _;
    }

    function addOwnerWithThreshold(
        address _safe,
        address _newOwner
    ) public firstOwnerSet(_safe) {
        SuperChainStorage storage s = superChainStorage();
        require(msg.sender == _newOwner, "Caller is not the new owner");
        require(
            s.userSuperChainAccount[_newOwner] == address(0),
            "Owner already has a SuperChainAccount"
        );
        require(
            s._isPopulatedAddOwnerWithThreshold[_newOwner][_safe],
            "Owner not populated"
        );
        for (
            uint i = 0;
            i < s.populatedAddOwnersWithTreshold[_safe].length;
            i++
        ) {
            if (s.populatedAddOwnersWithTreshold[_safe][i] == _newOwner) {
                s.populatedAddOwnersWithTreshold[_safe][i] = s
                    .populatedAddOwnersWithTreshold[_safe][
                        s.populatedAddOwnersWithTreshold[_safe].length - 1
                    ];
                s.populatedAddOwnersWithTreshold[_safe].pop();
                break;
            }
        }
        bytes memory data = abi.encodeWithSignature(
            "addOwnerWithThreshold(address,uint256)",
            _newOwner,
            1
        );
        bool success = ISafe(_safe).execTransactionFromModule(
            _safe,
            0,
            data,
            Enum.Operation.Call
        );

        require(success, "Failed to add owner");
        s.userSuperChainAccount[_newOwner] = _safe;
        emit OwnerAdded(
            _safe,
            _newOwner,
            s.superChainAccount[_safe].superChainID
        );
    }

    function removePopulateRequest(address _safe, address user) public {
        SuperChainStorage storage s = superChainStorage();
        require(
            s._isPopulatedAddOwnerWithThreshold[user][_safe],
            "Owner not populated"
        );
        require(
            ISafe(_safe).isOwner(msg.sender) ||
                s._isPopulatedAddOwnerWithThreshold[msg.sender][_safe] ||
                msg.sender == _safe,
            "The address is not an owner or the populated user"
        );
        for (
            uint i = 0;
            i < s.populatedAddOwnersWithTreshold[_safe].length;
            i++
        ) {
            if (s.populatedAddOwnersWithTreshold[_safe][i] == user) {
                Account memory _account = s.superChainAccount[_safe];
                s.populatedAddOwnersWithTreshold[_safe][i] = s
                    .populatedAddOwnersWithTreshold[_safe][
                        s.populatedAddOwnersWithTreshold[_safe].length - 1
                    ];
                s.populatedAddOwnersWithTreshold[_safe].pop();
                s._isPopulatedAddOwnerWithThreshold[user][_safe] = false;
                emit OwnerPopulationRemoved(_safe, user, _account.superChainID);
                break;
            }
        }
    }

    function setInitialOwner(
        address _safe,
        address _owner,
        NounMetadata calldata _noun,
        string calldata superChainID
    ) public {
        SuperChainStorage storage s = superChainStorage();
        require(
            s.userSuperChainAccount[_owner] == address(0),
            "Owner already has a SuperChainSmartAccount"
        );
        require(ISafe(_safe).isOwner(_owner), "The address is not an owner");
        require(
            msg.sender == _safe,
            "Caller is not the SuperChainSmartAccount"
        );
        require(
            !s.hasFirstOwnerYet[_safe],
            "SuperChainSmartAccount already has owners"
        );
        require(
            ISafe(_safe).getOwners().length == 1,
            "SuperChainSmartAccount already has owners"
        );
        require(
            !_isInvalidSuperChainId(superChainID),
            "The last 11 characters cannot be '.superchain'"
        );
        require(
            !s.superChainIDRegistered[superChainID],
            "The superchain ID was registered yet."
        );
        s.superChainAccount[_safe].smartAccount = _safe;
        s.userSuperChainAccount[_owner] = _safe;
        s.superChainAccount[_safe].superChainID = string.concat(
            superChainID,
            ".superchain"
        );
        s.superChainIDRegistered[superChainID] = true;
        s.hasFirstOwnerYet[_safe] = true;
        s.superChainAccount[_safe].noun = _noun;
        emit OwnerAdded(_safe, _owner, s.superChainAccount[_safe].superChainID);
        emit SuperChainSmartAccountCreated(
            _safe,
            _owner,
            s.superChainAccount[_safe].superChainID,
            _noun
        );
    }

    function populateAddOwner(
        address _safe,
        address _newOwner
    ) public firstOwnerSet(_safe) {
        SuperChainStorage storage s = superChainStorage();
        require(
            msg.sender == _safe,
            "Caller is not the SuperChainSmartAccount"
        );
        require(!ISafe(_safe).isOwner(_newOwner), "Owner already exists");
        require(
            !s._isPopulatedAddOwnerWithThreshold[_newOwner][_safe],
            "Owner already populated"
        );
        require(
            s.userSuperChainAccount[_newOwner] == address(0),
            "Owner already has a SuperChainSmartAccount"
        );
        require(
            s.populatedAddOwnersWithTreshold[_safe].length <= 2,
            "Max owners populated"
        );
        s.populatedAddOwnersWithTreshold[_safe].push(_newOwner);
        s._isPopulatedAddOwnerWithThreshold[_newOwner][_safe] = true;
        string memory _superChainId = s.superChainAccount[_safe].superChainID;
        emit OwnerPopulated(_safe, _newOwner, _superChainId);
    }

    function incrementSuperChainPoints(
        uint256 _points,
        address recipent
    ) public returns (bool levelUp) {
        SuperChainStorage storage s = superChainStorage();
        Account storage _account = s.superChainAccount[recipent];
        require(
            msg.sender == s._resolver,
            "Only the resolver can increment the points"
        );
        require(_account.smartAccount != address(0), "Account not found");
        _account.points += _points;
        for (uint16 i = uint16(s._tierTreshold.length); i > 0; i--) {
            uint16 index = i - 1;
            if (s._tierTreshold[index] <= _account.points) {
                if (_account.level == index + 1) {
                    break;
                }
                _account.level = index + 1;
                levelUp = true;
                break;
            }
        }
        emit PointsIncremented(recipent, _points, levelUp);
        return levelUp;
    }

    function simulateIncrementSuperChainPoints(
        uint256 _points,
        address recipent
    ) public view returns (bool levelUp) {
        SuperChainStorage storage s = superChainStorage();
        Account memory _account = s.superChainAccount[recipent];
        require(_account.smartAccount != address(0), "Account not found");
        _account.points += _points;
        for (uint16 i = uint16(s._tierTreshold.length); i > 0; i--) {
            uint16 index = i - 1;
            if (s._tierTreshold[index] <= _account.points) {
                if (_account.level == index + 1) {
                    break;
                }
                _account.level = index + 1;
                levelUp = true;
                break;
            }
        }
        return levelUp;
    }

    function _changeResolver(address resolver) public onlyOwner {
        SuperChainStorage storage s = superChainStorage();
        s._resolver = resolver;
    }

    function addTiersTreshold(uint256[] memory _tresholds)  external onlyOwner{
        for (uint256 i = 0; i < _tresholds.length; i++) {
            _addTierTreshold(_tresholds[i]);
        }
    }

    function _addTierTreshold(uint256 _treshold) internal {
        SuperChainStorage storage s = superChainStorage();
        if (s._tierTreshold.length > 0) {
            require(
                s._tierTreshold[s._tierTreshold.length - 1] < _treshold,
                "The treshold must be higher than the last one"
            );
        }
        s._tierTreshold.push(_treshold);
        emit TierTresholdAdded(_treshold);
    }
    function updateTierThreshold(
        uint256 index,
        uint256 newThreshold
    ) public onlyOwner {
        SuperChainStorage storage s = superChainStorage();
        require(index < s._tierTreshold.length, "Index out of bounds");
        require(
            (index == 0 || s._tierTreshold[index - 1] < newThreshold) &&
                (index == s._tierTreshold.length - 1 ||
                    newThreshold < s._tierTreshold[index + 1]),
            "Invalid threshold update"
        );
        s._tierTreshold[index] = newThreshold;
        emit TierTresholdUpdated(index, newThreshold);
    }

    function getNextLevelPoints(address _safe) public view returns (uint256) {
        SuperChainStorage storage s = superChainStorage();
        if (s.superChainAccount[_safe].level == s._tierTreshold.length) {
            revert MaxLvlReached();
        }
        return s._tierTreshold[s.superChainAccount[_safe].level];
    }

    function _isInvalidSuperChainId(
        string memory str
    ) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory suffixBytes = bytes(".superchain");

        if (strBytes.length < suffixBytes.length) {
            return false;
        }

        for (uint i = 0; i < suffixBytes.length; i++) {
            if (
                strBytes[strBytes.length - suffixBytes.length + i] !=
                suffixBytes[i]
            ) {
                return false;
            }
        }

        return true;
    }

    function getSuperChainAccount(
        address _safe
    ) public view returns (Account memory) {
        SuperChainStorage storage s = superChainStorage();
        return s.superChainAccount[_safe];
    }

    function getUserSuperChainAccount(
        address _owner
    ) public view returns (Account memory) {
        SuperChainStorage storage s = superChainStorage();
        return s.superChainAccount[s.userSuperChainAccount[_owner]];
    }

    function UpdateNounAvatar(address _safe, NounMetadata calldata _noun) public {
        SuperChainStorage storage s = superChainStorage();
        require(
            msg.sender == _safe,
            "Only the SuperChainSmartAccount can update the noun"
        );
        s.superChainAccount[_safe].noun = _noun;
        emit NounUpdated(_safe, _noun);
    }

    function populatedAddOwnersWithTreshold(
        address $
    ) public view returns (address[] memory) {
        SuperChainStorage storage s = superChainStorage();
        return s.populatedAddOwnersWithTreshold[$];
    }
    function superChainAccount(address $) public view returns (Account memory) {
        SuperChainStorage storage s = superChainStorage();
        return s.superChainAccount[$];
    }
    function userSuperChainAccount(address $) public view returns (address) {
        SuperChainStorage storage s = superChainStorage();
        return s.userSuperChainAccount[$];
    }
    function hasFirstOwnerYet(address $) public view returns (bool) {
        SuperChainStorage storage s = superChainStorage();
        return s.hasFirstOwnerYet[$];
    }
    function superChainIDRegistered(
        string memory $
    ) public view returns (bool) {
        SuperChainStorage storage s = superChainStorage();
        return s.superChainIDRegistered[$];
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
