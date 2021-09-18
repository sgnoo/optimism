// SPDX-License-Identifier: MIT
pragma solidity >0.5.0 <0.8.0;
pragma experimental ABIEncoderV2;

interface iOVM_L1FeeManager {

    /********************
     * Public Functions *
     ********************/

    function setGasLimit (uint256 _gasLimit) external;

    // TODO: set dynamic setMinFee model.
    function setMinFee (uint256 _minFee) external;

    function checkETHFee (uint256 _fee) external returns (bool);

    function checkERC20Fee (address _token, uint256 _fee) external returns (bool);
}
