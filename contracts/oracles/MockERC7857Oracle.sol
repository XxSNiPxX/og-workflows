// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC7857Oracle} from "../interfaces/IERC7857Oracle.sol";

/// @title MockERC7857Oracle
/// @notice Trust-the-proof oracle for local development and tests.
///
///         Real production oracle would:
///           - parse a TEE attestation or ZK proof,
///           - verify a signature / verifier-key,
///           - extract oldDataHash, newDataHash, sealedKey, recipient.
///
///         This mock instead just decodes the proof bytes as the same struct
///         the oracle would otherwise produce, and returns it. Callers can
///         opt-in or opt-out of verification by setting `acceptAll`.
///
///         Encoding the off-chain side passes:
///           proof = abi.encode(oldDataHash, newDataHash, sealedKey, recipient)
contract MockERC7857Oracle is IERC7857Oracle {
    address public admin;
    bool public acceptAll;

    event AdminSet(address indexed admin);
    event AcceptAllSet(bool acceptAll);

    error NotAdmin();
    error MalformedProof();

    constructor(address _admin) {
        admin = _admin;
        acceptAll = true;
        emit AdminSet(_admin);
        emit AcceptAllSet(true);
    }

    modifier onlyAdmin() {
        if (msg.sender != admin) revert NotAdmin();
        _;
    }

    function setAdmin(address _admin) external onlyAdmin {
        admin = _admin;
        emit AdminSet(_admin);
    }

    function setAcceptAll(bool v) external onlyAdmin {
        acceptAll = v;
        emit AcceptAllSet(v);
    }

    function verifyTransferProof(bytes calldata proof)
        external
        view
        override
        returns (PreimageProofOutput memory out)
    {
        out = _decode(proof);
        out.valid = acceptAll && out.recipient != address(0);
    }

    function verifyCloneProof(bytes calldata proof)
        external
        view
        override
        returns (PreimageProofOutput memory out)
    {
        out = _decode(proof);
        out.valid = acceptAll && out.recipient != address(0);
    }

    function _decode(bytes calldata proof) internal pure returns (PreimageProofOutput memory out) {
        // Expected encoding: (bytes32 oldHash, bytes32 newHash, bytes sealedKey, address recipient)
        if (proof.length < 4 * 32) revert MalformedProof();
        (bytes32 oldHash, bytes32 newHash, bytes memory sealed_, address recipient) =
            abi.decode(proof, (bytes32, bytes32, bytes, address));
        out.oldDataHash = oldHash;
        out.newDataHash = newHash;
        out.newSealedKey = sealed_;
        out.recipient = recipient;
    }
}
