// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IERC20Voteable {
    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint256);
}
