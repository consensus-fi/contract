// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./IERC20Voteable.sol";

abstract contract ERC20Voteable is ERC20, IERC20Voteable {
    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes;
    }
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );
    bytes32 public constant DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
    );
    bytes32 public constant DELEGATION_TYPEHASH = keccak256(
        "Delegation(address delegatee,uint256 nonce,uint256 expiry)"
    );
    bytes32 public constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );
    mapping(address => address) _delegates;
    mapping(address => mapping(uint256 => Checkpoint)) public _checkpoints;
    mapping(address => uint256) public _numCheckpoints;
    mapping(address => uint256) public _nonces;

    /**
     * @notice Triggers an approval from owner to spends
     * @param owner The address to approve from
     * @param spender The address to be approved
     * @param rawAmount The number of tokens that are approved (2^256-1 means infinite)
     * @param deadline The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function permit(
        address owner,
        address spender,
        uint256 rawAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        uint256 amount;
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                _getChainId(),
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                rawAmount,
                _nonces[owner]++,
                deadline
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "ERC20Voteable: permit: invalid signature"
        );
        require(signatory == owner, "ERC20Voteable: permit: unauthorized");
        require(now <= deadline, "ERC20Voteable: permit: signature expired");

        _approve(owner, spender, amount);
        emit Approval(owner, spender, amount);
    }

    /**
     * @notice Delegate votes from `_msgSender()` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) public {
        return _delegate(_msgSender(), delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                _getChainId(),
                address(this)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)
        );
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );
        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "ERC20Voteable: delegateBySig: invalid signature"
        );
        require(
            nonce == _nonces[signatory]++,
            "ERC20Voteable: delegateBySig: invalid nonce"
        );
        require(
            now <= expiry,
            "ERC20Voteable: delegateBySig: signature expired"
        );
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint256 nCheckpoints = _numCheckpoints[account];
        return
            nCheckpoints > 0
                ? _checkpoints[account][nCheckpoints - 1].votes
                : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber)
        public
        override
        view
        returns (uint256)
    {
        require(
            blockNumber < block.number,
            "ERC20Voteable: getPriorVotes: not yet determined"
        );

        uint256 nCheckpoints = _numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (_checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return _checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (_checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = _checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return _checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint256 srcRepNum = _numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0
                    ? _checkpoints[srcRep][srcRepNum - 1].votes
                    : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint256 dstRepNum = _numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0
                    ? _checkpoints[dstRep][dstRepNum - 1].votes
                    : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint256 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        if (
            nCheckpoints > 0 &&
            _checkpoints[delegatee][nCheckpoints - 1].fromBlock == block.number
        ) {
            _checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            _checkpoints[delegatee][nCheckpoints] = Checkpoint(
                block.number,
                newVotes
            );
            _numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function _getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        _moveDelegates(_delegates[from], _delegates[to], amount);
    }
}
