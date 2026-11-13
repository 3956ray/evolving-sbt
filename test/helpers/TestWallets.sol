// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { IERC1271 } from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { EvolvingSBT } from "../../src/EvolvingSBT.sol";

/// @dev Test fixture only; deliberately exposes signature disabling without access control.
contract Mock1271Wallet is IERC1271, IERC721Receiver {
    address public immutable signer;
    bool public enabled = true;

    constructor(address signer_) {
        signer = signer_;
    }

    function disableSignatures() external {
        enabled = false;
    }

    function isValidSignature(bytes32 digest, bytes memory signature) external view returns (bytes4) {
        return enabled && ECDSA.recover(digest, signature) == signer
            ? IERC1271.isValidSignature.selector
            : bytes4(0xffffffff);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract ReentrantMintReceiver is IERC721Receiver {
    bool public nestedMintSucceeded;
    bool public nestedBurnSucceeded;
    bool public nestedTransferSucceeded;

    function mint(EvolvingSBT sbt) external returns (uint256) {
        return sbt.mint();
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        (nestedMintSucceeded,) = msg.sender.call(abi.encodeCall(EvolvingSBT.mint, ()));
        (nestedBurnSucceeded,) = msg.sender.call(abi.encodeCall(EvolvingSBT.burn, (tokenId)));
        (nestedTransferSucceeded,) = msg.sender
            .call(
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)", address(this), address(0xBEEF), tokenId
                )
            );
        return IERC721Receiver.onERC721Received.selector;
    }
}
