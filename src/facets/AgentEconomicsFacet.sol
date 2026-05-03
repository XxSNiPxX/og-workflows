// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAgentEconomics} from "../interfaces/IAgentEconomics.sol";
import {LibAgentManifestStorage} from "../libraries/LibAgentManifestStorage.sol";

contract AgentEconomicsFacet is IAgentEconomics {
    function getCostPerRequest() external view override returns (uint256) {
        return LibAgentManifestStorage.layout().manifest.costPerRequest;
    }

    function getPayoutAddress() external view override returns (address) {
        return LibAgentManifestStorage.layout().manifest.payoutAddress;
    }
}
