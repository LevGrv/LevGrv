pragma solidity ^0.4.20;

import "ds-token/base.sol";

contract SimpleToken is DSTokenBase {
    string public name;
    string public symbol;
    uint8  public decimals = 18;

    constructor (string name_, string symbol_, uint supply_) public DSTokenBase(supply_)  {
        name = name_;
        symbol = symbol_;
        //_supply = 1000000000000000000000000;
    }
}
