// SPDX-License-Identifier: MIT
// @unsupported: ovm
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

/* Interface Imports */
import { iOVM_L1StandardBridge } from "../../../iOVM/bridge/tokens/iOVM_L1StandardBridge.sol";
import { iOVM_L1ERC20Bridge } from "../../../iOVM/bridge/tokens/iOVM_L1ERC20Bridge.sol";
import { iOVM_L2ERC20Bridge } from "../../../iOVM/bridge/tokens/iOVM_L2ERC20Bridge.sol";
import { iOVM_L1Oracle } from "../../../iOVM/oracle/iOVM_L1Oracle.sol";
import { iOVM_L1ClaimableERC721 } from "../../../iOVM/oracle/iOVM_L1ClaimableERC721.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* Library Imports */
import { OVM_CrossDomainEnabled } from "../../../libraries/bridge/OVM_CrossDomainEnabled.sol";
import { Lib_PredeployAddresses } from "../../../libraries/constants/Lib_PredeployAddresses.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

/**
 * @title OVM_L1StandardBridge
 * @dev The L1 ETH and ERC20 Bridge is a contract which stores deposited L1 funds and standard
 * tokens that are in use on L2. It synchronizes a corresponding L2 Bridge, informing it of deposits
 * and listening to it for newly finalized withdrawals.
 *
 * Compiler used: solc
 * Runtime target: EVM
 */
