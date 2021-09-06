// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Interface Imports */
import { iOVM_L1FeeManager } from "../../../../contracts/optimistic-ethereum/iOVM/oracle/iOVM_L1Oracle.sol";

contract OVM_L1FeeManager is iOVM_L1FeeManager {

    // TODO: test code for calculating gasUsed.
    uint256 public gasLimit; // gasLimit for Oracle to process `processFastWithdrawal` transaction.
                             // gasLimit can change when after specific hardfork, some opcodes change.

    // // TODO: variable name.
    uint256 public minFee; // minimum fee to accept request for fast withdrawal.

    constructor () {
        // TODO: interface check to get liqudiity amount.
        //       The amount will be used for dynamic fee system.
    }

    function setGasLimit (uint256 _gasLimit) external {
        gasLimit = _gasLimit;
    }

    // TODO: set dynamic setMinFee model.
    function setMinFee (uint256 _minFee) external {
        minFee = _minFee;
    }

    function checkETHFee (uint256 _fee) external returns (bool) {
        uint256 fare = gasLimit * block.basefee; // transaction fee in wei.

        return minFee < _fee.sub(fare);
    }

    function checkERC20Fee (address _token, uint256 _fee) external returns (bool) {
        // TODO: import price oracle contract. e.g. 1inch (https://github.com/1inch/offchain-oracle)
        uint256 rate = 1Inch.getRateToEth(_token, false);
        uint256 fee = _fee * rate;

        uint256 fare = gasLimit * block.basefee; // transaction fee in wei.

        return minFee < fee.sub(fare);
    }
}
