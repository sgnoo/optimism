// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Library Imports */
import { Lib_OVMCodec } from "../../libraries/codec/Lib_OVMCodec.sol";

/* Interface Imports */
import { iOVM_CanonicalTransactionChain } from "../../../../contracts/optimistic-ethereum/iOVM/chain/iOVM_CanonicalTransactionChain.sol";
import { iOVM_L1StandardBridge } from "../../../../contracts/optimistic-ethereum/iOVM/bridge/tokens/iOVM_L1StandardBridge.sol";
import { iOVM_L1Oracle } from "../../../../contracts/optimistic-ethereum/iOVM/oracle/iOVM_L1Oracle.sol";
import { iOVM_L1ClaimableERC721 } from "../../../../contracts/optimistic-ethereum/iOVM/oracle/iOVM_L1ClaimableERC721.sol";

contract OVM_Oracle is iOVM_L1Oracle {

    iOVM_L1StandardBridge public ovmL1StandardBridge;
    iOVM_CanonicalTransactionChain public ovmCanonicalTransactionChain;
    iOVM_L1ClaimableERC721 public ovmL1ClaimableERC721;

    bytes4 private constant _INTERFACE_ID_FAST_WITHDRAW    = 0xfc2bb3a8; // fastWithdraw(address,uint256,uint256,uint256,uint256,uint32,bytes)
    bytes4 private constant _INTERFACE_ID_FAST_WITHDRAW_TO = 0xdaaab375; // fastWithdrawTo(address,address,uint256,uint256,uint256,uint256,uint32,bytes)

    function initialize (
        address _ovmL1StandardBridge,
        address _ovmCanonicalTransactionChain,
        address _ovmL1ClaimableERC721
    )
        external
    {
        require(
            _ovmL1StandardBridge          != address(0) &&
            _ovmCanonicalTransactionChain != address(0) &&
            _ovmL1ClaimableERC721         != address(0),
            "Must provide contract address"
        )
        ovmL1StandardBridge          = iOVM_L1StandardBridge(_ovmL1StandardBridge);
        ovmCanonicalTransactionChain = iOVM_CanonicalTransactionChain(_ovmCanonicalTransactionChain);
        ovmL1ClaimableERC721         = iOVM_L1ClaimableERC721(_ovmL1ClaimableERC721);
    }

    function processFastWithdrawal (
        Lib_OVMCodec.Transaction memory _transaction,
        Lib_OVMCodec.TransactionChainElement memory _txChainElement,
        Lib_OVMCodec.ChainBatchHeader memory _batchHeader,
        Lib_OVMCodec.ChainInclusionProof memory _inclusionProof
    ) external returns (bool) {
        require(
            iOVM_CanonicalTransactionChain.verifyTransaction(
                _transaction,
                _txChainElement,
                _batchHeader,
                _inclusionProof
            ),
            "Invalid transaction inclusion proof."
        );

        // TODO: check
        bytes4 sig;
        assembly {
            sig := mload(add(_transaction.data, add(0x20, 0)))
        }

        require(
            sig == _INTERFACE_ID_FAST_WITHDRAW || sig == _INTERFACE_ID_FAST_WITHDRAW_TO,
            ""
        );

        uint256 _fee;
        uint256 _amount;
        uint256 _deadline;
        uint256 _nonce;
        if (sig == _INTERFACE_ID_FAST_WITHDRAW) {
            (, _amount, _fee, _deadline, _nonce, ,) =
                abi.decode(_transaction.data, address, uint256, uint256, uint256, uint256, uint32, bytes));
        } else {
            (, , _amount, _fee, _deadline, _nonce, ,) =
                abi.decode(_transaction.data, address, address, uint256, uint256, uint256, uint256, uint32, bytes));
        }
        // TODO: amount check?

        require(
            _checkFee(fee),
            ""
        );
        require(
            _checkDeadline(deadline),
            ""
        );

        // This function checks if fast withdrawal has already processed. Do we need to put explicit condition?
        // require(iOVM_L1StandardBridge.fastWithdrawals == false).
        require(
            iOVM_L1StandardBridge.processFastWithdrawal(_nonce),
            ""
        );

        // TODO: make NFT tokens for FW. fToken id should be claimId.
        ovmL1ClaimableERC721.safeMint(_to, msg.sender);

        emit ProcessedFastWithdrawal(_nonce);
        return true;
    }

    function checkFee () {
        if (feeManager == address(0)) {
            return true;
        }
    }

    function checkDeadline () {
        if (deadlineManager == address(0)) {
            return true;
        }
    }
}
