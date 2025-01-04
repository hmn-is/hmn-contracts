// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {HmnManagerImplBase} from "./HmnManagerImplBase.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IHmnManagerBridge} from "./interfaces/IHmnManagerBridge.sol";
import {IHmnManagerMain} from "./interfaces/IHmnManagerMain.sol";
import {IHmnManagerBase} from "./interfaces/IHmnManagerBase.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher, MultiChainAddress, Address32, BlockChainId, Verification, Strings, VerificationLevels, BlockChainIds} from './utils/LibsAndTypes.sol';


/// @title Human Verification Registry Implementation Version 1 - Storage only
/// @notice A registry that manages human verification and account recovery on Ethereum Mainnet
/// @dev Implementation contract designed to operate behind a proxy. Key considerations:
/// - All (mainnet specific) data is kept in this storage contract (and can never be changed, only added to)
/// - All (mainnet specific) logic is kept in a separate logic contract (and can be changed by later, delayed upgrades)
abstract contract HmnManagerImplMainStorageV1 {

    ///////////////////////////////////////////////////////////////////////////////
    ///                   A NOTE ON IMPLEMENTATION CONTRACTS                    ///
    ///////////////////////////////////////////////////////////////////////////////

    // This contract is designed explicitly to operate from behind a proxy contract. As a result,
    // there are a few important implementation considerations:
    //
    // - All updates made after deploying a given version of the implementation should inherit from
    //   the latest version of the implementation. This prevents storage clashes.
    // - All functions that are less access-restricted than `private` should be marked `virtual` in
    //   order to enable the fixing of bugs in the existing interface.
    // - Any function that reads from or modifies state (i.e. is not marked `pure`) must be
    //   annotated with the `onlyProxy` and `onlyInitialized` modifiers. This ensures that it can
    //   only be called when it has access to the data in the proxy, otherwise results are likely to
    //   be nonsensical.
    // - This contract deals with important data for the human verification registry system. Ensure that all newly-added
    //   functionality is carefully access controlled using `onlyOwner`, or a more granular access
    //   mechanism.
    // - Do not assign any contract-level variables at the definition site unless they are
    //   `constant`.
    //
    // Additionally, the following notes apply:
    //
    // - Initialisation and ownership management are not protected behind `onlyProxy` intentionally.
    //   This ensures that the contract can safely be disposed of after it is no longer used.
    // - Carefully consider what data recovery options are presented as new functionality is added.
    //   Care must be taken to ensure that a migration plan can exist for cases where upgrades
    //   cannot recover from an issue or vulnerability.

    ///////////////////////////////////////////////////////////////////////////////
    ///                    !!!!! DATA: DO NOT REORDER !!!!!                     ///
    ///////////////////////////////////////////////////////////////////////////////

    /// CONTRACTS

    /// @notice The World ID router contract for verifying proofs
    /// @dev This is marked internal and not immutable because it is set in initilize and kept in the proxy contract storage
    ///      However, it is effective immutable per implementation contract, because it's not set elsewhere
    ///      and the initialize function can only be called once.
	  IWorldID internal worldId;

    /// @notice A HmnBridge contract for each cupported chain. 
    ///         The bridges are responsible for sending verifications (and other state)
    IHmnManagerBridge[] public hmnBridges;

    /// WORLD ID CONFIG

	  /// @dev The contract's external nullifier hash
	  uint256 internal contractNullifier;

    /// @notice For book keeping only
	  string internal appId;
	  string internal actionId;

    /// @dev The World ID verification level (groupId) used for on-chain verification
    uint256 public onChainVerificationLevel;

    /// OTHER CONFIGS

    /// @notice Nonces for verifying device acccounts for signature verification against replay attacks
    mapping(address => uint256) public verificationNonces;

    /// @notice Allowed slack between server clock and blockchain clock in device verification
    uint256 public constant CLOCK_SKEW = 60;
    
    /// @notice Flag value indicating an address was previously used but renounced
    uint256 public constant USED_ADDRESS_FLAG = 1;
    
    /// @notice Maps human (nullifier) hashes to verified address(es) on each chain
    /// @dev Currently, only one address per chain is supported for each user.
    ///      The addresses are stored in an array for future proofing purposes only.
    mapping(uint256 => mapping(BlockChainId => Address32[])) public humanHashToChainAddresses;

    /// @notice Maps addresses on each chain back to their human (nullifier) hash
    mapping(BlockChainId => mapping(Address32 => uint256)) public chainAddressToHumanHash;

    /// @notice Time window for moving funds after renouncing an account
    uint256 public moveOutTime;

    /// @notice Whether previously verified accounts can be reused after renouncing
    bool public allowAccountReuse;

    /// @notice Minimum safety period required before account recovery can complete
    uint256 public minRecoverySafetyPeriod;

    /// @notice User configured recovery timeout period for each address
    mapping(address => uint256) public addressRecoveryTimeout;

    /// @notice Maps addresses to their designated recovery address
    mapping(address => address) public addressToRecoveryAddress;

    /// @notice Maps addresses to their required recovery nullifier hash
    mapping(address => uint256) public addressRecoveryNullifier;

    /// @notice Timestamp when recovery was requested for each address
    mapping(address => uint256) public recoveryRequestedTimestamp;

}