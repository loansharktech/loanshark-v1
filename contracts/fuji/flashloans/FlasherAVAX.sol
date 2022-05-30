// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../abstracts/claimable/Claimable.sol";
import "../../interfaces/IFujiAdmin.sol";
import "../../interfaces/IVault.sol";
import "../../interfaces/IFlasher.sol";
import "../../interfaces/IFliquidator.sol";
import "../../interfaces/IFujiMappings.sol";
import "../../interfaces/IWETH.sol";
import "../../libraries/FlashLoans.sol";
import "../../libraries/Errors.sol";
import "../../interfaces/aave/IFlashLoanReceiver.sol";
import "../../interfaces/aave/IAaveLendingPool.sol";
import "../../interfaces/cream/ICTokenFlashloan.sol";
import "../../interfaces/cream/ICFlashloanReceiver.sol";
import "../libraries/LibUniversalERC20FTM.sol";

/**
 * @dev Contract that handles Fuji protocol flash loan logic and
 * the specific logic of all active flash loan providers used by Fuji protocol.
 */


contract FlasherAVAX is IFlasher, Claimable, IFlashLoanReceiver, ICFlashloanReceiver {
  using LibUniversalERC20FTM for IERC20;

  IFujiAdmin private _fujiAdmin;

  address private constant _AVAX = 0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF;
  address private constant _WAVAX = 0xd00ae08403B9bbb9124bB305C09058E32C39A48c;
  address private constant _cAVAX = 0x219990FA1f91751539c65aE3f50040C6701cF219;

  address private immutable _aavxLendingPool = 0x76cc67FF2CC77821A70ED14321111Ce381C2594D;
  IFujiMappings private immutable _crMappings = IFujiMappings(0x1eEdE44b91750933C96d2125b6757C4F89e63E20);

  // need to be payable because of the conversion ETH <> WETH
  receive() external payable {}

  /**
  * @dev Throws if caller is not 'owner'.
  */
  modifier isAuthorized() {
    require(
      msg.sender == _fujiAdmin.getController() ||
        msg.sender == _fujiAdmin.getFliquidator() ||
        msg.sender == owner(),
      Errors.VL_NOT_AUTHORIZED
    );
    _;
  }

  /**
   * @dev Sets the fujiAdmin Address
   * @param _newFujiAdmin: FujiAdmin Contract Address
   * Emits a {FujiAdminChanged} event.
   */
  function setFujiAdmin(address _newFujiAdmin) public onlyOwner {
    _fujiAdmin = IFujiAdmin(_newFujiAdmin);
    emit FujiAdminChanged(_newFujiAdmin);
  }

  /**
   * @dev Routing Function for Flashloan Provider
   * @param info: struct information for flashLoan
   * @param _flashnum: integer identifier of flashloan provider
   */
  function initiateFlashloan(FlashLoan.Info calldata info, uint8 _flashnum) external isAuthorized override {
    if (_flashnum == 0) {
      _initiateGeistFlashLoan(info);
    } else if (_flashnum == 2) {
      _initiateCreamFlashLoan(info);
    } else {
      revert(Errors.VL_INVALID_FLASH_NUMBER);
    }
  }

  /**
   * @dev Initiates an Geist flashloan.
   * @param info: data to be passed between functions executing flashloan logic
   */
  function _initiateGeistFlashLoan(FlashLoan.Info calldata info) internal {
    //Initialize Instance of Geist Lending Pool
    IAaveLendingPool geistLp = IAaveLendingPool(_aavxLendingPool);

    //Passing arguments to construct Geist flashloan -limited to 1 asset type for now.
    address receiverAddress = address(this);
    address[] memory assets = new address[](1);
    assets[0] = address(info.asset == _AVAX ? _WAVAX : info.asset);
    uint256[] memory amounts = new uint256[](1);
    amounts[0] = info.amount;

    // 0 = no debt, 1 = stable, 2 = variable
    uint256[] memory modes = new uint256[](1);
    //modes[0] = 0;

    //address onBehalfOf = address(this);
    //bytes memory params = abi.encode(info);
    //uint16 referralCode = 0;

    //Geist Flashloan initiated.
    geistLp.flashLoan(receiverAddress, assets, amounts, modes, address(this), abi.encode(info), 0);
  }

  /**
   * @dev Executes Geist Flashloan, this operation is required
   * and called by Geistflashloan when sending loaned amount
   */
  function executeOperation(
    address[] calldata assets,
    uint256[] calldata amounts,
    uint256[] calldata premiums,
    address initiator,
    bytes calldata params
  ) external override returns (bool) {
    require(msg.sender == _aavxLendingPool && initiator == address(this), Errors.VL_NOT_AUTHORIZED);

    FlashLoan.Info memory info = abi.decode(params, (FlashLoan.Info));

    uint256 _value;
    if (info.asset == _AVAX) {
      // Convert WAVAX to AVAX and assign amount to be set as msg.value
      _convertWavaxToAvax(amounts[0]);
      _value = info.amount;
    } else {
      // Transfer to Vault the flashloan Amount
      // _value is 0
      IERC20(assets[0]).univTransfer(payable(info.vault), amounts[0]);
    }

    _executeAction(info, amounts[0], premiums[0], _value);

    //Approve geistLP to spend to repay flashloan
    _approveBeforeRepay(info.asset == _AVAX, assets[0], amounts[0] + premiums[0], _aavxLendingPool);

    return true;
  }

  // ===================== CreamFinance FlashLoan ===================================

  /**
   * @dev Initiates an CreamFinance flashloan.
   * @param info: data to be passed between functions executing flashloan logic
   */
  function _initiateCreamFlashLoan(FlashLoan.Info calldata info) internal {
    address crToken = info.asset == _AVAX
      ? _cAVAX
      : _crMappings.addressMapping(info.asset);

    // Prepara data for flashloan execution
    bytes memory params = abi.encode(info);

    // Initialize Instance of Cream crLendingContract
    ICTokenFlashloan(crToken).flashLoan(address(this), address(this), info.amount, params);
  }
  /**
   * @dev Executes CreamFinance Flashloan, this operation is required
   * and called by CreamFinanceflashloan when sending loaned amount
   */
  function onFlashLoan(
    address sender,
    address underlying,
    uint256 amount,
    uint256 fee,
    bytes calldata params
  ) external override returns (bytes32) {
    // Check Msg. Sender is crToken Lending Contract
    // from IronBank because ETH on Cream cannot perform a flashloan
    address crToken = underlying == _WAVAX
      ? _cAVAX
      : _crMappings.addressMapping(underlying);
    require(msg.sender == crToken && address(this) == sender, Errors.VL_NOT_AUTHORIZED);
    require(IERC20(underlying).balanceOf(address(this)) >= amount, Errors.VL_FLASHLOAN_FAILED);
    FlashLoan.Info memory info = abi.decode(params, (FlashLoan.Info));
    uint256 _value;
    if (info.asset == _AVAX) {
      // Convert WFTM to FTM and assign amount to be set as msg.value
      _convertWavaxToAvax(amount);
      _value = amount;
    } else {
      // Transfer to Vault the flashloan Amount
      // _value is 0
      IERC20(underlying).univTransfer(payable(info.vault), amount);
    }
    // Do task according to CallType
    _executeAction(info, amount, fee, _value);

    if (info.asset == _AVAX) _convertAvaxToWavax(amount + fee);
    // Transfer flashloan + fee back to crToken Lending Contract
    IERC20(underlying).univApprove(payable(crToken), amount + fee);

    return keccak256("ERC3156FlashBorrowerInterface.onFlashLoan");
  }

  // ========================================================
  //
  // flash loans come here....
  //
  // ========================================================

  function _executeAction(
    FlashLoan.Info memory _info,
    uint256 _amount,
    uint256 _fee,
    uint256 _value
  ) internal {
    if (_info.callType == FlashLoan.CallType.Switch) {
      IVault(_info.vault).executeSwitch{ value: _value }(_info.newProvider, _amount, _fee);
    } else if (_info.callType == FlashLoan.CallType.Close) {
      IFliquidator(_info.fliquidator).executeFlashClose{ value: _value }(
        _info.userAddrs[0],
        _info.vault,
        _amount,
        _fee
      );
    } else {
      IFliquidator(_info.fliquidator).executeFlashBatchLiquidation{ value: _value }(
        _info.userAddrs,
        _info.userBalances,
        _info.userliquidator,
        _info.vault,
        _amount,
        _fee
      );
    }
  }

  function _approveBeforeRepay(
    bool _isAVAX,
    address _asset,
    uint256 _amount,
    address _spender
  ) internal {
    if (_isAVAX) {
      _convertAvaxToWavax(_amount);
      IERC20(_WAVAX).univApprove(payable(_spender), _amount);
    } else {
      IERC20(_asset).univApprove(payable(_spender), _amount);
    }
  }

  function _convertAvaxToWavax(uint256 _amount) internal {
    IWETH(_WAVAX).deposit{ value: _amount }();
  }

  function _convertWavaxToAvax(uint256 _amount) internal {
    IWETH token = IWETH(_WAVAX);
    token.withdraw(_amount);
  }
}
