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
    //   the latest version of the storage implementation. This prevents storage clashes.
    // - Do not assign any contract-level variables at the definition site unless they are
    //   `constant`.

    ///////////////////////////////////////////////////////////////////////////////
    ///              !!!!! DATA: DO NOT REORDER OR DELETE !!!!!                 ///
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