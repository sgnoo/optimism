// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import { iOVM_L1ClaimableERC721 } from "../../../../contracts/optimistic-ethereum/iOVM/oracle/iOVM_L1ClaimableERC721.sol";

contract OVM_L1ClaimableERC721 is iOVM_L1ClaimableERC721, ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}
}

