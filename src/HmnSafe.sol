// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import {HmnProxy} from "./abstract/HmnProxy.sol";

/// @title Proxy for time locked HMN reserve safe
/// @notice A proxy component for a delay-upgradeable HmnSafeImpl
contract HmnSafe is HmnProxy {
    ///////////////////////////////////////////////////////////////////////////////
    ///                    !!!! DO NOT ADD MEMBERS HERE !!!!                    ///
    ///////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////
    ///                             CONSTRUCTION                                ///
    ///////////////////////////////////////////////////////////////////////////////

    /// @notice Constructs a new instance of the HumanRegistry.
    /// @dev This constructor is only called once, and can be called with the encoded call necessary
    ///      to initialize the logic contract.
    ///
    /// @param _logic The initial implementation (delegate) of the contract that this acts as a proxy
    ///        for.
    /// @param _data If this is non-empty, it is used as the data for a `delegatecall` to `_logic`.
    ///        This is usually an encoded function call, and allows for initialising the storage of
    ///        the proxy in a way similar to a traditional solidity constructor.
    constructor(address _logic, bytes memory _data) payable HmnProxy(_logic, _data) {
        // !!!! DO NOT PUT PROGRAM LOGIC HERE !!!!
        // It should go in the `initialize` function of the delegate instead.
    }
}