// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {OwnerUpgradeableImplWithDelay} from "./abstract/OwnerUpgradeableImplWithDelay.sol";
import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";
import {IERC721} from "openzeppelin-contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

/// @title HMN Safe Implementation V1 for delayed withdrawal requests
/// @notice Implementation that allows delayed, owner-controlled withdrawals of ERC20 and ERC721 tokens.
/// @dev This contract follows a similar delay pattern to the upgrade logic in OwnerUpgradeableImplWithDelay.
///      It requires scheduling a withdrawal request, waiting for the delay period, and then executing the withdrawal.
contract HmnSafeImplV1 is OwnerUpgradeableImplWithDelay, IERC721Receiver {
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

    enum AssetType {
        NONE,
        ERC20,
        ERC721
    }

    /// @notice Withdrawal request mapping: type => token address => amount/tokenId => scheduled timestamp
    mapping(AssetType => mapping(address => mapping(uint256 => uint256))) internal _pendingWithdrawals;

    /// @notice Safety period for withdrawals
    uint256 internal _withdrawDelay;

    ///////////////////////////////////////////////////////////////////////////////
    ///                                ERRORS                                   ///
    ///////////////////////////////////////////////////////////////////////////////

    error WithdrawalNotScheduled(AssetType assetType, address token, uint256 amountOrTokenId);
    error WithdrawalDelayNotMet(AssetType assetType, address token, uint256 amountOrTokenId);
    error NoPendingWithdrawal(AssetType assetType, address token, uint256 amountOrTokenId);
    error WithdrawalAlreadyScheduled(AssetType assetType, address token, uint256 amountOrTokenId);
    error InvalidAssetType();
    error InvalidToken();

    ///////////////////////////////////////////////////////////////////////////////
    ///                                 EVENTS                                  ///
    ///////////////////////////////////////////////////////////////////////////////

    event WithdrawalScheduled(
        AssetType indexed assetType,
        address indexed token,
        uint256 amountOrTokenId,
        uint256 scheduledFor
    );

    event WithdrawalCanceled(
        AssetType indexed assetType,
        address indexed token,
        uint256 amountOrTokenId
    );

    event WithdrawalExecuted(
        AssetType indexed assetType,
        address indexed token,
        uint256 amountOrTokenId
    );

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

    /// @notice Initializes the contract.
    /// @dev Must be called exactly once.
    /// @param withdrawalDelay The safety delay period for withdrawals in seconds
    /// @dev This is marked `reinitializer()` to allow for updated initialisation steps when working
    ///      with upgrades based upon this contract. Be aware that there are only 256 (zero-indexed)
    ///      initialisations allowed, so decide carefully when to use them. Many cases can safely be
    ///      replaced by use of setters.
    function initialize(uint256 withdrawalDelay) public reinitializer(1) {
        // Initialize parent contracts
        __delegateInit();
                
        _withdrawDelay = withdrawalDelay;

        __setInitialized();
    }

    /// @notice Performs the initialisation steps necessary for the base contracts of this contract.
    /// @dev Must be called during `initialize` before performing any additional steps.
    function __delegateInit() internal virtual onlyInitializing {
        __OwnerUpgradeableImplWithDelay_init();
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                            ERC721 COMPLIANCE                            ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Handle the receipt of an NFT
    /// @dev The ERC721 smart contract calls this function on the recipient
    ///      after a `safeTransfer`. This function MUST return the function selector,
    ///      otherwise the transfer will be reverted.
    /// @param operator The address which called `safeTransferFrom` function
    /// @param from The address which previously owned the token
    /// @param tokenId The NFT identifier which is being transferred
    /// @param data Additional data with no specified format
    /// @return bytes4 `onERC721Received` function selector
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external virtual override onlyProxy onlyInitialized returns (bytes4) {
        return this.onERC721Received.selector;
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                          DELAYED WITHDRAW LOGIC                         ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Returns the safety delay period for withdrawals.
    function withdrawDelay() public view virtual onlyProxy onlyInitialized returns (uint256) {
        return _withdrawDelay;
    }

    /// @notice Schedules a withdrawal of tokens.
    /// @param assetType The type of asset (ERC20 or ERC721)
    /// @param token The token address.
    /// @param amountOrTokenId The amount (for ERC20) or tokenId (for ERC721) to withdraw.
    function requestWithdrawal(AssetType assetType, address token, uint256 amountOrTokenId)
        external
        virtual
        onlyProxy
        onlyInitialized
        onlyOwner
    {
        if (token == address(0)) revert InvalidToken();
        if (assetType == AssetType.NONE) revert InvalidAssetType();
        if (_pendingWithdrawals[assetType][token][amountOrTokenId] != 0) 
            revert WithdrawalAlreadyScheduled(assetType, token, amountOrTokenId);

        uint256 scheduledFor = block.timestamp + withdrawDelay();
        _pendingWithdrawals[assetType][token][amountOrTokenId] = scheduledFor;

        emit WithdrawalScheduled(
            assetType, 
            token, 
            amountOrTokenId, 
            scheduledFor
        );
    }

    /// @notice Cancels a previously scheduled withdrawal.
    /// @param assetType The type of asset (ERC20 or ERC721)
    /// @param token The token address for which to cancel the withdrawal
    /// @param amountOrTokenId The amount (for ERC20) or tokenId (for ERC721) to cancel
    function cancelWithdrawal(AssetType assetType, address token, uint256 amountOrTokenId) 
        external 
        virtual 
        onlyProxy 
        onlyInitialized 
        onlyOwner 
    {
        uint256 scheduledFor = _pendingWithdrawals[assetType][token][amountOrTokenId];
        if (scheduledFor == 0) revert NoPendingWithdrawal(assetType, token, amountOrTokenId);

        delete _pendingWithdrawals[assetType][token][amountOrTokenId];

        emit WithdrawalCanceled(assetType, token, amountOrTokenId);
    }

    /// @notice Executes a previously scheduled withdrawal, if the delay has passed.
    /// @param assetType The type of asset (ERC20 or ERC721)
    /// @param token The token address to withdraw
    /// @param amountOrTokenId The amount (for ERC20) or tokenId (for ERC721) to withdraw
    function withdraw(AssetType assetType, address token, uint256 amountOrTokenId) 
        external 
        virtual 
        onlyProxy 
        onlyInitialized 
        onlyOwner 
    {
        uint256 scheduledFor = _pendingWithdrawals[assetType][token][amountOrTokenId];
        if (scheduledFor == 0) revert WithdrawalNotScheduled(assetType, token, amountOrTokenId);
        if (block.timestamp < scheduledFor) revert WithdrawalDelayNotMet(assetType, token, amountOrTokenId);

        // Clear the pending withdrawal before performing actions
        delete _pendingWithdrawals[assetType][token][amountOrTokenId];

        if (assetType == AssetType.ERC20) {
            // There is nothing to be done if the token returns false
            IERC20(token).transfer(_msgSender(), amountOrTokenId);
        } else if (assetType == AssetType.ERC721) {
            IERC721(token).safeTransferFrom(address(this), _msgSender(), amountOrTokenId);
        }

        emit WithdrawalExecuted(assetType, token, amountOrTokenId);
    }


}