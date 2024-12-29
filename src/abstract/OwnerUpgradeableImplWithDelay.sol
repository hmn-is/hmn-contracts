// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CheckInitialized} from "../utils/CheckInitialized.sol";

import {Ownable2StepUpgradeable} from "contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title Owner upgradeable implementation with safety delay
/// @notice An authorisation announcer component that relies authorisations to L2 Bridges
/// @dev This is base class for implementations delegated to by a proxy.
abstract contract OwnerUpgradeableImplWithDelay is Ownable2StepUpgradeable, UUPSUpgradeable, CheckInitialized {

    /// @notice Address of the pending implementation contract for user review
    address private _pendingImplementation;
    
    /// @notice Timestamp when the upgrade delay has elapsed
    uint256 private _upgradeScheduledFor;
    
    /// @notice Safety delay period for upgrades
    uint256 private _upgradeDelay;

    // Add events
    event UpgradeScheduled(address indexed implementation, uint256 scheduledFor);
    event UpgradeCanceled(address indexed implementation);

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
    // - This contract deals with important data for the system. Ensure that all newly-added
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
    ///                             INITIALIZATION                              ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Performs the initialisation steps necessary for the base contracts of this contract.
    /// @dev Must be called during `initialize` before performing any additional steps.
    /// @param upgradeDelay The safety delay period for upgrades in seconds
    function __OwnerUpgradeableImplWithDelay_init(uint256 upgradeDelay) internal virtual onlyInitializing {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _transferOwnership(_msgSender()); // __Ownable2Step_init 'fails' to do this
        _upgradeDelay = upgradeDelay;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                                 ERRORS                                  ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Thrown when an attempt is made to renounce ownership.
    error CannotRenounceOwnership();

    /// @notice Thrown when trying to upgrade before delay period has passed
    error UpgradeDelayNotMet();

    /// @notice Thrown when trying to upgrade to an implementation that wasn't scheduled
    error UpgradeNotScheduled();

    /// @notice Thrown when trying to schedule an upgrade to zero address
    error InvalidImplementation();

    ///////////////////////////////////////////////////////////////////////////////
    ///                             UPGRADE LOGIC                               ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Safety delay period for upgrades to allow users to review upcomming implementations
    ///         and thus prevent malicious administrators from suddently freezing user assets.
    function upgradeDelay() public view virtual onlyProxy onlyInitialized returns (uint256) {
        return _upgradeDelay;
    }

    /// @notice Schedules an upgrade to a new implementation
    /// @param newImplementation Address of the new implementation contract
    function scheduleUpgrade(address newImplementation) external virtual onlyProxy onlyInitialized onlyOwner {
        if (newImplementation == address(0)) revert InvalidImplementation();
        
        _pendingImplementation = newImplementation;
        _upgradeScheduledFor = block.timestamp + upgradeDelay();
        
        emit UpgradeScheduled(newImplementation, _upgradeScheduledFor);
    }

    /// @notice Cancels a scheduled upgrade
    function cancelUpgrade() external virtual onlyProxy onlyInitialized onlyOwner {
        address implementationToCancel = _pendingImplementation;
        _pendingImplementation = address(0);
        _upgradeScheduledFor = 0;
        
        emit UpgradeCanceled(implementationToCancel);
    }

    /// @notice Returns the pending implementation address
    /// @return implementation The address of the pending implementation
    function pendingImplementation() public view onlyProxy onlyInitialized returns (address implementation) {
        return _pendingImplementation;
    }

    /// @notice Returns the timestamp when the upgrade can be executed
    /// @return scheduledFor The timestamp when the upgrade can be executed
    function upgradeScheduledFor() public view onlyProxy onlyInitialized returns (uint256 scheduledFor) {
        return _upgradeScheduledFor;
    }

    /// @notice Is called when upgrading the contract to check whether it should be performed.
    /// @param newImplementation The address of the implementation being upgraded to.
    function _authorizeUpgrade(address newImplementation)
        internal
        virtual
        override
        onlyProxy
        onlyOwner
        onlyInitialized
    {
        // Check that this upgrade was properly scheduled
        if (newImplementation != _pendingImplementation) {
            revert UpgradeNotScheduled();
        }

        // Check that enough time has passed
        if (block.timestamp < _upgradeScheduledFor) {
            revert UpgradeDelayNotMet();
        }

        // Clear the upgrade schedule
        _pendingImplementation = address(0);
        _upgradeScheduledFor = 0;
    }

    /// @notice Ensures that ownership cannot be renounced.
    function renounceOwnership() public view override onlyOwner {
        revert CannotRenounceOwnership();
    }
}
