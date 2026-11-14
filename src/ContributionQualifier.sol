// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { EvolvingSBT } from "./EvolvingSBT.sol";
import { IEvolvingSBT } from "./interfaces/IEvolvingSBT.sol";
import { ClaimRevocationRegistry } from "./ClaimRevocationRegistry.sol";

/// @notice Public-data reference predicate: two distinct, currently valid recognized contributions.
/// @dev The application trusts the deployment and fixes its policy and registry at construction.
contract ContributionQualifier {
    EvolvingSBT public immutable credential;
    bytes32 public immutable namespace;
    bytes32 public immutable policyId;
    ClaimRevocationRegistry public immutable registry;

    error InvalidBinding();

    constructor(
        EvolvingSBT credential_,
        bytes32 namespace_,
        bytes32 policyId_,
        ClaimRevocationRegistry registry_
    ) {
        if (
            address(registry_).code.length == 0 || address(registry_.credential()) != address(credential_)
                || registry_.namespace() != namespace_ || registry_.policyId() != policyId_
                || credential_.policyIdOf(namespace_) != policyId_
        ) revert InvalidBinding();
        credential = credential_;
        namespace = namespace_;
        policyId = policyId_;
        registry = registry_;
    }

    /// @notice Evaluate at the call's block; this does not authenticate the caller or grant an entitlement.
    function qualifies(uint256 tokenId, uint256[2] calldata indices) external view returns (bool) {
        if (!credential.isUsable(tokenId, namespace)) return false;
        IEvolvingSBT.StateHead memory head = credential.stateOf(tokenId, namespace);
        if (head.policyId != policyId) return false;
        uint256 count = credential.recordCount(tokenId, namespace);
        if (indices[0] == indices[1] || indices[0] >= count || indices[1] >= count) return false;
        address holder = credential.ownerOf(tokenId);
        (EvolvingSBT.Record memory first, bool firstActive) =
            credential.recordAt(tokenId, namespace, indices[0]);
        (EvolvingSBT.Record memory second, bool secondActive) =
            credential.recordAt(tokenId, namespace, indices[1]);
        return first.experienceId != second.experienceId && _valid(tokenId, holder, first, firstActive)
            && _valid(tokenId, holder, second, secondActive);
    }

    function _valid(uint256 tokenId, address holder, EvolvingSBT.Record memory record, bool active)
        internal
        view
        returns (bool)
    {
        return active && record.subject == holder
            && (record.validUntil == 0 || block.timestamp <= record.validUntil)
            && !registry.isRevoked(tokenId, record.claimId);
    }
}
