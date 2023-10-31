// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "./PriceOracle.sol";
import "./EIP20Interface.sol";

interface IAggregatorV3 {
    function decimals() external view returns (uint8);

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface ICToken {
    function underlying() external view returns (address);
}

interface IFactory {
    function getCErc20(address) external view returns (address);
}

interface IUniswapV2Pair {
    function token0() external view returns (address);
    function token1() external view returns (address);
}

contract PriceOracleV2 is PriceOracle {
    mapping(address => IAggregatorV3) public priceFeeds;
    address public admin;
    uint256 feedDecimals = 8;
    IFactory factory;

    constructor(
        address[] memory assets_,
        IAggregatorV3[] memory feeds_
    ) {
        for (uint256 i = 0; i < assets_.length; i++) {
            priceFeeds[assets_[i]] = feeds_[i];
        }
        admin = msg.sender;
    }

    function setFactory(address _factory) external {
        require(msg.sender == admin, "only admin may set the factory");
        factory = IFactory(_factory);
    }

    function setPrice(   
        address[] memory assets_,
        IAggregatorV3[] memory feeds_) public {
            require(msg.sender == admin, "only admin may set the feeds");
            for (uint256 i = 0; i < assets_.length; i++) {
                priceFeeds[assets_[i]] = feeds_[i];
            }
    }

    // price in 18 decimals
    function getPrice(address token) public view returns (uint256) {
        (uint256 price, ) = _getLatestPrice(token);

        return price * 10**(18 - feedDecimals);
    }

    // price is extended for comptroller usage based on decimals of exchangeRate
    function getUnderlyingPrice(CToken cToken)
        external
        view
        override
        returns (uint256)
    {
        address token = ICToken(address(cToken)).underlying();
        uint256 price;
        if(factory.getCErc20(token) != address(0)) {
            uint256 _total = EIP20Interface(token).totalSupply();
            address token0 = IUniswapV2Pair(token).token0();
            address token1 = IUniswapV2Pair(token).token1();
            uint256 balance0 = EIP20Interface(token0).balanceOf(token);
            uint256 balance1 = EIP20Interface(token1).balanceOf(token);
            uint256 d0;
            uint256 d1;
            if(address(priceFeeds[token0]) != address(0)) {
                (uint256 price0, ) = _getLatestPrice(token0);
                d0 = (price0 * (10**(36 - feedDecimals))) / (10 ** EIP20Interface(token0).decimals()) * balance0;
            }
            if(address(priceFeeds[token1]) != address(0)) {
                (uint256 price1, ) = _getLatestPrice(token1);
                d1= (price1 * (10**(36 - feedDecimals))) / (10 ** EIP20Interface(token1).decimals()) * balance1;
            }
            if(d0!= 0 && d1 != 0) {
                uint256 _minVolume = d0 < d1? d0: d1;
                price = (_minVolume * 2) / _total;
            }
            return price;
        } else {
            if(address(priceFeeds[token]) != address(0)) {
                (price, ) = _getLatestPrice(token);
                return (price * (10**(36 - feedDecimals))) / (10 ** EIP20Interface(token).decimals());
            } else {
                return 0;
            }
        }
    }

    function _getLatestPrice(address token)
        internal
        view
        returns (uint256, uint256)
    {
        require(address(priceFeeds[token]) != address(0), "missing priceFeed");

        (
            ,
            //uint80 roundID
            int256 price, //uint256 startedAt
            ,
            uint256 timeStamp, //uint80 answeredInRound

        ) = priceFeeds[token].latestRoundData();

        require(price > 0, "price cannot be zero");
        uint256 uPrice = uint256(price);

        return (uPrice, timeStamp);
    }
}