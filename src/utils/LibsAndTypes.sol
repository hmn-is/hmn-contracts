// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Named type for the semantic clarity of current and future WorldID verification levels (groupId)
type VerificationLevel is uint256;

/// @dev Verification levels (WorldID groupId + custom 0 level for off-chain device-based verification)
library VerificationLevels {
    uint256 constant DEVICE = 0;  // For allowing transfers after off-chain device-based verification
                                  // NOTE! at the time of writing, worldID protocol does not recognise groupId 0
                                  //       or support on-chain device-based verification 
    uint256 constant ORB = 1;     // Require orb-based humanity verification
                                  // Require orb + face verification in the future?
}

/// @dev Struct with verification level (WorldID groupId) and verification timestamp for an address
struct Verification {
    uint256 level;     // Verification level achieved (see VerificationLevels)
                       // NOTE! equals VerificationLevels.DEVICE for unverified addresses,
                       //       so timestamp has to be always checked.
    uint256 timestamp; // When verification was granted/updated, or for unverified addresses.
}

/// @dev Named type for the semantic clarity of transfer protection modes
type TransferProtectionMode is uint256;

/// @dev Transfer protection modes that determine how strictly transfers are controlled
/// @dev See HmnManagerImplBase.checkTrust for detailed logic.
library TransferProtectionModes {
    uint256 constant ALLOW_ALL = 0;            // Disables all restrictions
    uint256 constant BLOCK_BOTS_ONLY = 1;      // Only block blacklisted bots
    uint256 constant ALLOW_ALL_CONTRACTS = 2;  // Allow if either party is a contract
    uint256 constant ALLOW_TO_CONTRACTS = 3;   // Allow sending to any contract
    uint256 constant ALLOW_FROM_CONTRACTS = 4; // Allow sending from any contract
    uint256 constant VERIFY_WITH_PIONEERING = 5; // Allow trusted pioneer users to whitelist contracts with their transactions
    uint256 constant VERIFY = 6;               // Apply all checks, and disable pioneering
}

/// @notice Named type for identifying the block chain (ecosystem) of an address
/// @dev Note that this is not the chainId of ethereum ecosystem (see BlockChainIds)
type BlockChainId is uint16;

/// @notice Block chain IDs following Wormhole's Solana centric worldview
/// @dev Used for future cross-chain verification state synchronization
library BlockChainIds {
    BlockChainId constant SOLANA = BlockChainId.wrap(1);
    BlockChainId constant ETHEREUM = BlockChainId.wrap(2);
}

/// @dev 32-byte address format for cross-chain compatibility
type Address32 is bytes32;


/// @dev Utlities for dealing with 32 byte addressess
library MultiChainAddress {

  /// @dev Converts 20-byte Ethereum address to 32-byte format by padding with zeros
    function toAddress32(address addr) internal pure returns (Address32) {
        return Address32.wrap(bytes32(uint256(uint160(addr))));
    }

    /// @dev Converts 32-byte address back to 20-byte Ethereum address format
    function toAddress(Address32 addr) internal pure returns (address) {
        return address(uint160(uint256(Address32.unwrap(addr))));
    }

    /// @dev Converts address to checksummed hex string
    function toString(address account) internal pure returns (string memory) {
        return Strings.toHexString(uint256(uint160(account)), 20);
    }

    /// @dev Checks if a 32-byte address is zero/unset
    function isZero(Address32 addr) internal pure returns (bool) {
        return Address32.unwrap(addr) == 0;
    }

    /// @dev Checks if a 32-byte address is not zero/unset
    function isSet(Address32 addr) internal pure returns (bool) {
        return !isZero(addr);
    }
}

/// @dev Utilities for World ID integration
library ByteHasher {
	/// @dev Creates a keccak256 hash of a bytestring.
	/// @param value The bytestring to hash
	/// @return The hash of the specified value
	/// @dev `>> 8` makes sure that the result is included in WorldID field
	function hashToField(bytes memory value) internal pure returns (uint256) {
		return uint256(keccak256(abi.encodePacked(value))) >> 8;
	}
}