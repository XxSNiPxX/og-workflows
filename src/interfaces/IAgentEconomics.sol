// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IAgentEconomics {
    function getCostPerRequest() external view returns (uint256);

    function getPayoutAddress() external view returns (address);
}
