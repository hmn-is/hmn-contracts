// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./utils/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {HmnBase} from "./HmnBase.sol";
import {IHmnManagerMain} from './interfaces/IHmnManagerMain.sol';
import {IHmnManagerBase} from './interfaces/IHmnManagerBase.sol';
import {ICustomArbitrumToken, IL1CustomGateway, IL2GatewayRouter} from './interfaces/IArbitrum.sol';

/// @title HMN L1 Token Contract
/// @notice Implementation of the main HMN token on Ethereum L1, with support for
///         account recovery and Arbitrum L2 bridging
/// @dev Extends HmnBase which implements human-verification transfer controls
contract HmnMain is HmnBase, ICustomArbitrumToken, Ownable2Step {

    /// @notice Thrown when attempting recovery on an account that has disabled it
    error RecoveryDisabled();
    /// @notice Thrown when isArbitrumEnabled is called outside of L2 registration
    error UnexpectedCall();

    /// @notice Emitted when recovery is successfully disabled for an account
    event RecoveryIsDisabled();
    /// @notice Emitted when recovery disabling succeeds even if registry call fails
    event RecoveryForceDisabled();

    /// @notice Emitted when recovery is enabled for an account
    event RecoveryEnabled(address indexed account, address indexed recoverer, uint256 nullifier, uint256 timeout);
    /// @notice Emitted when account recovery process begins
    event AccountRecoveryInitiated(address indexed recoveredAddress, address indexed recoverer);

    /// @dev Flag used during Arbitrum L2 token registration process
    bool private shouldRegisterGateway;
    /// @dev Arbitrum gateway contract for custom token bridging
    IL1CustomGateway private arbitrumGatewayAddress;
    /// @dev Arbitrum router contract for gateway configuration
    IL2GatewayRouter private arbitrumRouterAddress;

    /// @notice Initializes the HMN token with transfer controls and Arbitrum bridge support
    /// @param _hmnTransferControl Address of the transfer control registry
    /// @param _arbitrumGatewayAddress Address of Arbitrum's custom gateway
    /// @param _arbitrumRouterAddress Address of Arbitrum's L2 gateway router
    constructor(IHmnManagerMain _hmnTransferControl, IL1CustomGateway _arbitrumGatewayAddress, IL2GatewayRouter _arbitrumRouterAddress) HmnBase(_hmnTransferControl) Ownable2Step(_msgSender()) {
        arbitrumGatewayAddress = _arbitrumGatewayAddress;
        arbitrumRouterAddress = _arbitrumRouterAddress;
        _mint(_msgSender(), 8200000000 * 10**decimals());
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///                            Account Management                           ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Configures or disables recovery for the caller's account
    /// @param authorizedRecovererAddress Address authorized to initiate recovery, or zero for enabling any address
    /// @param authorizedRecovererHumanHash WorldID nullifier hash of authorized recoverer, or zero for enabling any nullifier.
    ///        Either address or human hash is required for enabling recovery.
    /// @param recoveryTimeout Duration after which recovery can be initiated, or zero to disable recovery
    /// @dev Set all parameters to 0 / address(0) to disable recovery
    function configureRecovery(address authorizedRecovererAddress, uint256 authorizedRecovererHumanHash, uint256 recoveryTimeout) external virtual {
        bool enableRecovery = (recoveryTimeout != 0 && (authorizedRecovererAddress != address(0) || authorizedRecovererHumanHash != 0));
        addressRecoveryEnabled[_msgSender()] = enableRecovery;

        if (enableRecovery) {
            _getManager().configureRecovery(_msgSender(), authorizedRecovererAddress, authorizedRecovererHumanHash, recoveryTimeout);
            emit RecoveryEnabled(_msgSender(), authorizedRecovererAddress, authorizedRecovererHumanHash, recoveryTimeout);
        } else {
            // Do not revert disabling even if the call fails
            try _getManager().configureRecovery(_msgSender(), address(0), 0, 0) {
                emit RecoveryIsDisabled();
            } catch {
                emit RecoveryForceDisabled();
            }
        }
    }

    /// @notice Initiates account recovery process using private key and/or WorldID verification
    /// @param addressToRecover Address of the account to recover
    /// @param root WorldID Merkle root, or zero if not provided
    /// @param nullifierHash Hash proving one-time verification, or zero if not provided
    /// @param proof ZK proof of WorldID verification, or zero if not provided
    function recover(address addressToRecover, uint256 root, uint256 nullifierHash, uint256[8] calldata proof) external virtual {
        if (!addressRecoveryEnabled[addressToRecover]) revert RecoveryDisabled();
        _getManager().recover(_msgSender(), addressToRecover, root, nullifierHash, proof);
        _approve(addressToRecover, _msgSender(), balanceOf(addressToRecover));
        emit AccountRecoveryInitiated(addressToRecover, _msgSender());
    }

    /// @notice Cancels or denies an ongoing recovery request for the caller's account
    /// @dev This is a conveniense function so that the user can interact directly with the coin,
    ///      and does not have to know about the registry.
    /// @return success True if there was a request to deny
    function denyRecoveryRequest() external virtual returns (bool) {
        return _getManager().denyRecoveryRequestFor(_msgSender());
    }

    /// @dev Returns the main (master) account and traffic control manager registry contract with its full interface
    function _getManager() internal view virtual returns (IHmnManagerMain) {
        return IHmnManagerMain(address(hmnManager));
    }

    ///////////////////////////////////////////////////////////////////////////////
    ///            ArbitrumEnabledToken and ICustomToken COMPLIANCE             ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Required by Arbitrum's custom gateway to verify token compatibility
    /// @return Magic value 0xb1 indicating Arbitrum compatibility
    function isArbitrumEnabled() external view override returns (uint8) {
        if (!shouldRegisterGateway) revert UnexpectedCall();
        return uint8(0xb1);
    }

    /// @notice Registers this token on Arbitrum L2 and configures the gateway
    /// @dev This is a one-time setup operation that can only be called by the owner
    function registerTokenOnL2(
        address l2CustomTokenAddress,
        uint256 maxSubmissionCostForCustomGateway,
        uint256 maxSubmissionCostForRouter,
        uint256 maxGasForCustomGateway,
        uint256 maxGasForRouter,
        uint256 gasPriceBid,
        uint256 valueForGateway,
        uint256 valueForRouter,
        address creditBackAddress
    ) public override payable onlyOwner {
        bool prev = shouldRegisterGateway;
        shouldRegisterGateway = true;

        arbitrumGatewayAddress.registerTokenToL2{ value: valueForGateway }(
            l2CustomTokenAddress,
            maxGasForCustomGateway,
            gasPriceBid,
            maxSubmissionCostForCustomGateway,
            creditBackAddress
        );

        arbitrumRouterAddress.setGateway{ value: valueForRouter }(
            address(arbitrumGatewayAddress),
            maxGasForRouter,
            gasPriceBid,
            maxSubmissionCostForRouter,
            creditBackAddress
        );

        shouldRegisterGateway = prev;
    }

    /// @inheritdoc ICustomArbitrumToken
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ICustomArbitrumToken, ERC20, IERC20) returns (bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    /// @inheritdoc ICustomArbitrumToken
    function balanceOf(address account) public view override(ICustomArbitrumToken, ERC20, IERC20) returns (uint256) {
        return super.balanceOf(account);
    }
}
