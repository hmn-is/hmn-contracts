//SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Address32} from "../utils/LibsAndTypes.sol";

interface IHmnSlave {

    function recover(address fromAddress, address toAddress) external;
}
