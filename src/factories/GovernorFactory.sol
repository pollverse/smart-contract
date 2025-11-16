// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "../core/DGPGovernor.sol";
import "../core/DGPTimelockController.sol";
import "../core/DGPTreasury.sol";
import "../core/voting/ERC20VotingPower.sol";
import "../core/voting/ERC721VotingPower.sol";
import {FactoryError} from "../libraries/Errors.sol";

contract GovernorFactory {
    enum TokenType { ERC20, ERC721 }

    struct DAOConfig {
        string daoName;
        address governor;
        address timelock;
        address treasury;
        address token;
        TokenType tokenType;
        address creator;
    }

    // New struct to pass many params in one calldata arg
    struct CreateDAOParams {
        string daoName;
        string tokenName;
        string tokenSymbol;
        uint256 initialSupply;
        uint256 maxSupply;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThreshold;
        uint256 timelockDelay;
        uint256 quorumPercentage;
        TokenType tokenType;
        string baseURI;
    }

    DAOConfig[] public daos;
    mapping(address => address[]) private daosByCreator;
    mapping(address => bool) private isDAO;
    event DAOCreated(
        address indexed governor,
        address indexed timelock,
        address indexed treasury,
        string daoName,
        address token,
        TokenType tokenType,
        address creator,
        uint256 daoId
    );

    // Note: single calldata struct param reduces stack usage
    function createDAO(CreateDAOParams calldata p) external returns (address governor, address timelock, address treasury, address token) {
        // deploy components
        timelock = _deployTimelock(p.timelockDelay);
        token = _deployToken(p.tokenType, p.tokenName, p.tokenSymbol, p.initialSupply, p.maxSupply, p.baseURI);
        governor = _deployGovernor(token, timelock, p.votingDelay, p.votingPeriod, p.proposalThreshold, p.quorumPercentage);
        treasury = _deployTreasury(timelock);

        // configure roles and record
        _configureRoles(p.tokenType, token, governor, timelock);
        _recordDAO(p.daoName, governor, timelock, treasury, token, p.tokenType);
        _configureTimelockRoles(timelock, governor);
    }

    function _deployTimelock(uint256 delay) internal returns (address) {
        address[] memory proposers;
        address[] memory executors;
        return address(new DGPTimelockController(delay, proposers, executors, address(this)));
    }

    function _deployToken(TokenType tokenType, string memory tokenName, string memory tokenSymbol, uint256 initialSupply, uint256 maxSupply, string memory baseURI) internal returns (address) {
        if (tokenType == TokenType.ERC20) {
            return address(new ERC20VotingPower(tokenName, tokenSymbol, initialSupply, maxSupply, msg.sender));
        } else {
            return address(new ERC721VotingPower(tokenName, tokenSymbol, maxSupply, baseURI));
        }
    }

    function _deployGovernor(address token, address timelock, uint256 votingDelay, uint256 votingPeriod, uint256 proposalThreshold, uint256 quorumPercentage) internal returns (address) {
        IVotes votesToken = IVotes(token);
        DGPTimelockController timelockController = DGPTimelockController(payable(timelock));
        return address(new DGPGovernor(
            votesToken,
            timelockController,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumPercentage,
            msg.sender
        ));
    }

    function _deployTreasury(address timelock) internal returns (address) {
        return address(new DGPTreasury(timelock, timelock));
    }

    function _configureRoles(TokenType tokenType, address token, address governor, address timelock) internal {
        if (tokenType == TokenType.ERC20) {
            ERC20VotingPower erc20 = ERC20VotingPower(token);

            // Governor can mint directly (for member top-ups)
            erc20.grantRole(erc20.MINTER_ROLE(), address(governor));

            // Timelock can mint via approved proposals
            erc20.grantRole(erc20.MINTER_ROLE(), timelock);

            // Revoke factory's own minter role so it cannot mint after setup
            erc20.revokeRole(erc20.MINTER_ROLE(), address(this));

            // Transfer admin control of roles to Timelock
            erc20.grantRole(erc20.DEFAULT_ADMIN_ROLE(), timelock);

            // Factory renounces admin to make DAO self-governing
            erc20.renounceRole(erc20.DEFAULT_ADMIN_ROLE(), address(this));

        } else {
            ERC721VotingPower erc721 = ERC721VotingPower(token);

            erc721.grantRole(erc721.MINTER_ROLE(), address(governor));
            erc721.grantRole(erc721.MINTER_ROLE(), timelock);

            // Revoke factory's own minter role so it cannot mint after setup
            erc721.revokeRole(erc721.MINTER_ROLE(), address(this));

            erc721.grantRole(erc721.DEFAULT_ADMIN_ROLE(), timelock);
            erc721.renounceRole(erc721.DEFAULT_ADMIN_ROLE(), address(this));
        }
    }

    function _configureTimelockRoles(address timelock, address governor) internal {
        DGPTimelockController timelockContract = DGPTimelockController(payable(timelock));

        bytes32 proposerRole = timelockContract.PROPOSER_ROLE();
        bytes32 executorRole = timelockContract.EXECUTOR_ROLE();
        bytes32 adminRole = timelockContract.DEFAULT_ADMIN_ROLE();

        timelockContract.grantRole(proposerRole, governor);
        // allow anyone to execute queued operations (optional; change to governor if you want restricted execution)
        timelockContract.grantRole(executorRole, address(0));

        // Make governor the admin of timelock (so governance can change roles via proposals)
        timelockContract.grantRole(adminRole, governor);
        // factory renounces admin role on timelock
        timelockContract.renounceRole(adminRole, address(this));
    }

    function _recordDAO(string memory daoName, address governor, address timelock, address treasury, address token, TokenType tokenType) internal {
        uint256 daoId = daos.length;
        daos.push(DAOConfig({
            daoName: daoName,
            governor: governor,
            timelock: timelock,
            treasury: treasury,
            token: token,
            tokenType: tokenType,
            creator: msg.sender
        }));
        daosByCreator[msg.sender].push(governor);
        isDAO[governor] = true;
        emit DAOCreated(governor, timelock, treasury, daoName, token, tokenType, msg.sender, daoId);
    }

    // ------------------ Frontend helper views ------------------

    function getDao(uint256 daoId) external view returns (DAOConfig memory) {
        if (daoId >= daos.length) revert FactoryError.DAODoesNotExist();
        return daos[daoId];
    }

    function getAllDao() external view returns (DAOConfig[] memory) {
        return daos;
    }

    function deleteDao(uint256 daoId) external {
        if (daoId >= daos.length) revert FactoryError.DAODoesNotExist();
        // optional: update isDAO and daosByCreator here to keep consistency
        daos[daoId] = daos[daos.length - 1];
        daos.pop();
    }
}
