// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7857} from "./interfaces/IERC7857.sol";
import {IERC7857Oracle} from "./interfaces/IERC7857Oracle.sol";
import {IUserStateINFT} from "./interfaces/IUserStateINFT.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {LibPermissionScope} from "./libraries/LibPermissionScope.sol";

/// @title UserStateINFT
/// @notice Global ERC-7857 contract: one Intelligent NFT per user wallet.
///
///         The iNFT carries the encrypted pointer to a user's private profile +
///         policy state. Other contracts (UserStateLedger, AgentDiamond,
///         WorkflowInstance) treat this contract as the authority for two
///         questions:
///           - "who owns tokenId X?"  → ownerOf
///           - "is executor E allowed to use tokenId X for type T under
///              workflow W?" → isAuthorizedFor
///
///         Re-encryption on transfer/clone is delegated to an off-chain oracle
///         (TEE / ZK). v1 ships with a MockOracle for testability.
contract UserStateINFT is IERC7857, IUserStateINFT, IERC165 {
    using LibPermissionScope for bytes;
    using LibPermissionScope for LibPermissionScope.PermissionScope;

    // ---------------------------------------------------------------------
    // Storage — ERC-7857 core
    // ---------------------------------------------------------------------

    struct INFTData {
        bytes32 dataHash;       // keccak256 of the encrypted off-chain payload
        bytes sealedKey;        // sealed symmetric key for current owner
        string encryptedURI;    // 0G storage URI
    }

    struct UserProfile {
        bool active;
        uint64 createdAt;
        uint64 updatedAt;
    }

    // tokenId => owner
    mapping(uint256 => address) private _owners;
    // wallet => tokenId  (one-per-wallet enforcement; 0 means none)
    mapping(address => uint256) private _walletToToken;
    // tokenId => INFT payload
    mapping(uint256 => INFTData) private _data;
    // tokenId => protocol-side profile metadata
    mapping(uint256 => UserProfile) private _profiles;

    // tokenId => disclosed key (non-empty means published)
    mapping(uint256 => bytes) private _disclosedKey;

    // tokenId => executor => raw permissions blob
    mapping(uint256 => mapping(address => bytes)) private _permissions;
    // tokenId => list of currently-authorized executors (for enumeration)
    mapping(uint256 => address[]) private _executors;
    // tokenId => executor => 1-based index in _executors[tokenId]
    mapping(uint256 => mapping(address => uint256)) private _executorIndex;

    uint256 private _nextTokenId;

    // ---------------------------------------------------------------------
    // Storage — admin / oracle
    // ---------------------------------------------------------------------

    address public admin;
    IERC7857Oracle public oracle;
    bool public mintingPaused;

    // ---------------------------------------------------------------------
    // Extra events (beyond IERC7857)
    // ---------------------------------------------------------------------

    event AdminSet(address indexed admin);
    event OracleSet(address indexed oracle);
    event MintingPaused(bool paused);
    event ProfileUpdated(uint256 indexed tokenId, bool active);

    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    error NotAdmin();
    error NotOwner();
    error ZeroAddress();
    error AlreadyMinted();
    error NoToken();
    error PausedErr();
    error OracleNotSet();
    error InvalidProof();
    error RecipientMismatch();
    error AlreadyHasToken();
    error EmptyKey();
    error AlreadyPublished();
    error TokenAlreadyAuthorized(); // never thrown; reserved for richer states
    error NotAuthorized();

    // ---------------------------------------------------------------------
    // Init
    // ---------------------------------------------------------------------

    constructor(address _admin, address _oracle) {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        oracle = IERC7857Oracle(_oracle); // may be address(0) initially
        emit AdminSet(_admin);
        emit OracleSet(_oracle);
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    modifier onlyTokenOwner(uint256 tokenId) {
        if (_owners[tokenId] != msg.sender) revert NotOwner();
        _;
    }

    function setAdmin(address _admin) external onlyAdmin {
        if (_admin == address(0)) revert ZeroAddress();
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setOracle(address _oracle) external onlyAdmin {
        oracle = IERC7857Oracle(_oracle);
        emit OracleSet(_oracle);
    }

    function setMintingPaused(bool _paused) external onlyAdmin {
        mintingPaused = _paused;
        emit MintingPaused(_paused);
    }

    // ---------------------------------------------------------------------
    // ERC-7857: mint / transfer / clone / publish
    // ---------------------------------------------------------------------

    /// @notice Mint exactly one iNFT per wallet.
    function mint(
        address to,
        bytes32 dataHash,
        bytes calldata sealedKey,
        string calldata encryptedURI
    ) external override returns (uint256 tokenId) {
        if (mintingPaused) revert PausedErr();
        if (to == address(0)) revert ZeroAddress();
        if (sealedKey.length == 0) revert EmptyKey();
        if (_walletToToken[to] != 0) revert AlreadyHasToken();

        tokenId = ++_nextTokenId;
        _owners[tokenId] = to;
        _walletToToken[to] = tokenId;
        _data[tokenId] = INFTData({
            dataHash: dataHash,
            sealedKey: sealedKey,
            encryptedURI: encryptedURI
        });
        _profiles[tokenId] = UserProfile({
            active: true,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        emit Minted(to, tokenId, dataHash, sealedKey, encryptedURI);
    }

    /// @notice Secure transfer with oracle-verified re-encryption.
    /// @dev    Callable by the current owner. The proof must reference this
    ///         token's current dataHash and produce a new sealedKey for `to`.
    function secureTransfer(address to, uint256 tokenId, bytes calldata proof)
        external
        override
        onlyTokenOwner(tokenId)
    {
        if (to == address(0)) revert ZeroAddress();
        if (_walletToToken[to] != 0) revert AlreadyHasToken();
        if (address(oracle) == address(0)) revert OracleNotSet();

        IERC7857Oracle.PreimageProofOutput memory out = oracle.verifyTransferProof(proof);
        if (!out.valid) revert InvalidProof();
        if (out.recipient != to) revert RecipientMismatch();
        if (out.oldDataHash != _data[tokenId].dataHash) revert InvalidProof();

        address from = msg.sender;

        // wipe ALL outstanding usage authorizations on transfer — the new
        // owner inherits a clean slate.
        _wipeAllAuthorizations(tokenId);

        // move ownership
        _walletToToken[from] = 0;
        _walletToToken[to] = tokenId;
        _owners[tokenId] = to;

        // update encrypted payload
        _data[tokenId].dataHash = out.newDataHash;
        _data[tokenId].sealedKey = out.newSealedKey;
        _profiles[tokenId].updatedAt = uint64(block.timestamp);
        // disclosed key (if any) is invalidated since the underlying payload changed
        delete _disclosedKey[tokenId];

        emit SecureTransferred(tokenId, from, to, out.newDataHash, out.newSealedKey);
    }

    /// @notice Clone — original keeps living, new tokenId minted to `to` with
    ///         a re-encrypted copy of the payload.
    function cloneToken(address to, uint256 tokenId, bytes calldata proof)
        external
        override
        onlyTokenOwner(tokenId)
        returns (uint256 newTokenId)
    {
        if (to == address(0)) revert ZeroAddress();
        if (_walletToToken[to] != 0) revert AlreadyHasToken();
        if (address(oracle) == address(0)) revert OracleNotSet();

        IERC7857Oracle.PreimageProofOutput memory out = oracle.verifyCloneProof(proof);
        if (!out.valid) revert InvalidProof();
        if (out.recipient != to) revert RecipientMismatch();
        if (out.oldDataHash != _data[tokenId].dataHash) revert InvalidProof();

        newTokenId = ++_nextTokenId;
        _owners[newTokenId] = to;
        _walletToToken[to] = newTokenId;

        _data[newTokenId] = INFTData({
            dataHash: out.newDataHash,
            sealedKey: out.newSealedKey,
            encryptedURI: _data[tokenId].encryptedURI // recipient gets same URI; payload at URI is the same encrypted blob
        });
        _profiles[newTokenId] = UserProfile({
            active: true,
            createdAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });

        emit Cloned(tokenId, newTokenId, to, out.newDataHash, out.newSealedKey);
    }

    /// @notice Publish: reveal the sealed key publicly, e.g. to make the
    ///         underlying agent open-source.
    function publish(uint256 tokenId, bytes calldata disclosedKey)
        external
        override
        onlyTokenOwner(tokenId)
    {
        if (disclosedKey.length == 0) revert EmptyKey();
        if (_disclosedKey[tokenId].length != 0) revert AlreadyPublished();
        _disclosedKey[tokenId] = disclosedKey;
        emit Published(tokenId, disclosedKey);
    }

    // ---------------------------------------------------------------------
    // ERC-7857: authorizeUsage / revokeUsage
    // ---------------------------------------------------------------------

    function authorizeUsage(uint256 tokenId, address executor, bytes calldata permissions)
        external
        override
        onlyTokenOwner(tokenId)
    {
        if (executor == address(0)) revert ZeroAddress();
        // overwriting an existing authorization is allowed (= scope rotation)
        _permissions[tokenId][executor] = permissions;
        if (_executorIndex[tokenId][executor] == 0) {
            _executors[tokenId].push(executor);
            _executorIndex[tokenId][executor] = _executors[tokenId].length;
        }
        emit UsageAuthorized(tokenId, executor, permissions);
    }

    function revokeUsage(uint256 tokenId, address executor)
        external
        override
        onlyTokenOwner(tokenId)
    {
        _revoke(tokenId, executor);
    }

    function _revoke(uint256 tokenId, address executor) internal {
        if (_executorIndex[tokenId][executor] == 0) return;

        delete _permissions[tokenId][executor];

        uint256 idx1 = _executorIndex[tokenId][executor];
        uint256 last = _executors[tokenId].length;
        if (idx1 != last) {
            address lastAddr = _executors[tokenId][last - 1];
            _executors[tokenId][idx1 - 1] = lastAddr;
            _executorIndex[tokenId][lastAddr] = idx1;
        }
        _executors[tokenId].pop();
        delete _executorIndex[tokenId][executor];

        emit UsageRevoked(tokenId, executor);
    }

    function _wipeAllAuthorizations(uint256 tokenId) internal {
        address[] storage execs = _executors[tokenId];
        // iterate from the end so swap-pop doesn't shift unread entries
        for (uint256 i = execs.length; i > 0; i--) {
            address e = execs[i - 1];
            delete _permissions[tokenId][e];
            delete _executorIndex[tokenId][e];
            execs.pop();
            emit UsageRevoked(tokenId, e);
        }
    }

    // ---------------------------------------------------------------------
    // ERC-7857 reads
    // ---------------------------------------------------------------------

    function ownerOf(uint256 tokenId) public view override(IERC7857, IUserStateINFT) returns (address) {
        address o = _owners[tokenId];
        if (o == address(0)) revert NoToken();
        return o;
    }

    function dataHashOf(uint256 tokenId) external view override returns (bytes32) {
        if (_owners[tokenId] == address(0)) revert NoToken();
        return _data[tokenId].dataHash;
    }

    function encryptedURIOf(uint256 tokenId) external view override returns (string memory) {
        if (_owners[tokenId] == address(0)) revert NoToken();
        return _data[tokenId].encryptedURI;
    }

    function getPermissions(uint256 tokenId, address executor)
        external
        view
        override
        returns (bytes memory)
    {
        return _permissions[tokenId][executor];
    }

    function isAuthorized(uint256 tokenId, address executor)
        external
        view
        override
        returns (bool)
    {
        bytes memory raw = _permissions[tokenId][executor];
        if (raw.length == 0) return false;
        LibPermissionScope.PermissionScope memory s = LibPermissionScope.decode(raw);
        if (s.expiresAt != 0 && uint64(block.timestamp) > s.expiresAt) return false;
        return s.canRead || s.canWrite || s.canAppend;
    }

    // ---------------------------------------------------------------------
    // IUserStateINFT — protocol-aware authorization
    // ---------------------------------------------------------------------

    function tokenIdOf(address wallet) external view override returns (uint256) {
        return _walletToToken[wallet];
    }

    /// @notice Used by UserStateLedger and downstream contracts to gate writes
    ///         and reads at the appropriate granularity.
    function isAuthorizedFor(
        uint256 tokenId,
        address executor,
        bytes32 itemType,
        uint256 workflowId
    ) external view override returns (bool) {
        if (_owners[tokenId] == address(0)) return false;
        bytes memory raw = _permissions[tokenId][executor];
        if (raw.length == 0) return false;
        LibPermissionScope.PermissionScope memory s = LibPermissionScope.decode(raw);
        if (!s.canAppend && !s.canWrite) return false; // for write-paths
        return s.covers(itemType, workflowId);
    }

    // ---------------------------------------------------------------------
    // Helper reads (not part of any standard)
    // ---------------------------------------------------------------------

    function getAuthorizedExecutors(uint256 tokenId) external view returns (address[] memory) {
        return _executors[tokenId];
    }

    function getProfile(uint256 tokenId) external view returns (UserProfile memory) {
        return _profiles[tokenId];
    }

    function disclosedKeyOf(uint256 tokenId) external view returns (bytes memory) {
        return _disclosedKey[tokenId];
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    function setProfileActive(uint256 tokenId, bool active_) external onlyTokenOwner(tokenId) {
        _profiles[tokenId].active = active_;
        _profiles[tokenId].updatedAt = uint64(block.timestamp);
        emit ProfileUpdated(tokenId, active_);
    }

    // ---------------------------------------------------------------------
    // ERC-165
    // ---------------------------------------------------------------------

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(IERC165).interfaceId
            || interfaceId == type(IERC7857).interfaceId
            || interfaceId == type(IUserStateINFT).interfaceId;
    }
}
