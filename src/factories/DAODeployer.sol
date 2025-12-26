// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "../core/DGPGovernor.sol";
import "../core/DGPTimelockController.sol";
import "../core/DGPTreasury.sol";
import "./GovernorRegistry.sol";
import "./DAOTokenFactory.sol";
import "./DAORoleConfigurator.sol";

contract DAODeployer {
    enum TokenType {
        ERC20,
        ERC721
    }

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
    DAOTokenFactory public immutable tokenFactory;
    DAORoleConfigurator public immutable roleConfigurator;

    constructor(address registry_, address tokenFactory_, address _roleConfigurator) {
        registry = GovernorRegistry(registry_);
        tokenFactory = DAOTokenFactory(tokenFactory_);
        roleConfigurator = DAORoleConfigurator(_roleConfigurator);
    }

    /* ================== EXTERNAL ================== */

    function createDAO(CreateDAOParams calldata p)
        external
        returns (uint256 daoId)
    {
        // 1. Reserve DAO ID
        daoId = registry.reserveDAOId(
            msg.sender,
            p.metadataURI,
            p.tokenType
        );

        // 2. Deploy components
        address timelock = _deployTimelock(p.timelockDelay);

        address token = tokenFactory.deployToken(
            p.tokenType,
            p.tokenName,
            p.tokenSymbol,
            p.initialSupply,
            p.maxSupply,
            p.baseURI,
            msg.sender
        );

        address governor = _deployGovernor(
            p,
            token,
            timelock,
            daoId
        );

        address treasury = address(
            new DGPTreasury(timelock, governor)
        );

        // 3. Finalize registry
        registry.finalizeDAO(
            daoId,
            governor,
            timelock,
            treasury,
            token
        );

        // 4. Configure roles
        roleConfigurator.configure(
            address(timelock),
            address(governor),
            address(treasury),
            address(token),
            msg.sender
        );
    }

    /* ================== INTERNAL ================== */

    function _deployTimelock(uint256 delay)
        internal
        returns (address)
    {
        return address(
            new DGPTimelockController(
                delay,
                new address[](0),
                new address[](0),
                address(this)
            )
        );
    }

    function _deployGovernor(
        CreateDAOParams calldata p,
        address token,
        address timelock,
        uint256 daoId
    ) internal returns (address) {
        return address(
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
    }

    function _configureRoles(
        uint8 tokenType,
        address token,
        address governor,
        address timelock
    ) internal {
        DGPTimelockController tc =
            DGPTimelockController(payable(timelock));

        tc.grantRole(tc.PROPOSER_ROLE(), governor);
        tc.grantRole(tc.CANCELLER_ROLE(), governor);
        tc.grantRole(tc.EXECUTOR_ROLE(), address(0));
        tc.grantRole(tc.DEFAULT_ADMIN_ROLE(), timelock);
        tc.renounceRole(tc.DEFAULT_ADMIN_ROLE(), address(this));

        // Token roles (generic interface via call)
        (bool ok, ) = token.call(
            abi.encodeWithSignature(
                "grantRole(bytes32,address)",
                keccak256("MINTER_ROLE"),
                governor
            )
        );
        require(ok, "MINTER_ROLE grant failed");

        (ok, ) = token.call(
            abi.encodeWithSignature(
                "grantRole(bytes32,address)",
                keccak256("DEFAULT_ADMIN_ROLE"),
                timelock
            )
        );
        require(ok, "ADMIN_ROLE grant failed");

        token.call(
            abi.encodeWithSignature(
                "renounceRole(bytes32,address)",
                keccak256("DEFAULT_ADMIN_ROLE"),
                address(this)
            )
        );

        token.call(
            abi.encodeWithSignature(
                "renounceRole(bytes32,address)",
                keccak256("MINTER_ROLE"),
                address(this)
            )
        );
    }
}
