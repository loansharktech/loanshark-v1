// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import "../interfaces/IFujiAdmin.sol";
import "../interfaces/ISwapper.sol";

/**
 * @dev Contract to support Harvesting function in {FujiVault}
 */

contract SwapperFTM is ISwapper {
  address public constant AVAX = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
  address public constant WAVAX = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
  address public constant HURRICANE_ROUTER_ADDR = 0x08a978a0399465621e667C49CD54CC874DC064Eb;

  /**
   * @dev Returns data structure to perform a swap transaction.
   * Function is called by FujiVault to harvest farmed tokens at baselayer protocols
   * @param assetFrom: asset type to be swapped.
   * @param assetTo: desired asset after swap transaction.
   * @param amount: amount of assetFrom to be swapped.
   * Requirements:
   * - Should return transaction data to swap all farmed token to vault's collateral type.
   */
  function getSwapTransaction(
    address assetFrom,
    address assetTo,
    uint256 amount
  ) external view override returns (Transaction memory transaction) {
    require(assetFrom != assetTo, "invalid request");

    if (assetFrom == AVAX && assetTo == WAVAX) {
      transaction.to = WAVAX;
      transaction.value = amount;
      transaction.data = abi.encodeWithSelector(IWETH.deposit.selector);
    } else if (assetFrom == WAVAX && assetTo == AVAX) {
      transaction.to = WAVAX;
      transaction.data = abi.encodeWithSelector(IWETH.withdraw.selector, amount);
    } else if (assetFrom == AVAX) {
      transaction.to = HURRICANE_ROUTER_ADDR;
      address[] memory path = new address[](2);
      path[0] = WAVAX;
      path[1] = assetTo;
      transaction.value = amount;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactETHForTokens.selector,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    } else if (assetTo == AVAX) {
      transaction.to = HURRICANE_ROUTER_ADDR;
      address[] memory path = new address[](2);
      path[0] = assetFrom;
      path[1] = WAVAX;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactTokensForETH.selector,
        amount,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    } else if (assetFrom == WAVAX || assetTo == WAVAX) {
      transaction.to = HURRICANE_ROUTER_ADDR;
      address[] memory path = new address[](2);
      path[0] = assetFrom;
      path[1] = assetTo;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactTokensForTokens.selector,
        amount,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    } else {
      transaction.to = HURRICANE_ROUTER_ADDR;
      address[] memory path = new address[](3);
      path[0] = assetFrom;
      path[1] = WAVAX;
      path[2] = assetTo;
      transaction.data = abi.encodeWithSelector(
        IUniswapV2Router01.swapExactTokensForTokens.selector,
        amount,
        0,
        path,
        msg.sender,
        type(uint256).max
      );
    }
  }
}
