// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { SafeERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

library LibUniversalERC20UpgradeableAVAX {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  IERC20Upgradeable private constant _AVAX_ADDRESS =
    IERC20Upgradeable(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);
  IERC20Upgradeable private constant _ZERO_ADDRESS =
    IERC20Upgradeable(0x0000000000000000000000000000000000000000);

  function isAVAX(IERC20Upgradeable token) internal pure returns (bool) {
    return (token == _ZERO_ADDRESS || token == _AVAX_ADDRESS);
  }

  function univBalanceOf(IERC20Upgradeable token, address account) internal view returns (uint256) {
    if (isAVAX(token)) {
      return account.balance;
    } else {
      return token.balanceOf(account);
    }
  }

  function univTransfer(
    IERC20Upgradeable token,
    address payable to,
    uint256 amount
  ) internal {
    if (amount > 0) {
      if (isAVAX(token)) {
        (bool sent, ) = to.call{ value: amount }("");
        require(sent, "Failed to send AVAX");
      } else {
        token.safeTransfer(to, amount);
      }
    }
  }

  function univApprove(
    IERC20Upgradeable token,
    address to,
    uint256 amount
  ) internal {
    require(!isAVAX(token), "Approve called on AVAX");

    if (amount == 0) {
      token.safeApprove(to, 0);
    } else {
      uint256 allowance = token.allowance(address(this), to);
      if (allowance < amount) {
        if (allowance > 0) {
          token.safeApprove(to, 0);
        }
        token.safeApprove(to, amount);
      }
    }
  }
}
