// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { EvolvingSBT } from "./EvolvingSBT.sol";
import { IEvolvingSBT } from "./interfaces/IEvolvingSBT.sol";

/// @notice Monotonic issuer revocation for one immutable signed-growth policy.
/// @dev Application configuration pins this registry; callers cannot select a replacement at use time.
contract ClaimRevocationRegistry {
    EvolvingSBT public immutable credential;
    bytes32 public immutable namespace;
    bytes32 public immutable policyId;
    address public immutable issuer;
    uint256 public immutable deploymentChainId;
    mapping(bytes32 => bool) private _revoked;

    error InvalidBinding();
    error NotIssuer();
    error InvalidClaim();

    event ClaimRevoked(uint256 indexed tokenId, bytes32 indexed claimId, bytes32 indexed revocationKey);

    constructor(EvolvingSBT credential_, bytes32 namespace_, address issuer_, address controller_) {
        if (address(credential_).code.length == 0 || issuer_ == address(0)) revert InvalidBinding();
        bytes32 policy = credential_.policyIdOf(namespace_);
        (IEvolvingSBT.PolicyDefinition memory definition,) = credential_.policyOf(namespace_, policy);
        if (
            definition.verifier != address(credential_) || definition.schemaId != credential_.SCHEMA_ID()
                || definition.rulesHash != credential_.RULES_HASH()
                || definition.authorizationHash != keccak256(abi.encode(issuer_, controller_))
                || definition.verifierConfigHash
                    != keccak256(
                        abi.encode(credential_.PROFILE_ID(), credential_.MAX_RECORDS(), issuer_, controller_)
                    )
        ) revert InvalidBinding();
        credential = credential_;
        namespace = namespace_;
        policyId = policy;
        issuer = issuer_;
        deploymentChainId = block.chainid;
    }

    function revocationKey(uint256 tokenId, bytes32 claimId) public view returns (bytes32) {
        return keccak256(
            abi.encode(deploymentChainId, address(credential), namespace, policyId, tokenId, claimId)
        );
    }

    function isRevoked(uint256 tokenId, bytes32 claimId) external view returns (bool) {
        return _revoked[revocationKey(tokenId, claimId)];
    }

    /// @notice Revoke even before admission, during an update pause, or after history capacity is exhausted.
    function revoke(uint256 tokenId, bytes32 claimId) external {
        if (msg.sender != issuer) revert NotIssuer();
        if (claimId == bytes32(0)) revert InvalidClaim();
        bytes32 key = revocationKey(tokenId, claimId);
        if (_revoked[key]) return;
        _revoked[key] = true;
        emit ClaimRevoked(tokenId, claimId, key);
    }
}
