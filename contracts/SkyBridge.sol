//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0 <=0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";


import "./interfaces/IERC20.sol";
import "./interfaces/IBurnableToken.sol";
import "./interfaces/IParams.sol";
import "./libraries/SafeERC20.sol";
import "./LPToken.sol";

contract SkyBridge is Ownable {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;
  
  IBurnableToken public lpToken;
  IParams public ip;

  mapping(address => bool) public whitelist;
  address public immutable BTCT_ADDR;
  address public immutable sbBTCPool;
  uint256 private immutable convertScale;
  uint256 private immutable lpDivisor;

  mapping(address => uint256) private floatAmountOf;
  mapping(bytes32 => bool) private used; //used TX

  // node lists
  mapping(address => uint8) nodes;
  address[] nodeAddrs;
  uint8 public activeNodeCount;
  uint8 public churnedInCount;
  uint8 public tssThreshold;

  constructor (
    address _lpToken,
    address _btct,
    address _sbBTCPool,
    uint256 _existingBTCFloat
  ) {
    sbBTCPool = _sbBTCPool;
    lpToken = IBurnableToken(_lpToken);
    lpDivisor = 10**IERC20(_lpToken).decimals();
    BTCT_ADDR = _btct;
    convertScale = 10**(IERC20(_btct).decimals() - 8);
    whitelist[_btct] = true;
    whitelist[_lpToken] = true;
    whitelist[address(0)] = true;
    floatAmountOf[address(0)] = _existingBTCFloat;
  }

  /**
    * Transfer part
  */
  /// @dev singleTransferERC20 sends tokens from contract.
  /// @param _destToken The address of target token.
  /// @param _to The address of recipient.
  /// @param _amount The amount of tokens.
  /// @param _rewardsAmount The fees that should be paid.
  /// @param _redeemedFloatTxIds The txids which is for recording.
  function singleTransferERC20(
    address _destToken,
    address _to,
    uint256 _amount,
    uint256 _rewardsAmount,
    bytes32[] memory _redeemedFloatTxIds
  ) external onlyOwner returns (bool) {
    require(whitelist[_destToken], "14"); //_destToken is not whitelisted
    require(
        _destToken != address(0),
        "15" //_destToken should not be address(0)
    );
    address _feesToken = address(0);
    _feesToken = (_destToken == address(lpToken)) ? address(lpToken) : BTCT_ADDR;
    _rewardsCollection(_feesToken, _rewardsAmount);
    _addUsedTxs(_redeemedFloatTxIds);
    _safeTransfer(_destToken, _to, _amount);
    return true;
  }

  /// @dev multiTransferERC20TightlyPacked sends tokens from contract.
  /// @param _destToken The address of target token.
  /// @param _addressesAndAmounts The address of recipient and amount.
  /// @param _rewardsAmount The fees that should be paid.
  /// @param _redeemedFloatTxIds The txids which is for recording.
  function multiTransferERC20TightlyPacked(
    address _destToken,
    bytes32[] memory _addressesAndAmounts,
    uint256 _rewardsAmount,
    bytes32[] memory _redeemedFloatTxIds
  ) external onlyOwner returns (bool) {
    require(whitelist[_destToken], "_destToken is not whitelisted");
    require(
        _destToken != address(0),
        "_destToken should not be address(0)"
    );
    address _feesToken = (_destToken == address(lpToken)) ? address(lpToken) : BTCT_ADDR;
    _rewardsCollection(_feesToken, _rewardsAmount);
    _addUsedTxs(_redeemedFloatTxIds);
    for (uint256 i = 0; i < _addressesAndAmounts.length; i++) {
        _safeTransfer(
            _destToken,
            address(uint160(uint256(_addressesAndAmounts[i]))),
            uint256(uint96(bytes12(_addressesAndAmounts[i])))
        );
    }
    return true;
  }

  /// @dev _safeTransfer executes tranfer erc20 tokens
  /// @param _token The address of target token
  /// @param _to The address of receiver.
  /// @param _amount The amount of transfer.
  function _safeTransfer(
    address _token,
    address _to,
    uint256 _amount
  ) internal {
    if (_token == BTCT_ADDR) {
        _amount = _amount.mul(convertScale);
    }
    IERC20(_token).safeTransfer(_to, _amount);
  }

  /// @dev _rewardsCollection collects tx rewards.
  /// @param _feesToken The token address for collection fees.
  /// @param _rewardsAmount The amount of rewards.
  function _rewardsCollection(address _feesToken, uint256 _rewardsAmount)
    internal
  {
    if (_rewardsAmount == 0) return;
    // Get current LP token price.
    uint256 nowPrice = getCurrentPriceLP();
    // Add all fees into pool
    floatAmountOf[_feesToken] = floatAmountOf[_feesToken].add(
        _rewardsAmount
    );
    uint256 amountForNodes = _rewardsAmount.mul(ip.nodeRewardsRatio()).div(
        100
    );
    // Alloc LP tokens for nodes as fees
    uint256 amountLPTokensForNode = amountForNodes.mul(lpDivisor).div(
        nowPrice
    );
    // Mints LP tokens for Nodes
    lpToken.mint(sbBTCPool, amountLPTokensForNode);
  }

  /// @dev getCurrentPriceLP returns the current exchange rate of LP token.
  function getCurrentPriceLP()
    public
    view
    returns (uint256 nowPrice)
  {
    (uint256 reserveA, uint256 reserveB) = getFloatReserve(
        address(0),
        BTCT_ADDR
    );
    uint256 totalLPs = lpToken.totalSupply();
    // decimals of totalReserved == 8, lpDivisor == 8, decimals of rate == 8
    nowPrice = totalLPs == 0
        ? lpDivisor
        : (reserveA.add(reserveB)).mul(lpDivisor).div(totalLPs);
  }

  /// @dev getFloatReserve returns float reserves
  /// @param _tokenA The address of target tokenA.
  /// @param _tokenB The address of target tokenB.
  function getFloatReserve(address _tokenA, address _tokenB)
    public
    view
    returns (uint256 reserveA, uint256 reserveB)
  {
    (reserveA, reserveB) = (floatAmountOf[_tokenA], floatAmountOf[_tokenB]);
  }

  /// @dev _addUsedTxs updates txid list which is spent. (multiple hashes)
  /// @param _txids The array of txid.
  function _addUsedTxs(bytes32[] memory _txids) internal {
    for (uint256 i = 0; i < _txids.length; i++) {
        used[_txids[i]] = true;
    }
  }

  /// @dev churn transfers contract ownership and set variables of the next TSS validator set.
  /// @param _newOwner The address of new Owner.
  /// @param _nodes The reward addresses.
  /// @param _isRemoved The flags to remove node.
  /// @param _churnedInCount The number of next party size of TSS group.
  /// @param _tssThreshold The number of next threshold.
  function churn(
    address _newOwner,
    address[] memory _nodes,
    bool[] memory _isRemoved,
    uint8 _churnedInCount,
    uint8 _tssThreshold
  ) external onlyOwner returns (bool) {
    require(
        _tssThreshold >= tssThreshold && _tssThreshold <= 2**8 - 1,
        "01" //"_tssThreshold should be >= tssThreshold"
    );
    require(
        _churnedInCount >= _tssThreshold + uint8(1),
        "02" //"n should be >= t+1"
    );
    require(
        _nodes.length == _isRemoved.length,
        "05" //"_nodes and _isRemoved length is not match"
    );

    transferOwnership(_newOwner);
    // Update active node list
    for (uint256 i = 0; i < _nodes.length; i++) {
        if (!_isRemoved[i]) {
            if (nodes[_nodes[i]] == uint8(0)) {
                nodeAddrs.push(_nodes[i]);
            }
            if (nodes[_nodes[i]] != uint8(1)) {
                activeNodeCount++;
            }
            nodes[_nodes[i]] = uint8(1);
        } else {
            activeNodeCount--;
            nodes[_nodes[i]] = uint8(2);
        }
    }
    require(activeNodeCount <= 100, "Stored node size should be <= 100");
    churnedInCount = _churnedInCount;
    tssThreshold = _tssThreshold;
    return true;
  }

  /// @dev getActiveNodes returns active nodes list
  function getActiveNodes() public view returns (address[] memory) {
    uint256 count = 0;
    address[] memory _nodes = new address[](activeNodeCount);
    for (uint256 i = 0; i < nodeAddrs.length; i++) {
        if (nodes[nodeAddrs[i]] == uint8(1)) {
            _nodes[count] = nodeAddrs[i];
            count++;
        }
    }
    return _nodes;
  }
}