// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IAgentRegistry} from "../interfaces/IAgentRegistry.sol";

/// @title AgentAdminFacet
/// @notice Convenience admin operations for an agent diamond.
///         The diamond's contractOwner *is* the agent admin (per the spec),
///         so admin transfer == ownership transfer (handled by OwnershipFacet).
///         This facet adds protocol-aware helpers, e.g. forcing the global
///         AgentRegistry to re-sync this agent's manifest.
contract AgentAdminFacet {
    error NotAdmin();
    error ZeroAddress();

    event AdminTransferred(address indexed previousAdmin, address indexed newAdmin);

    modifier onlyAdmin() {
        if (msg.sender != LibDiamond.contractOwner()) revert NotAdmin();
        _;
    }

    /// @notice Read-only admin lookup (== diamond owner).
    function admin() external view returns (address) {
        return LibDiamond.contractOwner();
    }

    /// @notice Transfer admin rights. Equivalent to OwnershipFacet.transferOwnership
    ///         but with an admin-flavored event for indexers.
    function setAdmin(address newAdmin) external onlyAdmin {
        if (newAdmin == address(0)) revert ZeroAddress();
        address previous = LibDiamond.contractOwner();
        LibDiamond.setContractOwner(newAdmin);
        emit AdminTransferred(previous, newAdmin);
    }

    /// @notice Push an updated manifest snapshot into the global AgentRegistry.
    /// @dev    Anyone can call syncAgent on the registry, but admins commonly
    ///         want to do it from the agent itself.
    function syncToRegistry(address registry, uint256 agentId) external onlyAdmin {
        IAgentRegistry(registry).syncAgent(agentId);
    }
}
