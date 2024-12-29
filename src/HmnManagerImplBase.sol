// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {OwnerUpgradeableImplWithDelay} from "./abstract/OwnerUpgradeableImplWithDelay.sol";

import {IHmnManagerBase} from "./interfaces/IHmnManagerBase.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import {IHmnBase} from "./interfaces/IHmnBase.sol";

import './utils/LibsAndTypes.sol';

/// @title HMN Transfer Control Base Implementation
/// @notice Manages human verification and transfer controls for the HMN token across chains
/// @dev Base implementation for L1/L2 specific contracts. Must be used behind an upgradeable proxy.
///      All storage variables are defined here to prevent storage collisions during upgrades.
abstract contract HmnManagerImplBase is OwnerUpgradeableImplWithDelay, IHmnManagerBase {
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
    //        !!!!! STORAGE: DO NOT MODIFY, REORDER, REMOVE OR ADD !!!!!        ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice The HMN token contract address on the chain where the (derived) contract is deployed
    address internal HMN;

    /// @notice Address with permissions for routine registry upkeep operations
    address internal admin;

    /// @notice Current blockchain ID using Wormhole's chain ID scheme
    BlockChainId internal BLOCKCHAIN_ID;

    /// @notice Maps (chainId, address) to verification status
    /// @dev Master mapping on L1, synced to L2s
    mapping(BlockChainId => mapping(Address32 => Verification)) public verifications;
    
    /// @notice Maps verification level to its expiration duration (zero means never expires)
    mapping(uint256 => uint256) public timeouts;
    
    /// @notice Maps (chainId, address) to blacklist expiration timestamp (0 means not blacklisted)
    mapping(BlockChainId => mapping(Address32 => uint256)) public botBlacklist;

    /// @notice Addresses trusted to approve new contracts through their transactions
    mapping(BlockChainId => mapping(Address32 => bool)) public pioneerAccounts;

    /// @notice Current transfer restriction level. See TransferProtectionModes for options
    uint256 public transferProtectionMode; 

    /// @notice Minimum World ID verification level needed for transfers
    uint256 public requiredVerificationLevelForTransfer;
  
    
    /// @notice Maps whitelisted contracts to their approver
    mapping(address => Address32) public contractWhitelist;

    /// @notice Maps approvers to their list of whitelisted contracts
    mapping(Address32 => address[]) public whitelistedContractsByApprover;
    
    /// @notice Special whitelist for contracts that need unrestricted sending capability
    /// @dev Maps sender => recipient (ANYWHERE for any recipient)
    mapping(address => address) public fromToWhitelist;

    /// @dev Minimum verification timeout to ensure tradability
    uint256 internal constant MIN_TIMEOUT = 10 minutes;

    /// @dev A magic address for marking a from-to whitelisted (bridge) contract that is allowed to send anywhere
    address internal constant ANYWHERE = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

    /// @notice Fee percentage for unverified transfers (in basis points, 0-100)
    uint256 public unverifiedFee;

    /// @dev Maximum fee that can be charged (100 basis points = 1%)
    uint256 public constant MAX_FEE_BPS = 100;

    ///////////////////////////////////////////////////////////////////////////////
    ///                                ERRORS                                    ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when a transfer is attempted to an unverified recipient
    /// @param to The address of the unauthorized recipient
    error UnauthorisedRecipient(address to);
  
    /// @notice Thrown when an operation is attempted by an unauthorized account
    /// @param account The address that attempted the unauthorized operation
    error Unauthorised(address account);

    /// @notice Thrown when there's an invalid attempt to whitelist a contract
    /// @param contractAddr The contract address that failed to be whitelisted
    /// @param approverOrZero The address attempting to approve (or zero for removal)
    error UnauthorisedApproverOrInvalidRequest(address contractAddr, address approverOrZero);

    /// @notice Thrown when a transfer involves an unverified contract
    /// @param account The address of the unverified contract
    /// @param hint A message providing guidance on how to resolve the issue
    error UnverifiededContract(address account, string hint);
	  
    /// @notice Thrown when sender's verification level is below required threshold
    /// @param account The address with insufficient verification
    /// @param hint A message providing guidance on how to resolve the issue
    error SenderVerificationLevelInsufficient(address account, string hint);

    /// @notice Thrown when recipient's verification level is below required threshold
    /// @param account The address with insufficient verification
    /// @param hint A message providing guidance on how to resolve the issue
    error DestinationVerificationLevelInsufficient(address account, string hint);

    /// @notice Thrown when sender's verification has expired
    /// @param account The address with expired verification
    /// @param hint A message providing guidance on how to resolve the issue
    error SenderVerificationExpired(address account, string hint);

    /// @notice Thrown when recipient's verification has expired
    /// @param account The address with expired verification
    /// @param hint A message providing guidance on how to resolve the issue
    error DestinationVerificationExpired(address account, string hint);

    /// @notice Thrown when an unverified address attempts to send tokens
    /// @param account The unverified sender address
    /// @param hint A message providing guidance on how to resolve the issue
    error UnverifiedSender(address account, string hint);

    /// @notice Thrown when attempting to send tokens to an unverified address
    /// @param account The unverified recipient address
    /// @param hint A message providing guidance on how to resolve the issue
    error UnverifiedDestination(address account, string hint);

    /// @notice Thrown when a blacklisted bot attempts to transfer tokens
    /// @param account The blacklisted address
    error BlacklistedSender(address account);
    
    /// @notice Thrown when a blacklisted bot attempts to receive tokens
    /// @param account The blacklisted address
    error BlacklistedRecipient(address account);

    /// @notice Thrown when an invalid transfer protection mode is specified
    /// @param mode The invalid mode value
    error InvalidTransferProtectionMode(uint256 mode);

    /// @notice Thrown when a zero or invalid address is provided
    /// @param account The invalid address
    error InvalidAddress(address account);
    
    /// @notice Thrown when an address that should be a contract isn't one
    /// @param account The address that isn't a contract
    error NotAContract(address account);

    /// @notice Thrown when verification timeout is below minimum required duration
    /// @param timeout The invalid timeout value
    error InvalidTimeout(uint256 timeout);

    /// @notice Thrown when attempting to change the already-set HMN token address
    error HmnTokenAddressAlreadySet();

    /// @notice Thrown when a verification level is not found
    /// @param level The verification level that doesn't exist
    error VerificationLevelNotFound(uint256 level);

    /// @notice Thrown when a chain ID is not supported
    /// @param chainId The unsupported chain ID
    error UnsupportedChainId(uint256 chainId);

    /// @notice Thrown when a verification message has an invalid format
    error InvalidVerificationMessage();

    /// @notice Thrown when a verification signature is invalid
    error InvalidVerificationSignature();

    /// @notice Thrown when fee percentage exceeds maximum (100 basis points = 1%)
    /// @param fee The invalid fee percentage
    error InvalidFeePercentage(uint256 fee);

    ///////////////////////////////////////////////////////////////////////////////
    ///                                EVENTS                                    ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Emitted when the HMN token address is set
    /// @param hmn The address of the HMN token contract
    event HmnAddressSet(address indexed hmn);

    /// @notice Emitted when a verification timeout is updated
    /// @param verificationLevel The verification level the timeout applies to
    /// @param timeout The new timeout duration
    event TimeoutSet(uint256 indexed verificationLevel, uint256 timeout);

    /// @notice Emitted when an address's bot status is updated
    /// @param chainId The chain ID where the status was updated
    /// @param account The address whose status was changed
    /// @param blacklistedUntil Timestamp until which the address is blacklisted (0 means not blacklisted)
    event BotStatusSet(BlockChainId indexed chainId, Address32 indexed account, uint256 blacklistedUntil);

    /// @notice Emitted when a verification is saved to the registry
    /// @param chainId The chain ID where the verification was saved
    /// @param account The verified address
    /// @param verificationLevel The level of verification achieved
    /// @param timestamp The timestamp of verification
    event VerificationSaved(BlockChainId indexed chainId, Address32 indexed account, uint256 verificationLevel, uint256 timestamp);

    /// @notice Emitted when an address's pioneer status is updated
    /// @param chainId The chain ID where the status was updated
    /// @param account The address whose status was changed
    /// @param isPioneer Whether the address is granted pioneer status
    event PioneerStatusSet(BlockChainId indexed chainId, Address32 indexed account, bool isPioneer);

    /// @notice Emitted when the transfer protection mode is changed
    /// @param mode The new protection mode
    event TransferProtectionModeSet(uint256 mode);

    /// @notice Emitted when the required verification level for transfers is updated
    /// @param level The new required verification level
    event RequiredVerificationLevelSet(uint256 level);

    /// @notice Emitted when the admin address is updated
    /// @param admin The new admin address
    event AdminSet(address indexed admin);

    /// @notice Emitted when a contract is whitelisted by the owner
    /// @param contractAddr The whitelisted contract address
    /// @param approver The address that approved the whitelist
    event ContractWhitelisted(address indexed contractAddr, address indexed approver);

    /// @notice Emitted when a contract is whitelisted by a pioneer
    /// @param contractAddr The whitelisted contract address
    /// @param approver The pioneer address that approved the whitelist
    event ContractWhitelistedByPioneer(address indexed contractAddr, address indexed approver);

    /// @notice Emitted when a contract is removed from the whitelist
    /// @param contractAddr The removed contract address
    event ContractRemovedFromWhitelist(address indexed contractAddr);

    /// @notice Emitted when the from-to whitelist is adjusted
    /// @param account The sender address being configured
    /// @param toOrAnywhere The allowed recipient or ANYWHERE constant
    event FromToWhitelistAdjusted(address indexed account, address indexed toOrAnywhere);

    /// @notice Emitted when a pioneer's whitelistings are revoked
    /// @param chainId The chain ID where the pioneering was undone
    /// @param approver The pioneer address whose approvals were revoked
    event PioneeringUndone(BlockChainId indexed chainId, Address32 indexed approver);

    /// @notice Emitted when a verification is revoked
    /// @param chainId The chain ID where the verification was revoked
    /// @param account The address whose verification was revoked
    event VerificationRevoked(BlockChainId indexed chainId, Address32 indexed account);

    /// @notice Emitted when a chain is added to supported chains
    /// @param chainId The newly supported chain ID
    event ChainAdded(BlockChainId indexed chainId);

    /// @notice Emitted when a chain is removed from supported chains
    /// @param chainId The removed chain ID
    event ChainRemoved(BlockChainId indexed chainId);

    /// @notice Emitted when unverified fee is updated
    /// @param fee The new fee percentage in basis points
    event UnverifiedFeeSet(uint256 fee);

    ///////////////////////////////////////////////////////////////////////////////
    ///                        ACCESS CONTROL MODIFIERS                         ///
    ///////////////////////////////////////////////////////////////////////////////

    modifier onlyAdminOrOwner() {
        if (_msgSender() != owner() && _msgSender() != admin) revert Unauthorised(_msgSender());
        _;
    }

    modifier onlyAdmin() {
        if (_msgSender() != admin) revert Unauthorised(_msgSender());
        _;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                             INITIALIZATION                              ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @dev Prevents implementation contract from being initialized
    constructor() {
        // When called in the constructor, this is called in the context of the implementation and
        // not the proxy. Calling this thereby ensures that the contract cannot be spuriously
        // initialized on its own.
        _disableInitializers();
    }

    /// @notice Responsible for initialising all of the supertypes of this contract.
    /// @dev Must be called exactly once.
    /// @dev When adding new superclasses, ensure that any initialization that they need to perform
    ///      is accounted for here.
    ///
    /// @custom:reverts string If called more than once.
    function __HmnManagerImplBase_init(uint256 upgradeDelay) internal virtual onlyInitializing {
        __OwnerUpgradeableImplWithDelay_init(upgradeDelay);
    }

    /// @notice Sets the HMN token address
    /// @dev Can only be set once
    function setHmnAddress(address _hmn) external onlyOwner onlyProxy onlyInitialized {
        if (_hmn == address(0)) revert InvalidAddress(_hmn);
        if (HMN != address(0)) revert HmnTokenAddressAlreadySet();
        HMN = _hmn;
        emit HmnAddressSet(_hmn);
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                 CHAIN CENTRALIZED REGISTRY MANAGEMENT                   ///
    ///////////////////////////////////////////////////////////////////////////////
    
    function setTimeout(uint256 _verificationLevel, uint256 _timeout) public virtual onlyAdminOrOwner onlyProxy onlyInitialized {
        if (_timeout != 0 &&_timeout < MIN_TIMEOUT) revert InvalidTimeout(_timeout);
        timeouts[_verificationLevel] = _timeout;
        emit TimeoutSet(_verificationLevel, _timeout);
    }

    function setBot(BlockChainId chainId, Address32 account, uint256 blacklistedUntil) public virtual onlyAdminOrOwner onlyProxy onlyInitialized {
        botBlacklist[chainId][account] = blacklistedUntil;
        emit BotStatusSet(chainId, account, blacklistedUntil);
    }

    function _saveVerification(BlockChainId chainId, Address32 account, uint256 verificatoinLevel, uint256 timestamp) internal virtual {
        verifications[chainId][account] = Verification(verificatoinLevel, timestamp);
        emit VerificationSaved(chainId, account, verificatoinLevel, timestamp);
    }

    function setPioneer(BlockChainId chainId, Address32 account, bool flag) public virtual onlyAdminOrOwner onlyProxy onlyInitialized {
        pioneerAccounts[chainId][account] = flag;
        emit PioneerStatusSet(chainId, account, flag);
    }

    function setTransferProtectionMode(uint256 _transferProtectionMode) public virtual onlyAdminOrOwner onlyProxy onlyInitialized {
        _setTransferProtectionMode(_transferProtectionMode);
        emit TransferProtectionModeSet(_transferProtectionMode);
    }

    function _setTransferProtectionMode(uint256 _transferProtectionMode) internal virtual {
        if (_transferProtectionMode > TransferProtectionModes.VERIFY) revert InvalidTransferProtectionMode(_transferProtectionMode);
        transferProtectionMode = _transferProtectionMode;
    }

    function setRequiredVerificationLevelForTransfer(uint256 newLevel) public virtual onlyAdminOrOwner onlyProxy onlyInitialized {
        requiredVerificationLevelForTransfer = newLevel;
        emit RequiredVerificationLevelSet(newLevel);
    }
    
    function setUnverifiedFee(uint256 newFee) public virtual onlyAdminOrOwner onlyProxy onlyInitialized {
        _setUnverifiedFee(newFee);
        emit UnverifiedFeeSet(newFee);
    }

    function _setUnverifiedFee(uint256 newFee) internal virtual {
        // Allow 1 basis point more than the maximum disables unverified transfers completely
        if (newFee > MAX_FEE_BPS + 1) revert InvalidFeePercentage(newFee);
        unverifiedFee = newFee;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                       CHAIN SPECIFIC MANAGEMENT                         ///
    /////////////////////////////////////////////////////////////////////////////// 

    function setAdmin(address _admin) external virtual onlyOwner onlyProxy onlyInitialized {
        admin = _admin;
        emit AdminSet(_admin);
    }


    /// @notice Manually whitelist (or delist) a utility contract (eg. a defi router or pool).
    /// @param contractAddr The contract address to add
    /// @param approverOrZero The address that approves the contract
    function adjustContractWhitelist(address contractAddr, address approverOrZero) external virtual onlyProxy onlyInitialized onlyOwner {
        _adjustContractWhitelist(contractAddr, approverOrZero);
    }
    
    /// @notice Whitelist (or delist) a utility contract (eg. a defi router or pool) manually,
    ///         or based on pioneer transactions.
    /// @dev    This function is allowed for owner and to pioneer _originated_ token transactions.
    /// @param contractAddr The contract address to add
    /// @param approverOrZero The address that approves the contract
    function _adjustContractWhitelist(address contractAddr, address approverOrZero) internal virtual onlyProxy onlyInitialized {
        if (!isContract(contractAddr)) revert NotAContract(contractAddr);
        Address32 approver32 = approverOrZero.toAddress32();
        if (_msgSender() == owner() && approverOrZero == owner() && contractWhitelist[contractAddr].isZero()) {
            contractWhitelist[contractAddr] = approver32;
            whitelistedContractsByApprover[approver32].push(contractAddr);
            emit ContractWhitelisted(contractAddr, approverOrZero);
        } else if (_msgSender() == owner() && approverOrZero == address(0) && contractWhitelist[contractAddr].isSet()) {
            _removeContractFromWhitelist(contractAddr);
            emit ContractRemovedFromWhitelist(contractAddr);
        } else if (tx.origin == approverOrZero && isPioneer(approverOrZero) && contractWhitelist[contractAddr].isZero()) {
            contractWhitelist[contractAddr] = approver32;
            whitelistedContractsByApprover[approver32].push(contractAddr);
            emit ContractWhitelistedByPioneer(contractAddr, approverOrZero);
        } else {
            revert UnauthorisedApproverOrInvalidRequest(contractAddr, approverOrZero);
        }
    }

    function _removeContractFromWhitelist(address contractAddr) internal virtual onlyProxy onlyInitialized {
        Address32 approver32 = contractWhitelist[contractAddr];
        address[] memory contracts = whitelistedContractsByApprover[approver32];
        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i] == contractAddr) {
                whitelistedContractsByApprover[approver32][i] = contracts[contracts.length - 1];
                whitelistedContractsByApprover[approver32].pop();
                break;
            }
        }
        contractWhitelist[contractAddr] = Address32.wrap(bytes32(0));
    }

    function adjustFromToWhitelist(address account, address toOrAnywhere) external virtual onlyOwner onlyProxy onlyInitialized {
        fromToWhitelist[account] = toOrAnywhere;
        emit FromToWhitelistAdjusted(account, toOrAnywhere);
    }
  
    /// @notice Undo all whitelistings (and revoke status) of a pioneer that has been found deemed unverifiedworthy.
    /// @param approver32 The address whose whitelistings to undo
    function undoPioneering(BlockChainId chainId, Address32 approver32) public virtual onlyAdminOrOwner onlyProxy onlyInitialized {
        address[] memory contracts = whitelistedContractsByApprover[approver32];
        for (uint256 i = 0; i < contracts.length; i++) {
            contractWhitelist[contracts[i]] = Address32.wrap(bytes32(0));
        }
        delete whitelistedContractsByApprover[approver32];
        pioneerAccounts[chainId][approver32] = false;
        emit PioneeringUndone(chainId, approver32);
    }


    ///////////////////////////////////////////////////////////////////////////////
    ///                           IHmnManagerMain COMPLIANCE                    ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Validates whether a transfer between two addresses is allowed (for free or at all)
    /// @return fee percentage [0-1%], if configured, to be applied to unverified transfers
    /// @dev Transfer control algorithm:
    ///      1. If protection mode is ALLOW_ALL, allow all transfers
    ///
    ///      2. Block blacklisted bots
    ///         - Block blacklisted bots from interacting with anyone (note: the token contract still allows sell to whitelisted markets)
    ///         - If mode is BLOCK_BOTS_ONLY, allow all non-bot transfers
    ///
    ///      3. In relaxed modes, allow all transfers to and/or from contracts
    ///         - ALLOW_TO_CONTRACTS: Allow sending to any contract
    ///         - ALLOW_FROM_CONTRACTS: Allow sending from any contract  
    ///         - ALLOW_ALL_CONTRACTS: Allow if either party is a contract
    ///
    ///      4. Core rules based on WorldID verified humanity and trusted pairs
    ///         - Allow explictly enabled transfer pairs
    ///         - Allow transfer if both:
    ///           • Sender is a verified human or a whitelisted contract
    ///           • Recipient is a verified human or a whitelisted contract
    ///
    ///      5. In the default pioneering mode, allow and whitelist all contracts within transactions originating from trusted pioneers.
    ///         This enables protocol learning and trusted network expansion.
    ///
    ///      6. Finally, if all checks fail, either revert with a detailed error or return an unverified fee.
    /// @param from Source address of the transfer
    /// @param to Destination address of the transfer
    function verifyTransfer(address from, address to) public virtual onlyProxy onlyInitialized returns (uint256) {
        // 1. Allow all transfers if protection is disabled
        if (transferProtectionMode == TransferProtectionModes.ALLOW_ALL) return 0;

        // 2. Block blacklisted bots
        uint256 fromBlacklistedUntil = botBlacklist[BLOCKCHAIN_ID][from.toAddress32()];
        uint256 toBlacklistedUntil = botBlacklist[BLOCKCHAIN_ID][to.toAddress32()];
        if (fromBlacklistedUntil > block.timestamp && !IHmnBase(HMN).permanentWhitelist(from)) revert BlacklistedSender(from);
        if (toBlacklistedUntil > block.timestamp) revert BlacklistedRecipient(to);
        if (transferProtectionMode == TransferProtectionModes.BLOCK_BOTS_ONLY) return 0;

        // 3. In relaxed modes, allow all transfers to and/or from contracts
        if (transferProtectionMode == TransferProtectionModes.ALLOW_TO_CONTRACTS && isContract(to)) return 0;
        if (transferProtectionMode == TransferProtectionModes.ALLOW_FROM_CONTRACTS && isContract(from)) return 0;
        if (transferProtectionMode == TransferProtectionModes.ALLOW_ALL_CONTRACTS && (isContract(to) || isContract(from))) return 0;

        // 4. Check Verification registry and whitelists
        bool fromOk = contractWhitelist[from].isSet() || isVerifiedForTransfer(from) || IHmnBase(HMN).permanentWhitelist(from);
        bool toOk = contractWhitelist[to].isSet() || isVerifiedForTransfer(to);
        if (fromOk && toOk) return 0;
        if (fromToWhitelist[from] == ANYWHERE || fromToWhitelist[from] == to) return 0;

        // 5. In pioneering mode, allow trusted users to whitelist contracts during their transactions
        if (transferProtectionMode == TransferProtectionModes.VERIFY_WITH_PIONEERING && isPioneer(tx.origin)) {
            if (!fromOk && isContract(from)) {
                _adjustContractWhitelist(from, tx.origin);
                fromOk = true;
                if (to == from) {
                  toOk = true;
                }
            }
            if (!toOk && isContract(to)) {
                _adjustContractWhitelist(to, tx.origin);
                toOk = true;
            }
            if (fromOk && toOk) return 0;
        }

        // 6. Revert if unverified fee is set to a value higher than allowed
        if (unverifiedFee > MAX_FEE_BPS) {
          revertIfReason(from, true);
          revertIfReason(to, false);
        }
        // Return configured fee for unverified transfer
        return unverifiedFee;
        
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                                     UTILS                               ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Determines if an address belongs to a contract
    /// @dev Uses extcodesize which can return false negatives during contract construction
    /// @param account Address to check
    /// @return True if the address contains code (is a contract)
    function isContract(address account) internal virtual view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /// @notice Provides detailed error messages for failed transfer authorization
    /// @dev Checks verification status and provides context-specific error messages
    /// @param account The address to check
    function revertIfReason(address account, bool isFrom) internal virtual view {
        uint256 timestamp = getVerificationTimestamp(account);
        if (timestamp == 0 && isContract(account)) revert UnverifiededContract(account, getContractHint(account));
        
        bool isUnverified = timestamp == 0 && !isContract(account);
        if (isUnverified && isFrom) revert UnverifiedDestination(account, getAccountHint(account));
        if (isUnverified && !isFrom) revert UnverifiedSender(account, getAccountHint(account));
        
        Verification memory verification = getVerification(account);
        uint256 timeout = timeouts[verification.level]; // Note: defaults to Device timeout of unverified accounts
        bool isExpired = verification.timestamp != 0 && timeout != 0 && verification.timestamp + timeout <= block.timestamp;
        if (isExpired && isFrom) revert DestinationVerificationExpired(account, getAccountHint(account));
        if (isExpired && !isFrom) revert SenderVerificationExpired(account, getAccountHint(account));

        bool isInsufficient = isInsufficientVerificationForTransfer(account);
        if (isInsufficient && isFrom) revert DestinationVerificationLevelInsufficient(account, getAccountHint(account));
        if (isInsufficient && !isFrom) revert SenderVerificationLevelInsufficient(account, getAccountHint(account));
    }

    function getContractHint(address addr) internal virtual view returns (string memory) {
      return string(abi.encodePacked("Contract not trusted, please request trust at https://hmn.is/whitelist/", tx.origin.toString(), "/", addr.toString()));
    }

    function getAccountHint(address account) internal virtual view returns (string memory) {
      if (account == tx.origin) {
        return string(abi.encodePacked("Please visit https://hmn.is/verify/", account.toString()));
      } else {
        return string(abi.encodePacked("Please ask them to visit https://hmn.is/verify/", account.toString()));
      }
    }

    function getVerificationTimestamp(address account) internal virtual view returns (uint256) {
      return getVerification(account).timestamp;
    }

    function getVerification(address account) internal virtual view returns (Verification memory) {
      return verifications[BLOCKCHAIN_ID][account.toAddress32()];
    }

    function isNullVerification(Verification memory verification) internal virtual pure returns (bool) {
      return verification.timestamp == 0;
    }

    function isInsufficientVerificationForTransfer(address account) internal virtual view returns (bool) {
      Verification memory verification = getVerification(account);
      return verification.timestamp != 0 && verification.level < requiredVerificationLevelForTransfer;
    }

    function isVerifiedForTransfer(address account) internal virtual view returns (bool) {
      return isVerified(account, requiredVerificationLevelForTransfer);
    }

    function isVerified(address ethAddress, uint256 requiredLevel) public virtual view onlyProxy onlyInitialized returns (bool) {
        Address32 addr = ethAddress.toAddress32();
        return isVerified(BLOCKCHAIN_ID, addr, requiredLevel);
    }

    function isVerified(BlockChainId chainId, Address32 addr, uint256 requiredLevel) public virtual view onlyProxy onlyInitialized returns (bool) {
        Verification memory verification = verifications[chainId][addr];
        uint256 timeout = timeouts[verification.level];
        bool hasVerification = verification.timestamp != 0;
        bool timeoutOk = (timeout == 0 || verification.timestamp + timeout > block.timestamp);
        return hasVerification && timeoutOk && verification.level >= requiredLevel;
    }

    function isPioneer(address account) public view onlyProxy onlyInitialized returns (bool) {
        return isVerified(account, requiredVerificationLevelForTransfer) && pioneerAccounts[BLOCKCHAIN_ID][account.toAddress32()];
    }

}