contract OVM_L1StandardBridge is iOVM_L1StandardBridge, OVM_CrossDomainEnabled {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    /********************************
     * External Contract References *
     ********************************/

    address public l2TokenBridge;
    address public l1Oracle;

    // Maps L1 token to L2 token to balance of the L1 token deposited
    mapping(address => mapping (address => uint256)) public deposits;
    // Maps fast withdrawal nonce to information of fast withdrawal.
    mapping(uint256 => FastWithdrawal) public fastWithdrawals;

    /***************
     * Constructor *
     ***************/

    // This contract lives behind a proxy, so the constructor parameters will go unused.
    constructor()
        OVM_CrossDomainEnabled(address(0))
    {}

    /******************
     * Initialization *
     ******************/

    /**
     * @param _l1messenger L1 Messenger address being used for cross-chain communications.
     * @param _l2TokenBridge L2 standard bridge address.
     * @param _l1Oracle
     */
    function initialize(
        address _l1messenger,
        address _l2TokenBridge,
        address _l1Oracle
    )
        public
    {
        require(messenger == address(0), "Contract has already been initialized.");

        messenger     = _l1messenger;
        l2TokenBridge = _l2TokenBridge;
        l1Oracle      = _l1Oracle;
    }

    /**************
     * Depositing *
     **************/

    /** @dev Modifier requiring sender to be EOA.  This check could be bypassed by a malicious
     *  contract via initcode, but it takes care of the user error we want to avoid.
     */
    modifier onlyEOA() {
        // Used to stop deposits from contracts (avoid accidentally lost tokens)
        require(!Address.isContract(msg.sender), "Account not EOA");
        _;
    }

    /**
     * @dev This function can be called with no data
     * to deposit an amount of ETH to the caller's balance on L2.
     * Since the receive function doesn't take data, a conservative
     * default amount is forwarded to L2.
     */
    receive()
        external
        payable
        onlyEOA()
    {
        _initiateETHDeposit(
            msg.sender,
            msg.sender,
            1_300_000,
            bytes("")
        );
    }

    /**
     * @inheritdoc iOVM_L1StandardBridge
     */
    function depositETH(
        uint32 _l2Gas,
        bytes calldata _data
    )
        external
        override
        payable
        onlyEOA()
    {
        _initiateETHDeposit(
            msg.sender,
            msg.sender,
            _l2Gas,
            _data
        );
    }

    /**
     * @inheritdoc iOVM_L1StandardBridge
     */
    function depositETHTo(
        address _to,
        uint32 _l2Gas,
        bytes calldata _data
    )
        external
        override
        payable
    {
        _initiateETHDeposit(
            msg.sender,
            _to,
            _l2Gas,
            _data
        );
    }

    /**
     * @dev Performs the logic for deposits by storing the ETH and informing the L2 ETH Gateway of
     * the deposit.
     * @param _from Account to pull the deposit from on L1.
     * @param _to Account to give the deposit to on L2.
     * @param _l2Gas Gas limit required to complete the deposit on L2.
     * @param _data Optional data to forward to L2. This data is provided
     *        solely as a convenience for external contracts. Aside from enforcing a maximum
     *        length, these contracts provide no guarantees about its content.
     */
    function _initiateETHDeposit(
        address _from,
        address _to,
        uint32 _l2Gas,
        bytes memory _data
    )
        internal
    {
        // Construct calldata for finalizeDeposit call
        bytes memory message =
            abi.encodeWithSelector(
                iOVM_L2ERC20Bridge.finalizeDeposit.selector,
                address(0),
                Lib_PredeployAddresses.OVM_ETH,
                _from,
                _to,
                msg.value,
                _data
            );

        // Send calldata into L2
        sendCrossDomainMessage(
            l2TokenBridge,
            _l2Gas,
            message
        );

        emit ETHDepositInitiated(_from, _to, msg.value, _data);
    }

    /**
     * @inheritdoc iOVM_L1ERC20Bridge
     */
    function depositERC20(
        address _l1Token,
        address _l2Token,
        uint256 _amount,
        uint32 _l2Gas,
        bytes calldata _data
    )
        external
        override
        virtual
        onlyEOA()
    {
        _initiateERC20Deposit(_l1Token, _l2Token, msg.sender, msg.sender, _amount, _l2Gas, _data);
    }

     /**
     * @inheritdoc iOVM_L1ERC20Bridge
     */
    function depositERC20To(
        address _l1Token,
        address _l2Token,
        address _to,
        uint256 _amount,
        uint32 _l2Gas,
        bytes calldata _data
    )
        external
        override
        virtual
    {
        _initiateERC20Deposit(_l1Token, _l2Token, msg.sender, _to, _amount, _l2Gas, _data);
    }

    /**
     * @dev Performs the logic for deposits by informing the L2 Deposited Token
     * contract of the deposit and calling a handler to lock the L1 funds. (e.g. transferFrom)
     *
     * @param _l1Token Address of the L1 ERC20 we are depositing
     * @param _l2Token Address of the L1 respective L2 ERC20
     * @param _from Account to pull the deposit from on L1
     * @param _to Account to give the deposit to on L2
     * @param _amount Amount of the ERC20 to deposit.
     * @param _l2Gas Gas limit required to complete the deposit on L2.
     * @param _data Optional data to forward to L2. This data is provided
     *        solely as a convenience for external contracts. Aside from enforcing a maximum
     *        length, these contracts provide no guarantees about its content.
     */
    function _initiateERC20Deposit(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _l2Gas,
        bytes calldata _data
    )
        internal
    {
        // When a deposit is initiated on L1, the L1 Bridge transfers the funds to itself for future
        // withdrawals. safeTransferFrom also checks if the contract has code, so this will fail if
        // _from is an EOA or address(0).
        IERC20(_l1Token).safeTransferFrom(
            _from,
            address(this),
            _amount
        );

        // Construct calldata for _l2Token.finalizeDeposit(_to, _amount)
        bytes memory message = abi.encodeWithSelector(
            iOVM_L2ERC20Bridge.finalizeDeposit.selector,
            _l1Token,
            _l2Token,
            _from,
            _to,
            _amount,
            _data
        );

        // Send calldata into L2
        sendCrossDomainMessage(
            l2TokenBridge,
            _l2Gas,
            message
        );

        deposits[_l1Token][_l2Token] = deposits[_l1Token][_l2Token].add(_amount);

        emit ERC20DepositInitiated(_l1Token, _l2Token, _from, _to, _amount, _data);
    }

    /*************************
     * Cross-chain Functions *
     *************************/

     /**
     * @inheritdoc iOVM_L1StandardBridge
     */
    function finalizeETHWithdrawal(
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    )
        external
        override
        onlyFromCrossDomainAccount(l2TokenBridge)
    {
        (bool success, ) = _to.call{value: _amount}(new bytes(0));
        require(success, "TransferHelper::safeTransferETH: ETH transfer failed");

        emit ETHWithdrawalFinalized(_from, _to, _amount, _data);
    }

    /**
     * @inheritdoc iOVM_L1ERC20Bridge
     */
    function finalizeERC20Withdrawal(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _data
    )
        external
        override
        onlyFromCrossDomainAccount(l2TokenBridge)
    {
        deposits[_l1Token][_l2Token] = deposits[_l1Token][_l2Token].sub(_amount);

        // When a withdrawal is finalized on L1, the L1 Bridge transfers the funds to the withdrawer
        IERC20(_l1Token).safeTransfer(_to, _amount);

        emit ERC20WithdrawalFinalized(_l1Token, _l2Token, _from, _to, _amount, _data);
    }

     /**
     * @inheritdoc iOVM_L1StandardBridge
     */
    function finalizeETHFastWithdrawal(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _fee,
        uint256 _deadline,
        uint256 _nonce,
        uint256 _l2TxIndex,
        bytes calldata _data
    )
        external
        override
        onlyFromCrossDomainAccount(l2TokenBridge)
    {
        FastWithdrawal storage fastWithdrawal = fastWithdrawals[_nonce];
        if (fastWithdrawal.status == FastWithdrawalStatus.REVERTED) {
            uint256 amount = _amount.add(_fee);
            (bool success, ) = _to.call{value: amount}(new bytes(0));

            require(success, "TransferHelper::safeTransferETH: ETH transfer failed");
            // TODO: which event should be emitted? ETHWithdrawalFinalized or ETHFastWithdrawalFinalized.
            //       I think it betters to use ETHFastWithdrawalFinalized including fast withdrawal success or failure.
        } else if (fastWithdrawal.status == FastWithdrawalStatus.PROCESSED) {
            fastWithdrawal.isETH = true;
            fastWithdrawal.amount = _amount.add(_fee);
            fastWithdrawal.l2TxIndex = _l2TxIndex;
            fastWithdrawal.status = FastWithdrawalStatus.CLAIMABLE;
        }

        // TODO: modify event params.
        emit ETHFastWithdrawalFinalized(_from, _to, _amount, _data);
    }

    /**
     * @inheritdoc iOVM_L1ERC20Bridge
     */
    function finalizeERC20FastWithdrawal(
        address _l1Token,
        address _l2Token,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _fee,
        uint256 _deadline,
        uint256 _nonce,
        uint256 _l2TxIndex, // TODO: naming
        bytes calldata _data
    )
        external
        override
        onlyFromCrossDomainAccount(l2TokenBridge)
    {
        FastWithdrawal storage fastWithdrawal = fastWithdrawals[_nonce];

        if (fastWithdrawal.status == FastWithdrawalStatus.REVERTED) {
            uint256 amount = _amount.add(_fee);
            deposits[_l1Token][_l2Token] = deposits[_l1Token][_l2Token].sub(amount);

            // When a withdrawal is finalized on L1, the L1 Bridge transfers the funds to the withdrawer
            IERC20(_l1Token).safeTransfer(_to, amount);
        } else if (fastWithdrawal.status == FastWithdrawalStatus.PROCESSED) {
            fastWithdrawal.l1Token = _l1Token;
            fastWithdrawal.l2Token = _l2Token;
            fastWithdrawal.amount = _amount.add(_fee);
            fastWithdrawal.l2TxIndex = _l2TxIndex;
            fastWithdrawal.status = FastWithdrawalStatus.CLAIMABLE;
        }

        // TODO: make return types? this event should not be emitted, if it is in the `else` condition.
        emit ERC20FastWithdrawalFinalized(
            _l1Token,
            _l2Token,
            _from,
            _to,
            _amount,
            _data
        );
    }

    // TODO: need better function naming?
    function processFastWithdrawal(uint256 _nonce)
        external
        returns (bool)
    {
        require(
            msg.sender == l1Oracle,
            "Only OVM_Oracle can process fast withdrawal."
        );

        FastWithdrawal storage fastWithdrawal = fastWithdrawals[_nonce];

        // TODO: also need to check l2TxIndex? because of this sentence, we don't have to set `l2TxIndex = 0;`
        require(
            fastWithdrawal.l2TxIndex == 0 && fastWithdrawal.amount == 0,
            "Provided fast withdrawal has already been processed."
        );
        // TODO: we can put fastWithdrawal.status == FastWithdrawalStatus.REVERTED, but it could be confusing.
        require(
            fastWithdrawal.status != FastWithdrawalStatus.PROCESSED &&
            fastWithdrawal.status != FastWithdrawalStatus.CLAIMABLE &&
            fastWithdrawal.status != FastWithdrawalStatus.CLAIMED &&
            fastWithdrawal.status != FastWithdrawalStatus.CHALLENGED,
            "Provided fast withdrawal has already been processed."
        );

        fastWithdrawal.status = FastWithdrawalStatus.PROCESSED;
        // TODO: need return type?

        return true;
    }

    // TODO: param tokenId? _nonce?
    function claimFastWithdrawal (uint256 _nonce) external {
        // TODO: token naming.
        iOVM_L1ClaimableERC721 ovmL1ClaimableERC721 = iOVM_L1Oracle(l1Oracle).ovmL1ClaimableERC721();
        require(
            ovmL1ClaimableERC721.ownerOf(_nonce) == msg.sender, ""
        );

        FastWithdrawal storage fastWithdrawal = fastWithdrawals[_nonce];
        require(
            fastWithdrawal.status == FastWithdrawalStatus.CLAIMABLE, ""
        );

        // TODO: need this require statement?
        require(
            fastWithdrawal.l1Token != address(0) &&
            fastWithdrawal.l2Token != address(0),
            ""
        );
        // TODO: need this require statement?
        require(fastWithdrawal.amount > 0, "");

        // TODO: any other good code?
        if (fastWithdrawal.isETH) {
            _claimFastWithdrawalETH(fastWithdrawal.amount);

            emit FastWithdrawalETHClaimed();
        } else {
            _claimFastWithdrawalERC20(
                fastWithdrawal.l1Token,
                fastWithdrawal.l2Token,
                fastWithdrawal.amount
            );

            emit FastWithdrawalERC20Claimed();
        }
        fastWithdrawal.status = FastWithdrawalStatus.CLAIMED;

        // TODO: burn fToken
        // There is no need to burn fToken, because we have to check challenge posibility after DTD.
    }

    function _claimFastWithdrawalETH (uint256 _amount) internal {
        (bool success, ) = msg.sender.call{value: _amount}(new bytes(0));

        require(success, "TransferHelper::safeTransferETH: ETH transfer failed");
    }

    function _claimFastWithdrawalERC20 (
        address _l1Token,
        address _l2Token,
        uint256 _amount
    )
        internal
    {
        deposits[_l1Token][_l2Token] = deposits[_l1Token][_l2Token].sub(_amount);

        IERC20(_l1Token).safeTransfer(msg.sender, _amount);
    }

    /*****************************
     * Temporary - Migrating ETH *
     *****************************/

    /**
     * @dev Adds ETH balance to the account. This is meant to allow for ETH
     * to be migrated from an old gateway to a new gateway.
     * NOTE: This is left for one upgrade only so we are able to receive the migrated ETH from the
     * old contract
     */
    function donateETH() external payable {}
}
