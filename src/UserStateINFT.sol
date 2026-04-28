// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7857} from "./interfaces/IERC7857.sol";
import {IERC7857Oracle} from "./interfaces/IERC7857Oracle.sol";
import {IUserStateINFT} from "./interfaces/IUserStateINFT.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {LibPermissionScope} from "./libraries/LibPermissionScope.sol";

contract UserStateINFT is IERC7857, IUserStateINFT, IERC165 {
    using LibPermissionScope for bytes;
    using LibPermissionScope for LibPermissionScope.PermissionScope;

    struct INFTData {
        bytes32 dataHash;
        bytes sealedKey;
        string encryptedURI;
    }

    struct PermissionEntry {
        bytes raw;
        uint64 updatedAt;
    }

    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _walletToToken;

    mapping(uint256 => INFTData) private _data;
    mapping(uint256 => bytes) private _disclosedKey;

    mapping(uint256 => mapping(address => PermissionEntry))
        private _permissions;
    mapping(uint256 => address[]) private _executors;
    mapping(uint256 => mapping(address => uint256)) private _executorIndex;

    uint256 private _nextTokenId;

    address public admin;
    IERC7857Oracle public oracle;
    bool public mintingPaused;

    error NotAdmin();
    error NotOwner();
    error ZeroAddress();
    error AlreadyHasToken();
    error NoToken();
    error Paused();
    error OracleNotSet();
    error InvalidProof();
    error RecipientMismatch();
    error EmptyKey();
    error AlreadyPublished();

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier exists(uint256 tokenId) {
        if (_owners[tokenId] == address(0)) revert NoToken();
        _;
    }

    modifier onlyOwner(uint256 tokenId) {
        if (_owners[tokenId] != msg.sender) revert NotOwner();
        _;
    }

    constructor(address _admin, address _oracle) {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        oracle = IERC7857Oracle(_oracle);
    }

    // ========================= MINT =========================

    function mint(
        address to,
        bytes32 dataHash,
        bytes calldata sealedKey,
        string calldata encryptedURI
    ) external override(IERC7857) returns (uint256 id) {
        if (mintingPaused) revert Paused();
        if (to == address(0)) revert ZeroAddress();
        if (_walletToToken[to] != 0) revert AlreadyHasToken();
        if (sealedKey.length == 0) revert EmptyKey();

        id = ++_nextTokenId;

        _owners[id] = to;
        _walletToToken[to] = id;
        _data[id] = INFTData(dataHash, sealedKey, encryptedURI);

        emit Minted(to, id, dataHash, sealedKey, encryptedURI);
    }

    // ========================= TRANSFER =========================

    function publish(
        uint256 tokenId,
        bytes calldata disclosedKey
    ) external override(IERC7857) exists(tokenId) onlyOwner(tokenId) {
        if (disclosedKey.length == 0) revert EmptyKey();
        if (_disclosedKey[tokenId].length != 0) revert AlreadyPublished();

        _disclosedKey[tokenId] = disclosedKey;
        emit Published(tokenId, disclosedKey);
    }

    function secureTransfer(
        address to,
        uint256 tokenId,
        bytes calldata proof
    ) external override(IERC7857) exists(tokenId) onlyOwner(tokenId) {
        if (to == address(0)) revert ZeroAddress();
        if (_walletToToken[to] != 0) revert AlreadyHasToken();
        if (address(oracle) == address(0)) revert OracleNotSet();

        IERC7857Oracle.PreimageProofOutput memory out = oracle
            .verifyTransferProof(proof);

        if (!out.valid) revert InvalidProof();
        if (out.recipient != to) revert RecipientMismatch();
        if (out.oldDataHash != _data[tokenId].dataHash) revert InvalidProof();

        address from = msg.sender;

        _wipePermissions(tokenId);

        _walletToToken[from] = 0;
        _walletToToken[to] = tokenId;
        _owners[tokenId] = to;

        _data[tokenId].dataHash = out.newDataHash;
        _data[tokenId].sealedKey = out.newSealedKey;

        delete _disclosedKey[tokenId];

        emit SecureTransferred(
            tokenId,
            from,
            to,
            out.newDataHash,
            out.newSealedKey
        );
    }

    function cloneToken(
        address to,
        uint256 tokenId,
        bytes calldata proof
    )
        external
        override(IERC7857)
        exists(tokenId)
        onlyOwner(tokenId)
        returns (uint256 newId)
    {
        if (to == address(0)) revert ZeroAddress();
        if (_walletToToken[to] != 0) revert AlreadyHasToken();
        if (address(oracle) == address(0)) revert OracleNotSet();

        IERC7857Oracle.PreimageProofOutput memory out = oracle.verifyCloneProof(
            proof
        );

        if (!out.valid) revert InvalidProof();
        if (out.recipient != to) revert RecipientMismatch();
        if (out.oldDataHash != _data[tokenId].dataHash) revert InvalidProof();

        newId = ++_nextTokenId;

        _owners[newId] = to;
        _walletToToken[to] = newId;

        _data[newId] = INFTData(
            out.newDataHash,
            out.newSealedKey,
            _data[tokenId].encryptedURI
        );

        emit Cloned(tokenId, newId, to, out.newDataHash, out.newSealedKey);
    }

    // ========================= PERMISSIONS =========================

    function authorizeUsage(
        uint256 tokenId,
        address executor,
        bytes calldata permissions
    ) external override(IERC7857) exists(tokenId) onlyOwner(tokenId) {
        if (executor == address(0)) revert ZeroAddress();

        _permissions[tokenId][executor] = PermissionEntry(
            permissions,
            uint64(block.timestamp)
        );

        if (_executorIndex[tokenId][executor] == 0) {
            _executors[tokenId].push(executor);
            _executorIndex[tokenId][executor] = _executors[tokenId].length;
        }

        emit UsageAuthorized(tokenId, executor, permissions);
    }

    function revokeUsage(
        uint256 tokenId,
        address executor
    ) external override(IERC7857) exists(tokenId) onlyOwner(tokenId) {
        uint256 idx = _executorIndex[tokenId][executor];
        if (idx == 0) return;

        delete _permissions[tokenId][executor];

        uint256 last = _executors[tokenId].length;
        if (idx != last) {
            address lastAddr = _executors[tokenId][last - 1];
            _executors[tokenId][idx - 1] = lastAddr;
            _executorIndex[tokenId][lastAddr] = idx;
        }

        _executors[tokenId].pop();
        delete _executorIndex[tokenId][executor];

        emit UsageRevoked(tokenId, executor);
    }

    function _wipePermissions(uint256 tokenId) internal {
        address[] storage execs = _executors[tokenId];

        for (uint256 i = execs.length; i > 0; i--) {
            address e = execs[i - 1];
            delete _permissions[tokenId][e];
            delete _executorIndex[tokenId][e];
            execs.pop();
            emit UsageRevoked(tokenId, e);
        }
    }

    // ========================= READS =========================

    function ownerOf(
        uint256 tokenId
    ) public view override(IERC7857, IUserStateINFT) returns (address) {
        address o = _owners[tokenId];
        if (o == address(0)) revert NoToken();
        return o;
    }

    function tokenIdOf(
        address wallet
    ) external view override(IUserStateINFT) returns (uint256) {
        return _walletToToken[wallet];
    }

    function dataHashOf(
        uint256 tokenId
    ) external view override(IERC7857, IUserStateINFT) returns (bytes32) {
        if (_owners[tokenId] == address(0)) revert NoToken();
        return _data[tokenId].dataHash;
    }

    function encryptedURIOf(
        uint256 tokenId
    ) external view override(IERC7857, IUserStateINFT) returns (string memory) {
        if (_owners[tokenId] == address(0)) revert NoToken();
        return _data[tokenId].encryptedURI;
    }

    function getPermissions(
        uint256 tokenId,
        address executor
    ) external view override(IERC7857, IUserStateINFT) returns (bytes memory) {
        return _permissions[tokenId][executor].raw;
    }

    function isAuthorized(
        uint256 tokenId,
        address executor
    ) external view override(IERC7857, IUserStateINFT) returns (bool) {
        PermissionEntry memory p = _permissions[tokenId][executor];
        if (p.raw.length == 0) return false;

        LibPermissionScope.PermissionScope memory s = LibPermissionScope.decode(
            p.raw
        );

        if (s.expiresAt != 0 && block.timestamp > s.expiresAt) return false;

        return s.canWrite || s.canAppend;
    }

    function isAuthorizedFor(
        uint256 tokenId,
        address executor,
        bytes32 itemType,
        uint256 workflowId
    ) external view override(IUserStateINFT) returns (bool) {
        PermissionEntry memory p = _permissions[tokenId][executor];
        if (p.raw.length == 0) return false;

        LibPermissionScope.PermissionScope memory s = LibPermissionScope.decode(
            p.raw
        );

        if (!s.canWrite && !s.canAppend) return false;

        return s.covers(itemType, workflowId);
    }

    function disclosedKeyOf(
        uint256 tokenId
    ) external view override(IUserStateINFT) returns (bytes memory) {
        return _disclosedKey[tokenId];
    }

    // ========================= ERC165 =========================

    function supportsInterface(
        bytes4 interfaceId
    ) external pure override returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC7857).interfaceId ||
            interfaceId == type(IUserStateINFT).interfaceId;
    }
}
