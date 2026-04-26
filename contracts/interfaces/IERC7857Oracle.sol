// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title IERC7857Oracle
/// @notice Verifier for re-encryption proofs used by ERC-7857 transfer/clone.
/// @dev    In production this is backed by a TEE attestation or ZK proof produced
///         by an off-chain re-encryption service. The oracle attests that:
///           - the holder of the *old* sealed key produced a *new* sealed key
///             for `recipient`'s pubkey,
///           - the underlying plaintext (whose keccak256 is `newDataHash`) is
///             the same as before (or correctly transformed),
///         all without revealing the plaintext to the chain.
///
///         In v1 we ship a MockOracle that accepts any well-formed proof so the
///         protocol is testable end-to-end.
interface IERC7857Oracle {
    /// @notice Output of a verified re-encryption proof.
    struct PreimageProofOutput {
        bool valid;
        bytes32 oldDataHash;     // hash of the previous-owner's encrypted blob
        bytes32 newDataHash;     // hash of the new-owner's encrypted blob
        bytes   newSealedKey;    // symmetric key sealed to recipient's pubkey
        address recipient;       // who the new sealed key is for
    }

    /// @notice Verify a transfer re-encryption proof.
    /// @dev    Reverts on malformed proof; returns valid=false on bad proof.
    function verifyTransferProof(bytes calldata proof)
        external
        view
        returns (PreimageProofOutput memory);

    /// @notice Verify a clone re-encryption proof.
    /// @dev    Same shape as transfer but semantically the source token is not destroyed.
    function verifyCloneProof(bytes calldata proof)
        external
        view
        returns (PreimageProofOutput memory);
}
