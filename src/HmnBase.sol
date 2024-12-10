// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./utils/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC1363.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import './interfaces/IHmnManagerBase.sol';

/// @title HMN Token Base Contract
/// @notice Base implementation for the HMN token, shared between L1 and L2 versions
/// @dev Implements ERC20, ERC1363 (transferAndCall), and ERC20Permit (gasless approvals)
abstract contract HmnBase is ERC20, ERC1363, ERC20Permit, Ownable2Step {

    /// @notice Reference to the transfer control contract that enforces human-only transfers
    /// @dev Made immutable to reduce gas costs and prevent modification after deployment
    IHmnManagerBase internal immutable hmnManager;

    /// @notice Maximum fee that can be charged (100 basis points = 1%)
    uint256 public constant MAX_UNTRUST_FEE = 100;

    /// @notice Tracks whether an address has explicitly opted-in to account recovery.
    /// @dev This serves to guarantee an unchangeable ability to opt-out in the future,
    ///      while the upgradable registry transfer control contract contains most of
    ///      the data needed for recovery. 
    mapping(address => bool) public addressRecoveryEnabled;

    /// @notice Permanent whitelist for critical contracts (e.g. DEX routers)
    /// @dev Once added, addresses cannot be removed
    mapping(address => bool) public permanentWhitelist;

    /// @notice Emitted when a fee is paid for an untrusted transfer
    /// @param from Source address of the transfer
    /// @param value Amount of tokens transferred
    /// @param fee Amount of tokens paid as a fee
    event UntrustFeePaid(address indexed from, uint256 value, uint256 fee);

    /// @notice Emitted when a contract is added to the permanent whitelist
    event ContractAddedToPermanentWhitelist(address indexed account);

    /// @param _hmnManager Address of the contract that validates human verification
    constructor(IHmnManagerBase _hmnManager) ERC20("Human", "HMM") ERC20Permit("Human") Ownable2Step(_msgSender()) {
        hmnManager = _hmnManager;
        permanentWhitelist[address(0)] = true; // allow burns
    }
    
    /// @notice Permanently whitelist a critical utility contract such as a defi router or pool for guaranteed tradability
    /// @param account The contract address to whitelist
    function addToPermanentWhitelist(address account) virtual external onlyOwner {
        permanentWhitelist[account] = true;
        emit ContractAddedToPermanentWhitelist(account);
    }

    /// @notice Override of the internal transfer logic from ERC20 to enforce human-only transfers
    /// @dev Called for all transfer operations (transfer, transferFrom, mint, burn)
    /// @param from Source address (zero for mints)
    /// @param to Destination address (zero for burns)
    /// @param value Amount of tokens to transfer
    function _update(address from, address to, uint256 value) internal virtual override {
        // Trustlessly allow anyone with tokens to sell them to permanently whitelisted markets.
        if (permanentWhitelist[to]) {
            super._update(from, to, value);
            return;
        }

        uint256 untrustFee = hmnManager.checkTrust(from, to);
        if (untrustFee == 0 || value == 0) {
            super._update(from, to, value);
        } else {
            // Cap the fee at MAX_UNTRUST_FEE
            uint256 cappedFee = untrustFee > MAX_UNTRUST_FEE ? MAX_UNTRUST_FEE : untrustFee;
            uint256 fee = value * cappedFee / 10000;
            if (fee == 0 && cappedFee > 0) {
                fee = 1;
            }
            uint256 valueAfterFee = value - fee;
            super._update(from, to, valueAfterFee);
            super._update(from, address(hmnManager), fee);
            emit UntrustFeePaid(from, value, fee);
        }
    }

    /// @inheritdoc ERC1363
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1363) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
