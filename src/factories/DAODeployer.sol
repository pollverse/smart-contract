// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "../core/DGPGovernor.sol";
import "../core/DGPTimelockController.sol";
import "../core/DGPTreasury.sol";
import "../core/voting/ERC20VotingPower.sol";
import "../core/voting/ERC721VotingPower.sol";
import "./GovernorRegistry.sol";

contract DAODeployer {
    enum TokenType { ERC20, ERC721 }

    struct CreateDAOParams {
        string metadataURI;
        string tokenName;
        string tokenSymbol;
        uint256 initialSupply;
        uint256 maxSupply;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThreshold;
        uint256 timelockDelay;
        uint256 quorumPercentage;
        uint8 tokenType;
        string baseURI;
    }

    GovernorRegistry public immutable registry;

    constructor(address registry_) {
        registry = GovernorRegistry(registry_);
    }

    function createDAO(CreateDAOParams calldata p) external returns (uint256 daoId) {
        // 1. Deploy timelock
        address timelock = address(
            new DGPTimelockController(
                p.timelockDelay,
                new address[](0),
                new address[](0),
                address(this)
            )
        );

        // 2. Deploy voting token
        address token = _deployToken(
            p.tokenType,
            p.tokenName,
            p.tokenSymbol,
            p.initialSupply,
            p.maxSupply,
            p.baseURI
        );

        // 3. Deploy governor
        address governor = address(
            new DGPGovernor(
                IVotes(token),
                DGPTimelockController(payable(timelock)),
                p.votingDelay,
                p.votingPeriod,
                p.proposalThreshold,
                p.quorumPercentage,
                address(registry),
                msg.sender,
                daoId   
            )
        );

        // 4. Treasury
        address treasury = address(new DGPTreasury(timelock, governor));

        // 5. Register DAO
        daoId = registry.registerDAO(
            GovernorRegistry.DAOConfig({
                governor: governor,
                timelock: timelock,
                treasury: treasury,
                token: token,
                creator: msg.sender,
                tokenType: p.tokenType,
                createdAt: uint32(block.timestamp),
                isHidden: false,
                isDeleted: false,
                metadataURI: p.metadataURI
            })
        );

        // 6. Configure roles
        _configureRoles(p.tokenType, token, governor, timelock);
    }

    /* ---------------- Internals ---------------- */

    function _deployToken(
        uint8 tType,
        string memory n,
        string memory s,
        uint256 init,
        uint256 max,
        string memory bURI
    ) internal returns (address) {
        if (tType == 0) {
            return address(new ERC20VotingPower(n, s, init, max, msg.sender));
        }
        return address(new ERC721VotingPower(n, s, max, bURI));
    }

    function _configureRoles(
        uint8 tokenType,
        address token,
        address governor,
        address timelock
    ) internal {
        DGPTimelockController tc = DGPTimelockController(payable(timelock));

        tc.grantRole(tc.PROPOSER_ROLE(), governor);
        tc.grantRole(tc.CANCELLER_ROLE(), governor);
        tc.grantRole(tc.EXECUTOR_ROLE(), address(0));
        tc.grantRole(tc.DEFAULT_ADMIN_ROLE(), timelock);
        tc.renounceRole(tc.DEFAULT_ADMIN_ROLE(), address(this));

        if (tokenType == 0) {
            ERC20VotingPower t = ERC20VotingPower(token);
            t.grantRole(t.MINTER_ROLE(), governor);
            t.grantRole(t.DEFAULT_ADMIN_ROLE(), timelock);
            t.renounceRole(t.DEFAULT_ADMIN_ROLE(), address(this));
            t.renounceRole(t.MINTER_ROLE(), address(this));
        } else {
            ERC721VotingPower t = ERC721VotingPower(token);
            t.grantRole(t.MINTER_ROLE(), governor);
            t.grantRole(t.DEFAULT_ADMIN_ROLE(), timelock);
            t.renounceRole(t.DEFAULT_ADMIN_ROLE(), address(this));
            t.renounceRole(t.MINTER_ROLE(), address(this));
        }
    }
}
