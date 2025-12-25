// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../core/DGPGovernor.sol";
import "../core/DGPTimelockController.sol";
import "../core/DGPTreasury.sol";
import "../core/voting/ERC20VotingPower.sol";
import "../core/voting/ERC721VotingPower.sol";
import {FactoryError} from "../libraries/Errors.sol";

contract GovernorFactory is Ownable {
    enum TokenType { ERC20, ERC721 }

    struct DAOConfig {
        address governor;
        address timelock;
        address treasury;
        address token;
        address creator;
        uint8 tokenType;
        uint32 createdAt;
        bool isHidden;   // Removed from UI, but functional
        bool isDeleted;  // Functionality locked (Killed)
        string daoName;
        string daoDescription;
        string daoLogoURI;
    }

    struct CreateDAOParams {
        string daoName;
        string daoDescription;
        string daoLogoURI;
        string tokenName;
        string tokenSymbol;
        uint256 initialSupply;
        uint256 maxSupply;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThreshold;
        uint256 timelockDelay;
        uint256 quorumPercentage;
        uint8 tokenType; // 0 for ERC20, 1 for ERC721
        string baseURI;  // For NFTs
    }

    DAOConfig[] public daos;
    mapping(address => uint256[]) private daoIdsByCreator;
    
    event DAOCreated(uint256 indexed daoId, address indexed governor, string name, address creator);
    event DAOHidden(uint256 indexed daoId, bool status);
    event DAODeleted(uint256 indexed daoId);

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Creates a full DAO suite and configures roles.
     */
    function createDAO(CreateDAOParams calldata p) external returns (uint256 daoId) {
        daoId = daos.length;

        // 1. Deploy Core Components
        address timelock = address(new DGPTimelockController(p.timelockDelay, new address[](0), new address[](0), address(this)));
        address token = _deployToken(p.tokenType, p.tokenName, p.tokenSymbol, p.initialSupply, p.maxSupply, p.baseURI);
        
        // Pass factory address and daoId to Governor for "isDeleted" checks
        address governor = address(new DGPGovernor(
            IVotes(token),
            DGPTimelockController(payable(timelock)),
            p.votingDelay,
            p.votingPeriod,
            p.proposalThreshold,
            p.quorumPercentage,
            msg.sender, // Admin
            address(this),
            daoId
        ));

        address treasury = address(new DGPTreasury(timelock, governor));

        // 2. Register DAO
        daos.push(DAOConfig({
            governor: governor,
            timelock: timelock,
            treasury: treasury,
            token: token,
            creator: msg.sender,
            tokenType: p.tokenType,
            createdAt: uint32(block.timestamp),
            isHidden: false,
            isDeleted: false,
            daoName: p.daoName,
            daoDescription: p.daoDescription,
            daoLogoURI: p.daoLogoURI
        }));

        daoIdsByCreator[msg.sender].push(daoId);

        // 3. Setup Permissions
        _configureRoles(p.tokenType, token, governor, timelock);

        emit DAOCreated(daoId, governor, p.daoName, msg.sender);
    }

    /**
     * @dev Hiding keeps the DAO alive but signals the frontend to stop displaying it.
     */
    function setHidden(uint256 daoId, bool status) external {
        require(msg.sender == daos[daoId].creator, "Only creator can hide");
        daos[daoId].isHidden = status;
        emit DAOHidden(daoId, status);
    }

    /**
     * @dev Deleting locks the Governor. It cannot be undone.
     */
    function deleteDAO(uint256 daoId) external {
        require(msg.sender == daos[daoId].creator, "Only creator can delete");
        require(!daos[daoId].isDeleted, "Already deleted");
        
        daos[daoId].isDeleted = true;
        daos[daoId].isHidden = true; // Auto-hide on delete
        
        emit DAODeleted(daoId);
    }

    // --- Internal Helpers ---

    function _deployToken(uint8 tType, string memory n, string memory s, uint256 init, uint256 max, string memory bURI) internal returns (address) {
        if (tType == 0) return address(new ERC20VotingPower(n, s, init, max, msg.sender));
        return address(new ERC721VotingPower(n, s, max, bURI));
    }

    function _configureRoles(uint8 tokenType, address token, address governor, address timelock) internal {
        DGPTimelockController tc = DGPTimelockController(payable(timelock));
        
        // Timelock Roles
        tc.grantRole(tc.PROPOSER_ROLE(), governor);
        tc.grantRole(tc.CANCELLER_ROLE(), governor); // Governor can cancel its own queued proposals
        tc.grantRole(tc.EXECUTOR_ROLE(), address(0)); // Public execution
        tc.grantRole(tc.DEFAULT_ADMIN_ROLE(), timelock); // Timelock owns itself
        tc.renounceRole(tc.DEFAULT_ADMIN_ROLE(), address(this));

        // Token Roles
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

    // --- Getters ---
    function getDAO(uint256 daoId) external view returns (DAOConfig memory) {
        return daos[daoId];
    }

    function getDaosByCreator(address creator) external view returns (uint256[] memory) {
        return daoIdsByCreator[creator];
    }
}