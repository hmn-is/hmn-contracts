// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IHmnManagerBase {
    /// @notice Checks if a transfer between addresses is allowed and returns any applicable fee
    /// @param from Source address of the transfer
    /// @param to Destination address of the transfer
    /// @return Fee percentage in basis points (0-10000) for untrusted transfers
    function checkTrust(address from, address to) external returns (uint256);
}
