// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IHmnBase is IERC20 {
    function permanentWhitelist(address) external view returns (bool);
} 