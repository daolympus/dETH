// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

interface IFLETHStrategy {
    /// @notice Returns true if the strategy is unwinding, and no new deposits are expected
    function isUnwinding() external view returns (bool);

    /// @notice Converts ETH to LSTs. The LSTs remain in the strategy contract
    function convertETHToLST() external payable;

    /// @notice Converts the strategy's LSTs into ETH and sends it to the receiver
    function withdrawETH(uint256 amount, address receiver) external;

    /// @notice The strategy's LST balance, converted to ETH
    function balanceInETH() external view returns (uint256);

    /// @notice Allows the owner to set the unwinding flag
    function setIsUnwinding(bool isUnwinding_) external;

    /// @notice Allows the owner to unwind the strategy in small amounts into ETH (to avoid price impact)
    function unwindToETH(uint256 ethAmount) external;

    function emergencyRescue() external;
}
