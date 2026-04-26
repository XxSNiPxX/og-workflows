// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IERC7857
/// @notice Interface for ERC-7857 Intelligent NFTs (iNFTs).
/// @dev ERC-7857 extends ERC-721 with encrypted metadata, oracle-verified
///      re-encryption on transfer/clone, and authorized usage grants.
///      Reference: 0G Labs ERC-7857 draft.
interface IERC7857 {
    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    /// @notice Emitted when a new iNFT is minted.
    /// @param to            recipient / first owner
    /// @param tokenId       newly minted tokenId
    /// @param dataHash      keccak256 of the encrypted off-chain payload
    /// @param sealedKey     symmetric key sealed to the recipient's pubkey
    /// @param encryptedURI  off-chain URI (e.g. 0G Storage) of the encrypted blob
    event Minted(
        address indexed to,
        uint256 indexed tokenId,
        bytes32 dataHash,
        bytes sealedKey,
        string encryptedURI
    );

    /// @notice Emitted when a token is transferred with re-encryption.
    /// @dev    Different from ERC721 Transfer: this carries the new dataHash
    ///         and sealedKey produced by the oracle.
    event SecureTransferred(
        uint256 indexed tokenId,
        address indexed from,
        address indexed to,
        bytes32 newDataHash,
        bytes newSealedKey
    );

    /// @notice Emitted when a token is cloned (original kept, new minted with re-encrypted data).
    event Cloned(
        uint256 indexed originalTokenId,
        uint256 indexed newTokenId,
        address indexed to,
        bytes32 newDataHash,
        bytes newSealedKey
    );

    /// @notice Emitted when an executor is authorized to use a tokenId off-chain.
    /// @dev    `permissions` is ABI-encoded protocol-specific data (see LibPermissionScope).
    event UsageAuthorized(
        uint256 indexed tokenId,
        address indexed executor,
        bytes permissions
    );

    /// @notice Emitted when an executor's authorization is revoked.
    event UsageRevoked(
        uint256 indexed tokenId,
        address indexed executor
    );

    /// @notice Emitted when a previously-encrypted token's key is published
    ///         (e.g. owner makes the agent open-source).
    event Published(
        uint256 indexed tokenId,
        bytes disclosedKey
    );

    // ---------------------------------------------------------------------
    // Mint / Transfer / Clone
    // ---------------------------------------------------------------------

    /// @notice Mint a new iNFT with sealed encrypted metadata.
    function mint(
        address to,
        bytes32 dataHash,
        bytes calldata sealedKey,
        string calldata encryptedURI
    ) external returns (uint256 tokenId);

    /// @notice Transfer with oracle-verified re-encryption.
    /// @param to     recipient
    /// @param tokenId tokenId being transferred
    /// @param proof  opaque oracle proof bytes; verified by IERC7857Oracle
    function secureTransfer(
        address to,
        uint256 tokenId,
        bytes calldata proof
    ) external;

    /// @notice Clone a token: original keeps living, new tokenId minted with re-encrypted data.
    function cloneToken(
        address to,
        uint256 tokenId,
        bytes calldata proof
    ) external returns (uint256 newTokenId);

    /// @notice Reveal the sealed key to make the encrypted payload publicly decryptable.
    function publish(
        uint256 tokenId,
        bytes calldata disclosedKey
    ) external;

    // ---------------------------------------------------------------------
    // Authorized usage (off-chain executors)
    // ---------------------------------------------------------------------

    /// @notice Grant `executor` the right to use the token's data off-chain
    ///         under the constraints encoded in `permissions`.
    function authorizeUsage(
        uint256 tokenId,
        address executor,
        bytes calldata permissions
    ) external;

    /// @notice Revoke a previous authorizeUsage.
    function revokeUsage(uint256 tokenId, address executor) external;

    // ---------------------------------------------------------------------
    // Reads
    // ---------------------------------------------------------------------

    /// @notice keccak256 of the encrypted off-chain payload for `tokenId`.
    function dataHashOf(uint256 tokenId) external view returns (bytes32);

    /// @notice ERC-721-style owner lookup. ERC-7857 extends ERC-721 in spirit
    ///         though we don't formally inherit IERC721 here to keep the
    ///         interface minimal.
    function ownerOf(uint256 tokenId) external view returns (address);

    /// @notice The encrypted URI (e.g. 0G Storage pointer) for `tokenId`.
    function encryptedURIOf(uint256 tokenId) external view returns (string memory);

    /// @notice Returns the raw permission bytes previously granted to `executor`.
    function getPermissions(uint256 tokenId, address executor)
        external
        view
        returns (bytes memory);

    /// @notice Whether `executor` has *any* non-expired authorization on `tokenId`.
    function isAuthorized(uint256 tokenId, address executor) external view returns (bool);
}
