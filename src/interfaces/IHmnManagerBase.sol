// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IHmnManagerBase {
    /// @notice Checks if a transfer between addresses is allowed and returns any applicable fee
    /// @param from Source address of the transfer
    /// @param to Destination address of the transfer
    /// @param value Amount of tokens to transfer
    /// @param transferSender Address of the sender of the transfer
    /// @return Fee percentage in basis points (0-100) for unverified transfers
    function verifyTransfer(address from, address to, uint256 value, address transferSender) external returns (uint256);
}
