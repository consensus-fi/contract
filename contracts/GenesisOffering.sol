// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/SafeCast.sol";
import "./CF.sol";

contract GenesisOffering {
    using SafeMath for uint256;
    CF public token;
    uint256 public totalEther;
    uint256 public totalToken;
    uint256 public start;
    uint256 public end;
    uint256 public constant maxStockPerAddress = 100 ether;
    mapping(address => uint256) public holders;

    constructor(
        address _tokenAddress,
        uint256 _totalToken,
        uint256 _start,
        uint256 _end
    ) public {
        assert(
            _tokenAddress != address(0) &&
                _totalToken > 0 &&
                _start > 0 &&
                _end > start
        );
        token = CF(_tokenAddress);
        totalToken = _totalToken;
        start = _start;
        end = _end;
    }

    modifier ensureStarted() {
        assert(block.timestamp >= start && block.timestamp < end);
        _;
    }

    modifier ensureEnded() {
        assert(block.timestamp > end);
        _;
    }

    function purchase() public payable ensureStarted {
        assert(holders[msg.sender].add(msg.value) <= maxStockPerAddress);
        totalEther = totalEther.add(msg.value);
        holders[msg.sender] = holders[msg.sender].add(msg.value);
    }

    function claim() public ensureEnded {
        uint256 bidAmount = holders[msg.sender];
        assert(bidAmount > 0);
        holders[msg.sender] = 0;
        token.mint(msg.sender, totalToken.mul(bidAmount).div(totalEther));
    }

    function devClaim() public ensureEnded {
        address payable devTeam = address(uint160(token.owner()));
        devTeam.transfer(address(this).balance);
    }
}
