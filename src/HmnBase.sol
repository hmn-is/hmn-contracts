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
    uint256 public constant MAX_FEE_BPS = 100;

    /// @notice Bot fee percentage (1-100) for "confessed bot" accounts, 0 means feature is disabled
    uint256 public botFeeBps;

    /// @notice Tracks whether an address has explicitly opted-in to account recovery.
    /// @dev This serves to guarantee an unchangeable ability to opt-out in the future,
    ///      while the upgradable registry transfer control contract contains most of
    ///      the data needed for recovery. 
    mapping(address => bool) public addressRecoveryEnabled;

    /// @notice Permanent whitelist for critical contracts (e.g. DEX routers)
    /// @dev Once added, addresses cannot be removed
    mapping(address => bool) public permanentWhitelist;

    /// @notice Tracks whether an address has flagged itself as a bot
    /// @dev Once enabled, cannot be disabled
    mapping(address => bool) public botConfessions;

    /// @notice Emitted when a fee is paid for an unverified transfer
    /// @param from Source address of the transfer
    /// @param value Amount of tokens transferred
    /// @param fee Amount of tokens paid as a fee
    event UnverifiedFeePaid(address indexed from, uint256 value, uint256 fee);
    
    /// @notice Emitted when a fee is paid to opt-out of human verification
    /// @param from Source address of the transfer
    /// @param value Amount of tokens transferred
    /// @param fee Amount of tokens paid as a fee
    event BotFeePaid(address indexed from, uint256 value, uint256 fee);

    /// @notice Emitted when a contract is added to the permanent whitelist
    event ContractAddedToPermanentWhitelist(address indexed account);

    /// @notice Emitted when bot account mode is enabled for an address
    event BotConfessed(address indexed account);

    /// @notice Emitted when global bot fee is set or updated
    event BotFeeUpdated(uint256 newFee);

    /// @notice Thrown when bot fee is invalid (must be 1-100)
    error InvalidBotFee();

    /// @param _hmnManager Address of the contract that validates human verification
    constructor(IHmnManagerBase _hmnManager) ERC20("Human", "HMN") ERC20Permit("Human") Ownable2Step(_msgSender()) {
        hmnManager = _hmnManager;
        permanentWhitelist[address(0)] = true; // allow burns
        permanentWhitelist[_msgSender()] = true; // allow mint
    }
    
    /// @notice Enable bot account mode for the caller
    function confessBot() external virtual {
        botConfessions[_msgSender()] = true;
        emit BotConfessed(_msgSender());
    }

    /// @notice Set the global bot fee percentage
    /// @dev In order to guarantee trustless tradeability, the bot fee cannot be unset
    /// @param _botFee New bot fee percentage (1-100)
    function setBotFee(uint256 _botFee) external virtual onlyOwner {
        if (_botFee == 0 || _botFee > MAX_FEE_BPS) {
            revert InvalidBotFee();
        }
        botFeeBps = _botFee;
        emit BotFeeUpdated(_botFee);
    }

    /// @notice Permanently whitelist a critical utility contract such as a defi router or pool for guaranteed tradability
    /// @param account The contract address to whitelist
    function addToPermanentWhitelist(address account) virtual external onlyOwner {
        permanentWhitelist[account] = true;
        emit ContractAddedToPermanentWhitelist(account);
    }

    /// @notice Calculate fee amount based on value and fee basis points
    /// @dev Ensures fee is capped at MAX_FEE_BPS and enforces minimum fee of 1 if any fee is charged
    /// @param value The amount being transferred
    /// @param feeBps The fee in basis points (0-100)
    /// @return The calculated fee amount
    function calculateFee(uint256 value, uint256 feeBps) internal pure returns (uint256) {
        if (value == 0 || feeBps == 0) return 0;
        uint256 cappedFeeBps = feeBps > MAX_FEE_BPS ? MAX_FEE_BPS : feeBps;
        uint256 fee = value * cappedFeeBps / 10000;
        return fee == 0 ? 1 : fee; // Ensure minimum fee of 1
    }

    /// @notice Override of the internal transfer logic from ERC20 to enforce human-only transfers
    /// @dev Called for all transfer operations (transfer, transferFrom, mint, burn)
    /// @param from Source address (zero for mints)
    /// @param to Destination address (zero for burns)
    /// @param value Amount of tokens to transfer
    function _update(address from, address to, uint256 value) internal virtual override {
        // Ability to opt-out from manager verification by instead paying a bot fee.
        // Note: Initially disabled. This is added as a future option to make the coin trustless wrt to the manager.
        if (botFeeBps > 0 && botConfessions[from]) {
            uint256 botFee = calculateFee(value, botFeeBps);
            uint256 valueAfterFee = value - botFee;
            super._update(from, to, valueAfterFee);
            super._update(from, address(hmnManager), botFee);
            emit BotFeePaid(from, value, botFee);
            return;
        }

        // Trustlessly allow anyone with tokens to sell them to permanently whitelisted markets.
        if (permanentWhitelist[to]) {
            super._update(from, to, value);
            return;
        }

        uint256 unverifiedFee = hmnManager.verifyTransfer(from, to);
        uint256 fee = calculateFee(value, unverifiedFee);
        if (fee == 0) {
            super._update(from, to, value);
        } else {
            uint256 valueAfterFee = value - fee;
            super._update(from, to, valueAfterFee);
            super._update(from, address(hmnManager), fee);
            emit UnverifiedFeePaid(from, value, fee);
        }
    }

    /// @inheritdoc ERC1363
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1363) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
