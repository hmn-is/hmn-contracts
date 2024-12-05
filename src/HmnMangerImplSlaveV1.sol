// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {HmnMangerImplBase} from "./HmnMangerImplBase.sol";

import {IHmnSlave} from "./interfaces/IHmnSlave.sol";
import {IHmnManagerBridge} from "./interfaces/IHmnManagerBridge.sol";
import {IHmnManagerMain} from "./interfaces/IHmnManagerMain.sol";
import {IWorldID} from "./interfaces/IWorldID.sol";
import './utils/LibsAndTypes.sol';

/// @title Human Verification Registry Implementation Version 1 - HMN coin only
/// @notice A router component that can dispatch group numbers to the correct identity manager
///         implementation.
/// @dev This is the implementation delegated to by a proxy.
contract HmnMangerImplSlaveV1 is HmnMangerImplBase, IHmnManagerBridge {
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
    ///                    !!!!! DATA: DO NOT REORDER !!!!!                     ///
    ///////////////////////////////////////////////////////////////////////////////

    /// CONTRACTS
	  



    ///////////////////////////////////////////////////////////////////////////////
    ///                                  ERRORS                                 ///
    ///////////////////////////////////////////////////////////////////////////////



    ///////////////////////////////////////////////////////////////////////////////
    ///                                  EVENTS                                 ///
    ///////////////////////////////////////////////////////////////////////////////

    event HmnTransferControlInitialized();
    event AccountRenounced(address indexed acc);


    ///////////////////////////////////////////////////////////////////////////////
    ///                             INITIALIZATION                              ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Initializes the contract.
    /// @dev Must be called exactly once.
    /// @dev This is marked `reinitializer()` to allow for updated initialisation steps when working
    ///      with upgrades based upon this contract. Be aware that there are only 256 (zero-indexed)
    ///      initialisations allowed, so decide carefully when to use them. Many cases can safely be
    ///      replaced by use of setters.
    /// @dev This function is explicitly not virtual as it does not make sense to override even when
    ///      upgrading. Create a separate initializer function instead.
    /// @param _requiredVerificationLevelForTransfer The required verification level for transfers
    /// @param _transferProtectionMode The transfer protection mode to set
    /// @param _admin The address of the admin account
    function initialize(
        BlockChainId _chainId,
        uint256 _requiredVerificationLevelForTransfer,
        uint256 _transferProtectionMode,
        address _admin
    ) public reinitializer(1) {
        // Initialize the sub-contracts.
        __HmnManagerImplBase_init();

        // Start of custom initilization logic for this contract and version
        BLOCKCHAIN_ID = _chainId;
        permanentWhitelist[address(0)] = true; // allow burns
        requiredVerificationLevelForTransfer = _requiredVerificationLevelForTransfer;
        setTransferProtectionMode(_transferProtectionMode);
        admin = _admin;

        // Mark the contract as initialized.
        __setInitialized();
        emit HmnTransferControlInitialized();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                 CHAIN CENTRALIZED REGISTRY MANAGEMENT                   ///
    ///////////////////////////////////////////////////////////////////////////////

    function setRequiredVerificationLevelForTransfer(uint256 newLevel) public virtual override (HmnMangerImplBase, IHmnManagerBridge) onlyAdmin onlyProxy onlyInitialized {
        super.setRequiredVerificationLevelForTransfer(newLevel);
    }

    function setUntrustFee(uint256 newFee) public virtual override (HmnMangerImplBase, IHmnManagerBridge) onlyAdmin onlyProxy onlyInitialized {
        super.setUntrustFee(newFee);
    }
    
    function setTimeout(uint256 _verificationLevel, uint256 _timeout) public virtual override (HmnMangerImplBase, IHmnManagerBridge) onlyAdmin onlyProxy onlyInitialized {
        super.setTimeout(_verificationLevel, _timeout);
    }

    function setBot(BlockChainId chainId, Address32 account, uint256 blacklistedUntil) public virtual override (HmnMangerImplBase, IHmnManagerBridge) onlyAdmin onlyProxy onlyInitialized {
      super.setBot(chainId, account, blacklistedUntil);
    }

    function setPioneer(BlockChainId chainId, Address32 account, bool flag) public virtual override (HmnMangerImplBase, IHmnManagerBridge) onlyAdmin onlyProxy onlyInitialized {
      super.setPioneer(chainId, account, flag);
    }

    function undoPioneering(BlockChainId chainId, Address32 approver32) public virtual override (HmnMangerImplBase, IHmnManagerBridge) onlyAdmin onlyProxy onlyInitialized {
      super.undoPioneering(chainId, approver32);
    }


    function renounceAccount(BlockChainId chainId, Address32 fromAddress, uint256 adjustedTimestamp) public virtual onlyAdmin onlyProxy onlyInitialized {
        verifications[chainId][fromAddress].timestamp = adjustedTimestamp;
        emit AccountRenounced(fromAddress.toAddress());
    }

    function recover(BlockChainId /*chainId*/, Address32 fromAddress, Address32 toAddress) public virtual onlyAdmin onlyProxy onlyInitialized {
        IHmnSlave(address(HMN)).recover(fromAddress.toAddress(), toAddress.toAddress());
    }

    function saveVerification(BlockChainId chainId, Address32 account, uint256 verificationLevel, uint256 timestamp) external virtual onlyAdmin onlyProxy onlyInitialized {
        _saveVerification(chainId, account, verificationLevel, timestamp);
    }

}