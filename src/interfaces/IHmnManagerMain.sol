// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IHmnManagerBase} from "./IHmnManagerBase.sol";

interface IHmnManagerMain is IHmnManagerBase {
    
    function recover(address recoverer, address addressToRecover, uint256 root, uint256 humanHash, uint256[8] calldata proof) external;
    
    function denyRecoveryRequestFor(address addressToCancel) external returns (bool);

    function configureRecovery(address account, address recoverer, uint256 nullifier, uint256 timeout) external;
    
}