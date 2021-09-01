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

    // TODO: naming. liquidity? or tokens? etc...
    mapping(address => mapping(address => uint256)) reserve;

    address private constant OVM_ETH = 0x4200000000000000000000000000000000000006;

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
        Lib_OVMCodec.Transaction calldata _transaction,
        Lib_OVMCodec.TransactionChainElement calldata _txChainElement,
        Lib_OVMCodec.ChainBatchHeader calldata _batchHeader,
        Lib_OVMCodec.ChainInclusionProof calldata _inclusionProof
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

        // TODO: check if it works.
        bytes4 sig = bytes4(_transaction.data[:4]);
        require(
            sig == bytes4(keccak256("fastWithdraw(address,address,address,uint256,uint256,uint256,uint256,uint32,bytes)")),
            ""
        );

        // Decode Layer 2 transaction data.
        (
            address _l1Token,
            address _l2Token,
            address _to,
            uint256 _amount,
            uint256 _fee,
            uint256 _deadline,
            uint256 _nonce,
            bytes,
        ) = abi.decode(
            _transaction.data,
            address, address, uint256, uint256, uint256, uint256, uint32, bytes
        );

        require(
            _checkFee(fee),
            ""
        );
        require(
            _checkDeadline(deadline),
            ""
        );
        // TODO: liquidity check.

        // This function checks if fast withdrawal has already processed. Do we need to put explicit condition?
        // require(iOVM_L1StandardBridge.fastWithdrawals == false).
        require(
            iOVM_L1StandardBridge.processFastWithdrawal(_nonce) == true,
            "L1 Bridge does not accept processing fast withdrawal."
        );

        if (_l2Token == OVM_ETH) {
            (bool success, ) = _to.call{value: _amount}(new bytes(0));

            require(success, "TransferHelper::safeTransferETH: ETH transfer failed");
        } else {
            reserve[_l1Token][_l2Token] = reserve[_l1Token][_l2Token].sub(_amount);

            // When a withdrawal is finalized on L1, the L1 Bridge transfers the funds to the withdrawer
            IERC20(_l1Token).safeTransfer(_to, _amount);
        }

        ovmL1ClaimableERC721.safeMint(msg.sender, _nonce);

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

    // TODO: add liquidity function
    function addLiquidity(address _l1Token, address _l2Token, uint256 _amount) {
        reserve[_l1Token, _l2Token] += _amount;
    }
}
