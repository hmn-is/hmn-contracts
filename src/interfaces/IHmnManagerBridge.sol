// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { BlockChainId, Address32 } from "../utils/LibsAndTypes.sol";

interface IHmnManagerBridge {

    function setUntrustFee(uint256 feePercentage) external;

    function setRequiredVerificationLevelForTransfer(uint256 verificationLevel) external;
    
    function setTimeout(uint256 verificationLevel, uint256 timeout) external;

    function setBot(BlockChainId chainId, Address32 account, uint256 blacklistedUntil) external;

    function setPioneer(BlockChainId chainId, Address32 account, bool flag) external;

    function undoPioneering(BlockChainId chainId, Address32 approver32) external;

    function saveVerification(BlockChainId chainId, Address32 account, uint256 verificationLevel, uint256 timestamp) external;

    function renounceAccount(
      BlockChainId chainId,
      Address32 fromAddress,
      uint256 adjustedTimeStampForOldAccount
    ) external;

    function recover(
      BlockChainId chainId,
      Address32 fromAddress,
      Address32 toAddress
    ) external;
}
