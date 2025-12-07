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
        address governor;
        address timelock;
        address treasury;
        address token;
        uint8 tokenType;
        uint32 createdAt;
    }

    struct CreateDAOParams {
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

    DAOConfig[] public daos;
    mapping(address => uint256[]) private daoIdsByCreator;
    mapping(address => bool) private isDAO;
    
    event DAOCreated(
        uint256 indexed daoId,
        address indexed governor,
        address indexed token,
        uint8 tokenType,
        address creator,
        uint32 timestamp
    );

    function createDAO(CreateDAOParams calldata p) external returns (address, address, address, address) {
        address timelock = _deployTimelock(p.timelockDelay);
        address token = _deployToken(p.tokenType, p.tokenName, p.tokenSymbol, p.initialSupply, p.maxSupply, p.baseURI);
        address governor = _deployGovernor(token, timelock, p.votingDelay, p.votingPeriod, p.proposalThreshold, p.quorumPercentage);
        address treasury = _deployTreasury(timelock);

        uint256 daoId = daos.length;
        daos.push(DAOConfig({
            governor: governor,
            timelock: timelock,
            treasury: treasury,
            token: token,
            tokenType: p.tokenType,
            createdAt: uint32(block.timestamp)
        }));
        
        daoIdsByCreator[msg.sender].push(daoId);
        isDAO[governor] = true;

        _configureRoles(p.tokenType, token, governor, timelock);

        emit DAOCreated(daoId, governor, token, p.tokenType, msg.sender, uint32(block.timestamp));
        return (governor, timelock, treasury, token);
    }

    function _deployTimelock(uint256 delay) internal returns (address) {
        return address(new DGPTimelockController(delay, new address[](0), new address[](0), address(this)));
    }

    function _deployToken(
        uint8 tokenType,
        string memory tokenName,
        string memory tokenSymbol,
        uint256 initialSupply,
        uint256 maxSupply,
        string memory baseURI
    ) internal returns (address) {
        if (tokenType == 0) { // ERC20
            return address(new ERC20VotingPower(tokenName, tokenSymbol, initialSupply, maxSupply, msg.sender));
        }
        return address(new ERC721VotingPower(tokenName, tokenSymbol, maxSupply, baseURI));
    }

    function _deployGovernor(
        address token,
        address timelock,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 proposalThreshold,
        uint256 quorumPercentage
    ) internal returns (address) {
        return address(new DGPGovernor(
            IVotes(token),
            DGPTimelockController(payable(timelock)),
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

    function _configureRoles(uint8 tokenType, address token, address governor, address timelock) internal {
        // Configure token roles
        if (tokenType == 0) { // ERC20
            ERC20VotingPower t = ERC20VotingPower(token);
            t.grantRole(t.MINTER_ROLE(), governor);
            t.grantRole(t.MINTER_ROLE(), timelock);
            t.revokeRole(t.MINTER_ROLE(), address(this));
            t.grantRole(t.DEFAULT_ADMIN_ROLE(), timelock);
            t.renounceRole(t.DEFAULT_ADMIN_ROLE(), address(this));
        } else { // ERC721
            ERC721VotingPower t = ERC721VotingPower(token);
            t.grantRole(t.MINTER_ROLE(), governor);
            t.grantRole(t.MINTER_ROLE(), timelock);
            t.revokeRole(t.MINTER_ROLE(), address(this));
            t.grantRole(t.DEFAULT_ADMIN_ROLE(), timelock);
            t.renounceRole(t.DEFAULT_ADMIN_ROLE(), address(this));
        }

        // Configure timelock roles
        DGPTimelockController tc = DGPTimelockController(payable(timelock));
        tc.grantRole(tc.PROPOSER_ROLE(), governor);
        tc.grantRole(tc.EXECUTOR_ROLE(), address(0));
        tc.grantRole(tc.DEFAULT_ADMIN_ROLE(), governor);
        tc.renounceRole(tc.DEFAULT_ADMIN_ROLE(), address(this));
    }

    function getDao(uint256 daoId) external view returns (DAOConfig memory) {
        if (daoId >= daos.length) revert FactoryError.DAODoesNotExist();
        return daos[daoId];
    }

    function getAllDao() external view returns (DAOConfig[] memory) {
        return daos;
    }

    function getDaosByCreator(address creator) external view returns (uint256[] memory) {
        return daoIdsByCreator[creator];
    }

    function deleteDao(uint256 daoId) external {
        if (daoId >= daos.length) revert FactoryError.DAODoesNotExist();
        daos[daoId] = daos[daos.length - 1];
        daos.pop();
    }
}
