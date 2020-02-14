pragma solidity ^0.4.20;

import "ds-auth/auth.sol";
import "ds-math/math.sol";

import "./simple_token.sol";

contract AExchange is DSMath, DSAuth {
    ERC20 public weth_t;
    SimpleToken public pkr_t;
    SimpleToken public usd_t;

    uint public weth_cur_price = 400 * WAD;
    uint public pkr_cur_price = 700 * WAD;

    constructor (ERC20 weth) public {
        require(address(weth) != 0x00, "need weth token");
        weth_t = weth;

        pkr_t = new SimpleToken("PKR token", "PKR", 1000000 * WAD);
        usd_t = new SimpleToken("USD stable token", "USDT", 100000000 * WAD);
    }

    function setEthPrice(uint weth_cur_price_) public auth {
        weth_cur_price = weth_cur_price_;
    }
    function setPkrPrice(uint pkr_cur_price_) public auth {
        pkr_cur_price = pkr_cur_price_;
    }


    function getPKR(uint weth_amount) public {
        require(weth_t.balanceOf(msg.sender) >= weth_amount, "hasn't enough balance");
        require(weth_t.allowance(msg.sender, address(this)) >= weth_amount, "hasn't enough approved");

        uint pkr_amount = wdiv(wmul(weth_amount, weth_cur_price), pkr_cur_price);
        require(pkr_t.balanceOf(address(this)) >= pkr_amount, "hasn't enough exchange pkr balance");

        require(weth_t.transferFrom(msg.sender, address(this), weth_amount), "can't transfer weth from client");

        pkr_t.transfer(msg.sender, pkr_amount);
    }

    function returnPKR(uint pkr_amount) public {
        require(pkr_t.balanceOf(msg.sender) >= pkr_amount, "hasn't enough balance");
        require(pkr_t.allowance(msg.sender, address(this)) >= pkr_amount, "hasn't enough approved");

        uint weth_amount = wdiv(wmul(pkr_amount, weth_cur_price), weth_cur_price);
        require(weth_t.balanceOf(address(this)) >= weth_amount, "hasn't enough exchange weth balance");

        require(pkr_t.transferFrom(msg.sender, address(this), pkr_amount), "can't transfer weth from client");

        weth_t.transfer(msg.sender, weth_amount);
    }

    function getUSDT(uint weth_amount) public {
        require(weth_t.balanceOf(msg.sender) >= weth_amount, "hasn't enough balance");
        require(weth_t.allowance(msg.sender, address(this)) >= weth_amount, "hasn't enough approved");

        uint usd_amount = wmul(weth_amount, weth_cur_price);
        require(usd_t.balanceOf(address(this)) >= usd_amount, "hasn't enough exchange usd balance");

        require(weth_t.transferFrom(msg.sender, address(this), weth_amount), "can't transfer weth from client");

        usd_t.transfer(msg.sender, usd_amount);
    }

    function returnUSDT(uint usd_amount) public {
        require(usd_t.balanceOf(msg.sender) >= usd_amount, "hasn't enough balance");
        require(usd_t.allowance(msg.sender, address(this)) >= usd_amount, "hasn't enough approved");

        uint weth_amount = wdiv(usd_amount, weth_cur_price);
        require(weth_t.balanceOf(address(this)) >= weth_amount, "hasn't enough exchange weth balance");

        require(usd_t.transferFrom(msg.sender, address(this), usd_amount), "can't transfer weth from client");

        weth_t.transfer(msg.sender, weth_amount);
    }

    //для удобства
    function getBalances() public view returns(uint eth_amount, uint weth_amount, uint pkr_amount, uint usd_amount) {
        return getBalances(msg.sender);
    }
    function getBalances(address guy) public view returns(uint eth_amount, uint weth_amount, uint pkr_amount, uint usd_amount) {
        eth_amount = guy.balance;
        weth_amount = weth_t.balanceOf(guy);
        pkr_amount = pkr_t.balanceOf(guy);
        usd_amount = usd_t.balanceOf(guy);
    }
}
