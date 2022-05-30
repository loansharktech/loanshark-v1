// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../interfaces/IWETH.sol";

contract WFTMUnwrapper {
  address constant wavax = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;

  receive() external payable {}

  /**
   * @notice Convert WAVAX to AVAX and transfer to msg.sender
   * @dev msg.sender needs to send WAVAX before calling this withdraw
   * @param _amount amount to withdraw.
   */
  function withdraw(uint256 _amount) external {
    IWETH(wavax).withdraw(_amount);
    (bool sent, ) = msg.sender.call{ value: _amount }("");
    require(sent, "Failed to send AVAX");
  }
}
