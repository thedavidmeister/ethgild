// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

contract Ounce is ERC1155, ERC20 {
    using SafeCast for int256;
    using SafeMath for uint256;

    string public constant NAME = "ounce";
    string public constant SYMBOL = "oXAU";
    string public constant VAULT_URI = "https://example.com/{id}";

    uint256 public constant FEE_NUMERATOR = 1001;
    uint256 public constant FEE_DENOMINATOR = 1000;

    event Vault(address indexed caller, uint256 indexed vaultId, uint256 indexed amount);
    event Unvault(address indexed caller, uint256 indexed vaultId, uint256 indexed amount);

    AggregatorV3Interface public constant chainlinkXAUUSD = AggregatorV3Interface(0x214eD9Da11D2fbe465a6fc601a91E62EbEc1a0D6);
    AggregatorV3Interface public constant chainlinkETHUSD = AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    constructor () ERC20(NAME, SYMBOL) ERC1155(VAULT_URI) { }

    // Returns an ETH/XAU price or reverts.
    function xauEthPrice() public view returns (uint256) {
        ( , int256 _xauUsd, , , ) = chainlinkXAUUSD.latestRoundData();
        ( , int256 _ethUsd, , , ) = chainlinkETHUSD.latestRoundData();
        return _xauUsd.toUint256().div(_ethUsd.toUint256());
    }

    function unvault(uint256 _vaultId, uint256 _amountEth) external {
        uint256 _amount = _amountEth.mul(_vaultId);
        // ERC1155 burn.
        _burn(msg.sender, _vaultId, _amount);
        // ERC20 burn.
        _burn(msg.sender, _amount.mul(FEE_NUMERATOR).div(FEE_DENOMINATOR));
        // ETH refund.
        (bool _refundSuccess, ) = msg.sender.call{value: _amountEth}("");
        require(_refundSuccess, "ETH_REFUND");
        emit Unvault(msg.sender, _vaultId, _amountEth);
    }

    receive() external payable {
        require(msg.value > 0, "ZERO_VALUE");
        uint256 _xauEthPrice = xauEthPrice();
        uint256 _amount = msg.value.mul(_xauEthPrice);
        // ERC20 mint.
        _mint(msg.sender, _amount);
        // ERC1155 mint.
        _mint(msg.sender, _xauEthPrice, _amount, "");
        emit Vault(msg.sender, _xauEthPrice, _amount);
    }
}