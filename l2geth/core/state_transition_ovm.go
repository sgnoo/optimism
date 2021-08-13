package core

import (
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/core/vm"
	"github.com/ethereum/go-ethereum/rollup/dump"
)

var ZeroAddress = common.HexToAddress("0x0000000000000000000000000000000000000000")

func toExecutionManagerRun(evm *vm.EVM, msg Message) (Message, error) {
	outputmsg, err := modMessage(
		msg,
		msg.From(),
		msg.To(),
		msg.Data(),
		evm.Context.GasLimit,
	)
	if err != nil {
		return nil, err
	}

	return outputmsg, nil
}

func AsOvmMessage(tx *types.Transaction, signer types.Signer, decompressor common.Address, gasLimit uint64) (Message, error) {
	msg, err := tx.AsMessage(signer)
	if err != nil {
		// This should only be allowed to pass if the transaction is in the ctc
		// already. The presence of `Index` should specify this.
		index := tx.GetMeta().Index
		if index == nil {
			return msg, fmt.Errorf("Cannot convert tx to message in asOvmMessage: %w", err)
		}
	}

	// Queue origin L1ToL2 transactions do not go through the
	// sequencer entrypoint. The calldata is expected to be in the
	// correct format when deserialized from the EVM events, see
	// rollup/sync_service.go.
	if msg.QueueOrigin() == types.QueueOriginL1ToL2 {
		return msg, nil
	}

	// Sequencer transactions get sent to the "sequencer entrypoint," a contract that decompresses
	// the incoming transaction data.
	outmsg, err := modMessage(
		msg,
		msg.From(),
		msg.To(),
		msg.Data(),
		gasLimit,
	)

	if err != nil {
		return msg, fmt.Errorf("Cannot mod message: %w", err)
	}

	return outmsg, nil
}

func EncodeSimulatedMessage(msg Message, timestamp, blockNumber *big.Int, executionManager, stateManager dump.OvmDumpAccount) (Message, error) {
	return modMessage(
		msg,
		msg.From(),
		msg.To(),
		msg.Data(),
		msg.Gas(),
	)
}

func modMessage(
	msg Message,
	from common.Address,
	to *common.Address,
	data []byte,
	gasLimit uint64,
) (Message, error) {
	outmsg := types.NewMessage(
		from,
		to,
		msg.Nonce(),
		common.Big0,
		gasLimit,
		msg.GasPrice(),
		data,
		false,
		msg.L1MessageSender(),
		msg.L1BlockNumber(),
		msg.QueueOrigin(),
	)

	return outmsg, nil
}
