// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {HmnManagerImplBase} from "./HmnManagerImplBase.sol";
import {HmnManagerImplMainStorageV1} from "./HmnManagerImplMainStorageV1.sol";

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {IHmnManagerBridge} from "./interfaces/IHmnManagerBridge.sol";
import {IHmnManagerMain} from "./interfaces/IHmnManagerMain.sol";
import {IHmnManagerBase} from "./interfaces/IHmnManagerBase.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {ByteHasher, MultiChainAddress, Address32, BlockChainId, Verification, Strings, VerificationLevels, BlockChainIds} from './utils/LibsAndTypes.sol';


/// @title Human Verification Registry Implementation Version 1 - Logic
/// @notice A registry that manages human verification and account recovery on Ethereum Mainnet
/// @dev Implementation contract designed to operate behind a proxy. Key considerations:
/// - All updates must inherit from latest storage implementation to prevent storage clashes 
/// - External functions must use onlyProxy and onlyInitialized modifiers
/// - Carefully control access using onlyOwner or more granular mechanisms
/// - Only use constant contract-level variables
contract HmnManagerImplMainLogicV1 is EIP712Upgradeable, HmnManagerImplBase, HmnManagerImplMainStorageV1, IHmnManagerMain {
    using ByteHasher for bytes;
    using MultiChainAddress for address;
    using MultiChainAddress for Address32;

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
    ///              !!!!! ALL DATA KEPT IN STORAGE CONTRACT !!!!!              ///
    ///////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  ERRORS                                 ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when device timeout configuration is invalid
    error InvalidDeviceTimeout(uint256 timeout);

    /// @notice Thrown when orb timeout configuration is invalid 
    error InvalidOrbTimeout(uint256 timeout);

    /// @notice Thrown when attempting to configure recovery with no verification requirements
    ///         or with zero timeout and non-zero verification requirements
    error InvalidRecoveryConfiguration();

    /// @notice Thrown when attempting to set an invalid verification level for transfers.
    ///         Verification level should be either 0 (DEVICE) or the current on-chain verification level.
    error InvalidVerificationLevel(uint256 level);

    /// @notice Thrown when recovery functionality is disabled
    error RecoveryDisabled();

    /// @notice Thrown when account renouncing is disabled
    error RenounceDisabled();

    /// @notice Thrown when human hash doesn't match authorized address
    error UnauthorisedHumanForAddress(uint256 humanHash, address account);

    /// @notice Thrown when attempting to create a second account for the same human hash
    error UnauthorisedSecondAccount(address existingAddress);

    /// @notice Thrown when human hash doesn't match account's registered hash
    error HumanAccountMismatch(uint256 humanHash);

    /// @notice Thrown when World ID verification fails
    error WorldIDVerificationFailed(
      string reason,
      address router,
      uint256 root,
      uint256 groupId,
      uint256 signalHash,
      uint256 nullifierHash,
      uint256 externalNullifierHash,
      uint256[8] proof
    );


    /// @notice Thrown when attempting to downgrade verify level
    error InsufficientVerificationLevel(address account, uint256 level);

    /// @notice Thrown when using unauthorized human hash
    error UnauthorisedHash(uint256 humanHash);

    /// @notice Thrown when signature verification fails
    error InvalidSignature(
      bytes32 nameHash,
      bytes32 versionHash,
      uint256 chainId,
      address contractAddress,
      address sender,
      uint256 timestamp,
      uint256 groupId,
      uint256 nullifierHash,
      uint256 nonce,
      address signer,
      bytes signature
    );

    /// @notice Thrown when attempting to verify with a future timestamp
    error FutureTimestamp(uint256 timestamp, uint256 blockTimestamp);

    /// @notice Thrown when recovery hasn't been requested
    error RecoveryNotRequested();

    /// @notice Thrown when recovery safety period hasn't elapsed
    error RecoveryNotReady();
    
    /// @notice Thrown when anouncing changes to a bridge fails
    error BridgeCallFailed(uint256 index, address bridge, bytes callData);

    ///////////////////////////////////////////////////////////////////////////////
    ///                                  EVENTS                                 ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when account recovery is requested
    event RecoveryRequested(
        address indexed addressToRecover,
        address indexed requester,
        uint256 safetyPeriodExipiryTime
    );

    /// @notice Emitted when a recovery request is cancelled
    event RecoveryCancelled();

    /// @notice Emitted when account move is initiated
    event AccountMoveInitiated(
        address indexed fromAddress,
        address indexed toAddress,
        uint256 deadline
    );
    
    /// @notice Emitted when account is decoupled from its human
    event AccountRenounced(
        address indexed fromAddress,
        uint256 deadline
    );

    /// @notice Emitted when bridge operation fails
    event BridgeVerificationErrorEvent(address indexed bridge, string reason, BlockChainId chainId, Address32 account, uint256 verificationLevel, uint256 timestamp);


    /// @notice Emitted when recovery is authorized
    event RecoveryAuthorized(address indexed recoverer, address indexed addressToRecover);

    /// @notice Emitted when World ID configuration is updated
    event WorldIdConfigurationUpdated(
        uint256 onChainVerificationLevel,
        string appId,
        string actionId,
        uint256 contractNullifier
    );

    /// @notice Emitted when account management configuration is updated
    event AccountManagementConfigurationUpdated(
        uint256 minRecoverySafetyPeriod,
        uint256 moveOutTime,
        bool allowAccountReuse
    );

    /// @notice Emitted when new bridge is added
    event BridgeAdded(address indexed bridge);

    /// @notice Emitted when recovery is configured for an address
    event RecoveryConfigured(
        address indexed addressConfigured,
        address indexed recoveryAddress,
        uint256 recoveryNullifier,
        uint256 safetyPeriod
    );

    /// @notice Emitted when account is verified
    event AccountVerified(
        address indexed account,
        uint256 indexed humanHash,
        uint256 verificationLevel,
        uint256 timestamp
    );

    ///////////////////////////////////////////////////////////////////////////////
    ///                             INITIALIZATION                              ///
    ///////////////////////////////////////////////////////////////////////////////


    constructor() HmnManagerImplBase() EIP712Upgradeable() {
      // empty constructor
    }


    /// @notice Initializes the contract.
    /// @dev Must be called exactly once.
    /// @dev This is marked `reinitializer()` to allow for updated initialisation steps when working
    ///      with upgrades based upon this contract. Be aware that there are only 256 (zero-indexed)
    ///      initialisations allowed, so decide carefully when to use them. Many cases can safely be
    ///      replaced by use of setters.
    /// @param _admin The admin address for routine operations
    /// @param _worldId The World ID router contract address
    /// @param _requiredVerificationLevelForTransfer The required WorldId verification level (groupId)
    /// @param _appId The World ID app ID
    /// @param _actionId The World ID action ID
    /// @param _orbTimeout The timeout duration for orb (level/groupId 1) verifications (0 for no timeout)
    /// @param _deviceTimeout The timeout duration for device (level/groupId 0) verifications (0 for no timeout)
    /// @param _minRecoverySafetyPeriod The minimum safety period before account recovery can complete
    /// @param _moveOutTime The time window for moving funds out after renouncing an account
    /// @param _allowAccountReuse Whether to allow reuse of previously verified accounts
    /// @param _transferProtectionMode The initial transfer protection mode
    /// @param _upgradeDelay Allow users to review the upgrade before it is applied
    function initialize(
      address _admin,
      IWorldID _worldId,
      uint256 _onChainVerificationLevel,
      string memory _appId,
      string memory _actionId,
      uint256 _orbTimeout,
      uint256 _deviceTimeout,
      uint256 _minRecoverySafetyPeriod,
      uint256 _moveOutTime,
      bool _allowAccountReuse,
      uint256 _transferProtectionMode,
      uint256 _requiredVerificationLevelForTransfer,
      uint256 _upgradeDelay
    ) public reinitializer(1) {
        
        // Initialize parent contracts
        __delegateInit(_upgradeDelay);
        
        // Start of custom initilization logic for this contract and version
        BLOCKCHAIN_ID = BlockChainIds.ETHEREUM;
        timeouts[VerificationLevels.DEVICE] = _deviceTimeout;
        timeouts[VerificationLevels.ORB] = _orbTimeout; 
        admin = _admin;
        allowAccountReuse = _allowAccountReuse;
        worldId = _worldId;
        requiredVerificationLevelForTransfer = _requiredVerificationLevelForTransfer;
        onChainVerificationLevel = _onChainVerificationLevel;
        minRecoverySafetyPeriod = _minRecoverySafetyPeriod;
        moveOutTime = _moveOutTime;
        appId = _appId;
        actionId = _actionId;
        contractNullifier = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();
        _setTransferProtectionMode(_transferProtectionMode);
        
        // Mark the contract as initialized.
        __setInitialized();
    }

    /// @notice Performs the initialisation steps necessary for the base contracts of this contract.
    /// @dev Must be called during `initialize` before performing any additional steps.
    function __delegateInit(uint256 upgradeDelay) internal virtual onlyInitializing {
        __HmnManagerImplBase_init(upgradeDelay);
        __EIP712_init("HmnManager", "1");
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                  MAINNET SPECIFIC CONTRACT MANAGEMENT                   ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Reconfigure the WorldID verification parameters
    /// @dev In order to guarantee verification capability after reconfigurations,
    ///      changing the WorldId contract address is not supported
    ///      and the new parameters are tested before they are applied.
    /// @param root The root of the WorldID Merkle tree
    /// @param humanHash The hash representing the human's identity
    /// @param proof The zero-knowledge proof of WorldID verification
    /// @param _onChainVerificationLevel The new verification level (WorldID groupId) for on-chain verification
    /// @param _appId The new WorldID app ID for verification
    /// @param _actionId The new WorldID action ID for verification
    function reconfigureWorldId(
      uint256 root,
      uint256 humanHash,
      uint256[8] calldata proof,
      uint256 _onChainVerificationLevel,
      string memory _appId,
      string memory _actionId
    )
      external
      virtual
      onlyProxy
      onlyInitialized
      onlyOwner
    {
        uint256 _contractNullifier = abi.encodePacked(abi.encodePacked(_appId).hashToField(), _actionId).hashToField();

        _requireProof(
            root,
            _onChainVerificationLevel,
            _msgSender(),
            humanHash,
            _contractNullifier,
            proof
        );

        appId = _appId;
        actionId = _actionId;
        onChainVerificationLevel = _onChainVerificationLevel;
        contractNullifier = _contractNullifier;

        emit WorldIdConfigurationUpdated(
            _onChainVerificationLevel,
            _appId,
            _actionId,
            _contractNullifier
        );
    }

    /// @notice Reconfigure, enable or disable account management features
    /// @param _minRecoverySafetyPeriod The new minimum timeout period for account recovery
    /// @param _moveOutTime The new time window for moving funds after account renouncement
    /// @param _allowAccountReuse Whether to allow reuse of previously verified accounts
    function reconfigureAccountManagement(
        uint256 _minRecoverySafetyPeriod,
        uint256 _moveOutTime,
        bool _allowAccountReuse
    )
        external
        virtual
        onlyProxy
        onlyInitialized
        onlyOwner
    {
        minRecoverySafetyPeriod = _minRecoverySafetyPeriod;
        moveOutTime = _moveOutTime;
        allowAccountReuse = _allowAccountReuse;

        emit AccountManagementConfigurationUpdated(
            _minRecoverySafetyPeriod,
            _moveOutTime,
            _allowAccountReuse
        );
    }

    /// @notice Add a new block chain bridge for distributing state to slave registries in other block chains
    /// @param bridge The address of the bridge to add
    function addBridge(IHmnManagerBridge bridge) 
        external 
        virtual 
        onlyOwner 
        onlyProxy 
        onlyInitialized 
    {
        if (address(bridge) == address(0)) revert InvalidAddress(address(0));
        Verification memory verification = verifications[BLOCKCHAIN_ID][_msgSender().toAddress32()];
        bridge.saveVerification(BLOCKCHAIN_ID, _msgSender().toAddress32(), verification.level, verification.timestamp); // Test the bridge connection
        hmnBridges.push(bridge);

        emit BridgeAdded(address(bridge));
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                    MAINNET MASTER REGISTRY MANAGEMENT                   ///
    ///////////////////////////////////////////////////////////////////////////////

    function setTimeout(uint256 _verificationLevel, uint256 _timeout) public virtual override (HmnManagerImplBase) onlyOwner onlyProxy onlyInitialized {
        super.setTimeout(_verificationLevel, _timeout);
        _announceToBridges(abi.encodeWithSelector(IHmnManagerBridge.setTimeout.selector, _verificationLevel, _timeout));
    }

    function setBot(BlockChainId chainId, Address32 account, uint256 blacklistedUntil) public virtual override onlyOwner onlyProxy onlyInitialized {
        super.setBot(chainId, account, blacklistedUntil);
        _announceToBridges(abi.encodeWithSelector(IHmnManagerBridge.setBot.selector, chainId, account, blacklistedUntil));
    }

    function setPioneer(BlockChainId chainId, Address32 account, bool flag) public virtual override onlyOwner onlyProxy onlyInitialized {
        super.setPioneer(chainId, account, flag);
        _announceToBridges(abi.encodeWithSelector(IHmnManagerBridge.setPioneer.selector, chainId, account, flag));
    }

    function undoPioneering(BlockChainId chainId, Address32 approver32) public virtual override onlyOwner onlyProxy onlyInitialized {
        super.undoPioneering(chainId, approver32);
        _announceToBridges(abi.encodeWithSelector(IHmnManagerBridge.undoPioneering.selector, chainId, approver32));
    }

    /// @notice Saves a verification sent by user wallet and signed by trusted server
    function saveSignedVerification(
        uint256 level,
        uint256 nullifierHash,
        uint256 timestamp,
        bytes memory signature
    ) external virtual onlyProxy onlyInitialized {
        address sender = _msgSender();
        uint256 nonce = verificationNonces[sender];
        bytes32 structHash = keccak256(abi.encode(
            keccak256("verificationSignature(uint256 level,uint256 nullifierHash,uint256 timestamp,address sender,uint256 nonce)"),
            level,
            nullifierHash,
            timestamp,
            sender,
            nonce
        ));
        bytes32 _hash = _hashTypedDataV4(structHash);
        address signer = ECDSA.recover(_hash, signature);
        if (signer != admin && signer != owner()) revert InvalidSignature(_EIP712NameHash(), _EIP712VersionHash(), block.chainid, address(this), sender, timestamp, level, nullifierHash, nonce, signer, signature);
        verificationNonces[sender]++;

        Verification memory verification = getVerification(sender);
        if (verification.timestamp != 0 && verification.level > level) revert InsufficientVerificationLevel(sender, level);
        if (timestamp > block.timestamp + CLOCK_SKEW) revert FutureTimestamp(timestamp, block.timestamp);
        _requireSenderHashMatch(nullifierHash);

        _saveSenderHash(nullifierHash);
        _saveVerificationL1(nullifierHash, level, timestamp);
    }

    function _saveVerificationL1(uint256 humanHash, uint256 verificationLevel, uint256 timestamp) internal virtual {
        address sender = _msgSender();
        Address32 sender32 = sender.toAddress32();
        _saveVerification(BLOCKCHAIN_ID, sender32, verificationLevel, timestamp);
        _announceSaveVerification(BLOCKCHAIN_ID, sender32, verificationLevel, timestamp);
        emit AccountVerified(
            sender,
            humanHash,
            verificationLevel,
            timestamp
        );
    }

    /// @notice Announces the saving of a verification to other chains
    /// @dev Note: we do not let a successful verificaiton fail in the unlikely event of a bridge failure.
    ///      This guarantees the ability to verify even if the DAO adds a faulty bridge.
    function _announceSaveVerification(BlockChainId chainId, Address32 account, uint256 verificationLevel, uint256 timestamp) internal virtual {
        for (uint256 i = 0; i < hmnBridges.length; i++) {
            try hmnBridges[i].saveVerification(chainId, account, verificationLevel, timestamp) {
                // Success
            } catch Error(string memory reason) {
                emit BridgeVerificationErrorEvent(address(hmnBridges[i]), reason, chainId, account, verificationLevel, timestamp);
            } catch (bytes memory byteData) {
                emit BridgeVerificationErrorEvent(address(hmnBridges[i]), Strings.toHexString(uint256(uint160(bytes20(byteData)))), chainId, account, verificationLevel, timestamp);
            }
        }
    }

    function setRequiredVerificationLevelForTransfer(uint256 newLevel) public virtual override onlyOwner onlyProxy onlyInitialized {
        if (newLevel != VerificationLevels.DEVICE && newLevel != onChainVerificationLevel) revert InvalidVerificationLevel(newLevel);
        super.setRequiredVerificationLevelForTransfer(newLevel);
        _announceToBridges(abi.encodeWithSelector(IHmnManagerBridge.setRequiredVerificationLevelForTransfer.selector, newLevel));
    }

    function setUnverifiedFee(uint256 feePercentage) public virtual override onlyOwner onlyProxy onlyInitialized {
        super.setUnverifiedFee(feePercentage);
        _announceToBridges(abi.encodeWithSelector(IHmnManagerBridge.setUnverifiedFee.selector, feePercentage));
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                         RENOUNCE ACCOUNT FEATURE                        ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Renounce an old lost wallet after verifying user identity, enabling the user to verify a new wallet
    ///         (but not enabling them to recover HMN tokens).
    /// @dev Usecase: lost wallet private key without having configured recovery:
    /// @dev This function is called directly, or via the hmn.is frontend.
    function verifyAndRenounceAccount(uint256 root, uint256 humanHash, uint256[8] calldata proof, address addressToRenounce) external virtual onlyProxy onlyInitialized {
        if (getAddress(humanHash) != addressToRenounce) revert UnauthorisedHumanForAddress(humanHash, addressToRenounce);
        
        // Note: In addition, the target address has to authenticate separately
        _requireProof(root, onChainVerificationLevel, addressToRenounce, humanHash, contractNullifier, proof); 

        // Note: deliberately make an external call in order for renounceAccount to accept the call with different sender address.
        this.renounceAccount(addressToRenounce);
    }

    /// @notice This function removes the mapping from the human hash to to the renounced account, enabling the human to verify with a new address.
    ///         Note that the new account has to be verified separately immediatelly after calling this function, and 
    ///         any HMN tokens have to be moved out during a short overlap period (moveOutTime), after which the old account verification expires.
    /// @dev Usecases:
    ///      - The user wants to switch wallets while still having access to their old wallet (or has verified)
    ///      - The user has reset their WolrdId verificaiton and wants to verify their account with a new human hash.
    /// @dev Called either
    ///      - externally by this contract, after verifying the user via WorldId
    ///      - directly by the user with their old verified account
    function renounceAccount(address fromAddress) public virtual onlyProxy onlyInitialized {
        if (_msgSender() != fromAddress && _msgSender() != address(this)) revert Unauthorised(_msgSender());
        if (moveOutTime == 0) revert RenounceDisabled();
        uint256 humanHash = getHumanHash(fromAddress);
        Address32 fromAddress32 = fromAddress.toAddress32();
        delete humanHashToChainAddresses[humanHash][BLOCKCHAIN_ID];
        chainAddressToHumanHash[BLOCKCHAIN_ID][fromAddress32] = USED_ADDRESS_FLAG;

        // Expedite the expiration of the moved out account
        uint256 timeout = timeouts[verifications[BLOCKCHAIN_ID][fromAddress32].level];
        uint256 fromTimestamp = verifications[BLOCKCHAIN_ID][fromAddress32].timestamp;
        uint256 backdatedTimestamp = block.timestamp - timeout + moveOutTime;
        uint256 adjustedTimeStampForOldAccount = fromTimestamp < backdatedTimestamp ? fromTimestamp : backdatedTimestamp;
        verifications[BLOCKCHAIN_ID][fromAddress32].timestamp = adjustedTimeStampForOldAccount;
        uint256 deadline = adjustedTimeStampForOldAccount + timeout;

        _announceRenounceAccount(fromAddress, adjustedTimeStampForOldAccount);
        emit AccountRenounced(fromAddress, deadline);
    }

    function _announceRenounceAccount(address fromAddress, uint256 adjustedTimeStampForOldAccount) internal virtual {
        _announceToBridges(abi.encodeWithSelector(IHmnManagerBridge.renounceAccount.selector, BLOCKCHAIN_ID, fromAddress.toAddress32(), adjustedTimeStampForOldAccount));
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                         ACCOUNT RECOVERY FEATURE                        ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Configures recovery settings for an address and enables recovery
    ///         This is recovery step 1/3.
    /// @dev Only callable by the HMN token contract. Recovery requires either:
    ///      - A specific recovery address that must sign the recovery request, or
    ///      - A specific human hash (WorldID nullifier) that must be proven during recovery
    ///      - Or both
    /// @param addressToConfigure The address to configure recovery for
    /// @param authorizedRecoveryAddress Optional trusted address that can initiate recovery
    /// @param authorizedRecoveryNullifier Optional WorldID nullifier that can initiate recovery
    /// @param recoverySafetyPeriod Mandatory waiting period before recovery completes
    function configureRecovery(
        address addressToConfigure,
        address authorizedRecoveryAddress, 
        uint256 authorizedRecoveryNullifier,
        uint256 recoverySafetyPeriod
    ) public virtual onlyProxy onlyInitialized {
        if (_msgSender() != HMN) revert Unauthorised(_msgSender());
        if (minRecoverySafetyPeriod == 0) revert RecoveryDisabled();
        if (authorizedRecoveryAddress == address(0) && authorizedRecoveryNullifier == 0 && recoverySafetyPeriod != 0) revert InvalidRecoveryConfiguration();
        if (recoverySafetyPeriod != 0 && recoverySafetyPeriod < minRecoverySafetyPeriod) revert InvalidTimeout(recoverySafetyPeriod);

        addressToRecoveryAddress[addressToConfigure] = authorizedRecoveryAddress;
        addressRecoveryNullifier[addressToConfigure] = authorizedRecoveryNullifier;
        addressRecoveryTimeout[addressToConfigure] = recoverySafetyPeriod;
        _denyRecoveryRequest(addressToConfigure);

        emit RecoveryConfigured(
            addressToConfigure,
            authorizedRecoveryAddress,
            authorizedRecoveryNullifier,
            recoverySafetyPeriod
        );
    }

    /// @notice Initiates account recovery process with the configure private key and/or WorldID proof
    ///         This is recovery step 2/3.
    /// @dev Starts the safety period timer. Recovery can be triggered after the period expires.
    /// @param addressToRecover The address being recovered
    /// @param root The WorldID merkle root, if proveided
    /// @param humanHash The WorldID nullifier hash, if provided 
    /// @param proof The WorldID zero-knowledge proof, if provided
    function requestRecovery(
        address addressToRecover,
        uint256 root,
        uint256 humanHash,
        uint256[8] calldata proof
    ) external virtual onlyProxy onlyInitialized {
        _authenticateRecoveryRequest(_msgSender(), addressToRecover, root, humanHash, proof);
        recoveryRequestedTimestamp[addressToRecover] = block.timestamp;
        emit RecoveryRequested(_msgSender(), addressToRecover, block.timestamp + addressRecoveryTimeout[addressToRecover]);
    }

    /// @notice Validates recovery request after safety period
    ///         This is recovery step 3/3.
    /// @dev Usecase: a user has lost wallet keys or died, and the safety period has elapsed.
    /// @dev Called by HMN contract to verify recovery is authorized and safety period has elapsed.
    ///      This function re-authorizes the recoverer, and, if the safety period has elapsed,
    ///      renounces the old account and announces the right of the recoverer to withdrawl HMN tokens in slave chains.
    /// @param recoverer Address attempting recovery
    /// @param addressToRecover Address being recovered
    /// @param root WorldID merkle root
    /// @param humanHash WorldID nullifier hash 
    /// @param proof WorldID zero-knowledge proof
    function recover(
        address recoverer,
        address addressToRecover,
        uint256 root,
        uint256 humanHash,
        uint256[8] calldata proof
    ) external virtual onlyProxy onlyInitialized {
        if (_msgSender() != HMN) revert Unauthorised(_msgSender());
        _authenticateRecoveryRequest(recoverer, addressToRecover, root, humanHash, proof);
        if (recoveryRequestedTimestamp[addressToRecover] == 0) revert RecoveryNotRequested();
        if (block.timestamp < recoveryRequestedTimestamp[addressToRecover] + addressRecoveryTimeout[addressToRecover]) revert RecoveryNotReady();
        
        recoveryRequestedTimestamp[addressToRecover] = 0;
        renounceAccount(addressToRecover);
        _announceRecover(addressToRecover, recoverer);        
        emit RecoveryAuthorized(recoverer, addressToRecover);
    }

    function _announceRecover(address fromAddress, address toAddress) internal virtual {
        for (uint256 i = 0; i < hmnBridges.length; i++) {
            hmnBridges[i].recover(BLOCKCHAIN_ID, fromAddress.toAddress32(), toAddress.toAddress32());
        }
    }

    /// @notice Internal validation of recovery requests
    /// @dev Checks that:
    /// - Recovery is enabled globally and for this address
    /// - Recoverer matches authorized recovery address, if set
    /// - Human hash matches authorized recovery nullifier, if set
    /// - WorldID proof is valid, if autohrized recovery nullfier is sets
    function _authenticateRecoveryRequest(
        address recoverer,
        address addressToRecover,
        uint256 root,
        uint256 humanHash,
        uint256[8] calldata proof
    ) internal view virtual {
        if (minRecoverySafetyPeriod == 0) revert RecoveryDisabled();
        if (addressToRecover == address(0)) revert InvalidAddress(addressToRecover);
        if (addressRecoveryTimeout[addressToRecover] == 0) revert RecoveryDisabled();
        if (addressToRecoveryAddress[addressToRecover] == address(0) && addressRecoveryNullifier[addressToRecover] == 0) revert RecoveryDisabled();
        if (addressToRecoveryAddress[addressToRecover] != address(0) && addressToRecoveryAddress[addressToRecover] != recoverer) revert Unauthorised(recoverer);
        if (addressRecoveryNullifier[addressToRecover] != 0 && addressRecoveryNullifier[addressToRecover] != humanHash) revert UnauthorisedHash(humanHash);
        _requireProof(root, onChainVerificationLevel, recoverer, humanHash, contractNullifier, proof);
    }

    /// @notice Cancels a pending recovery request
    /// @dev Can be called directly by the address being recovered or via the HMN contract
    /// @param addressToCancel The address with pending recovery to cancel
    /// @return true if a recovery request was cancelled, false if none existed
    function denyRecoveryRequestFor(
        address addressToCancel
    ) external virtual onlyProxy onlyInitialized returns (bool) {
        if (_msgSender() != HMN && _msgSender() != addressToCancel) revert Unauthorised(_msgSender());
        return _denyRecoveryRequest(addressToCancel);
    }
    
    function _denyRecoveryRequest(address addressToCancel) internal returns (bool) {
        if (recoveryRequestedTimestamp[addressToCancel] != 0) {
          recoveryRequestedTimestamp[addressToCancel] = 0;
          emit RecoveryCancelled();
          return true;
        }
        return false;
    }

    /// @inheritdoc HmnManagerImplBase
    /// @dev For convenience, cancel recovery request for tx.origin, since it has to be in possession of its private keys to send this transaction
    /// @dev Note that this automatic cancellation does not trigger for contract wallets interacted with via meta-transactions.
    ///      For contract wallets, recovery must be denied manually, or through verification.
    function verifyTransfer(address from, address to) public virtual override (HmnManagerImplBase, IHmnManagerBase) onlyProxy onlyInitialized returns (uint256) {
        if (_msgSender() == HMN) _denyRecoveryRequest(tx.origin);
        return super.verifyTransfer(from, to);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                           HUMAN VERIFICATION                            ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Verifies a wallet address a new unique human, or renews the verification for an existing address.
	  /// @param root The root of the Merkle tree (returned by the JS widget).
	  /// @param humanHash The nullifier hash for this proof, preventing double signaling (returned by the JS widget).
	  /// @param proof The zero-knowledge proof that demonstrates the claimer is registered with World ID (returned by the JS widget).
	  function registerVerification(uint256 root, uint256 humanHash, uint256[8] calldata proof) external virtual onlyProxy onlyInitialized {
        _requireSenderHashMatch(humanHash);
        
        _requireProof(
            root,
            onChainVerificationLevel,
            _msgSender(),
            humanHash,
            contractNullifier,
            proof
        );

        _denyRecoveryRequest(_msgSender());
        _saveSenderHash(humanHash);
        _saveVerificationL1(humanHash, onChainVerificationLevel, block.timestamp);
    }

    function _requireSenderHashMatch(uint256 humanHash) internal virtual view {
        uint256 existingHumanHash = getHumanHash(_msgSender());
        address existingAddress = getAddress(humanHash);
        bool humanHashInUse = existingHumanHash != 0 && (existingHumanHash != USED_ADDRESS_FLAG || !allowAccountReuse);
        if (existingAddress != address(0) && existingAddress != _msgSender()) revert UnauthorisedSecondAccount(existingAddress);
        if (humanHashInUse && existingHumanHash != humanHash) revert HumanAccountMismatch(existingHumanHash);
    }

    function _saveSenderHash(uint256 humanHash) internal virtual {
        Address32 sender32 = _msgSender().toAddress32();
        humanHashToChainAddresses[humanHash][BLOCKCHAIN_ID] = [sender32];
        chainAddressToHumanHash[BLOCKCHAIN_ID][sender32] = humanHash;
    }

    function _requireProof(
        uint256 root,
        uint256 level, // verification level / groupId
        address account,
        uint256 humanNullifier,
        uint256 _contractNullifier,
        uint256[8] calldata proof
    ) internal view virtual {
        uint256 signalHash = abi.encodePacked(account).hashToField();
        try worldId.verifyProof(
            root,
            level,
            signalHash,
            humanNullifier,
            _contractNullifier,
            proof
        ) {
            return;
        } catch (bytes memory byteData) {
            // Possible error signatures:
            // 0x00 - Possibly SemaphoreVerifier.verifyProof's 'Check pairing equation' static call revert with no data
            // 0x7fcdd1f4 - ProofInvalid()
            // 0xa54f8e27 - PublicInputNotInField()
            // 0x09bde339 - InvalidProof()
            // 0x3ae7359e - ExpiredRoot() Thrown when attempting to validate a root that has expired.
            // 0xddae3b71 - NonExistentRoot() Thrown when attempting to validate a root that has yet to be added to the root history.
            // 0xbaa3de5f - InvalidVerifier() Thrown when a verifier is initialized to be the zero address
            // 0x4fdab253 - InvalidVerifierLUT()
            // 0x8833b8c0 - UnsupportedTreeDepth(uint8)
            // 0xa0b1d72d - MismatchedInputLengths()
            // 0x8e4a23d6 - Unauthorized(address)
            revert WorldIDVerificationFailed(
                Strings.toHexString(uint256(uint160(bytes20(byteData)))),
                address(worldId),
                root,
                level,
                signalHash,
                humanNullifier,
                _contractNullifier,
                proof
            );
        }
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                                     UTILS                               ///
    ///////////////////////////////////////////////////////////////////////////////

    function getAddress(uint256 humanHash) public view returns (address) {
        Address32[] storage addresses = humanHashToChainAddresses[humanHash][BLOCKCHAIN_ID];
        if (addresses.length > 0) return addresses[0].toAddress();
        return address(0);
    }

    function getHumanHash(address account) public view returns (uint256) {
        return chainAddressToHumanHash[BLOCKCHAIN_ID][account.toAddress32()];
    }

    function _announceToBridges(bytes memory callData) internal virtual {
        for (uint256 i = 0; i < hmnBridges.length; i++) {
            (bool success,) = address(hmnBridges[i]).call(callData);
            if (!success) revert BridgeCallFailed(i, address(hmnBridges[i]), callData);
        }
    }

}