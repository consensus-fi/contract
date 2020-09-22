// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Capped.sol";
import "./ERC20Voteable.sol";

contract CF is ERC20, ERC20Voteable, ERC20Capped, Ownable {
    event AuthorizeMinter(address minter, address operator);
    event RevokeMinter(address minter, address operator);

    address[] public minters;
    mapping(address => bool) public isMinter;

    constructor()
        public
        ERC20("Consensus Finance", "CF")
        ERC20Capped(1000_000e18)
    {}

    function mint(address to, uint256 amount) public {
        require(isMinter[_msgSender()], "CF: caller is not an operator for CF");
        _mint(to, amount);
    }

    function authorizeMinter(address minter) public onlyOwner {
        for (uint256 i = 0; i < minters.length; i++) {
            if (minters[i] == minter) revert("CF: minter exists");
        }
        minters.push(minter);
        isMinter[minter] = true;
        emit AuthorizeMinter(minter, _msgSender());
    }

    function revokeMinter(address minter) public onlyOwner {
        bool has;
        uint256 minterIndex;
        for (uint256 i = 0; i < minters.length; i++) {
            if (minters[i] == minter) {
                has = true;
                minterIndex = i;
                break;
            }
        }
        require(has, "CF: minter not found");
        address lastMinter = minters[minters.length - 1];
        if (lastMinter != minter) minters[minterIndex] = lastMinter;
        minters.pop();
        delete isMinter[minter];
        emit RevokeMinter(minter, _msgSender());
    }

    function mintersLength() public view returns (uint256) {
        return minters.length;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Voteable, ERC20Capped) {
        super._beforeTokenTransfer(from, to, amount);
    }
}
