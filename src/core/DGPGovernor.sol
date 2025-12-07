// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title DGPGovernor
 * @dev Governor implementation using OpenZeppelin Governor modules (Settings, CountingSimple, Votes, TimelockControl)
 * - Uses TimelockController from OpenZeppelin for execution/queueing.
 * - OPTIMIZED: Minimal on-chain proposal metadata (only proposer + timestamp).
 * - Full proposal details stored off-chain via metadata URI (backend/IPFS).
 * - Vote totals computed on-read to avoid stale state and save gas.
 *
 * Note: ensure factory passes TimelockController (or change the constructor arg to your DGPTimelockController type).
 */

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GovernorError} from "../libraries/Errors.sol";

contract DGPGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorTimelockControl,
    Ownable
{
    using SafeCast for uint256;
    using Address for address;

    /// @notice quorum percentage (1..99)
    uint256 private _quorumPercentage;
    
    struct ProposalMetadata {
        address proposer;
        uint64 timestamp;
        string metadataURI;
    }

    /// @notice minimal metadata stored per proposal
    mapping(uint256 => ProposalMetadata) private _proposalMetadata;

    uint256 public constant MAX_VOTING_POWER = 10_000 * 1e18;

    event ProposalCreated(uint256 indexed proposalId, string metadataURI);
    event MetadataURIUpdated(uint256 indexed proposalId, string newURI);

    // -----------------------
    // constructor
    // -----------------------
    constructor(
        IVotes _token,
        TimelockController _timelock,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        uint256 quorumPercentage_,
        address admin
    )
        Governor("DGP Governor")
        GovernorSettings(
            SafeCast.toUint48(_votingDelay),
            SafeCast.toUint32(_votingPeriod),
            _proposalThreshold
        )
        GovernorVotes(_token)
        GovernorTimelockControl(_timelock)
        Ownable(admin)
    {
        if (!(quorumPercentage_ >= 1 && quorumPercentage_ < 100)) {
            revert GovernorError.InvalidQuorumPercentage();
        }
        _quorumPercentage = quorumPercentage_;
        _transferOwnership(admin);
    }

    // -----------------------
    // Proposal metadata + creation
    // -----------------------

    /**
     * @dev Create a proposal with minimal on-chain metadata.
     * Full proposal details stored off-chain (backend/IPFS) via metadataURI.
     * @param metadataURI Points to JSON object containing: title, description, proposalType, proposedSolution, rationale, expectedOutcomes, timeline, budget
     *        Example: "ipfs://QmXxxx" or "https://api.backend.com/proposals/{id}"
     */
    function createProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory metadataURI
    ) public returns (uint256 proposalId) {
        if (bytes(metadataURI).length == 0) revert GovernorError.InvalidMetadataURI();
        
        // Create proposal with minimal description (just references backend)
        proposalId = propose(targets, values, calldatas, metadataURI);

        _proposalMetadata[proposalId] = ProposalMetadata({
            proposer: msg.sender,
            timestamp: uint64(block.timestamp),
            metadataURI: metadataURI
        });

        emit ProposalCreated(proposalId, metadataURI);
    }

    /**
     * @dev Allow owner to update metadata URI if needed (e.g., IPFS pinning)
     */
    function updateMetadataURI(uint256 proposalId, string memory newURI) external onlyOwner {
        if (bytes(newURI).length == 0) revert GovernorError.InvalidMetadataURI();
        _proposalMetadata[proposalId].metadataURI = newURI;
        emit MetadataURIUpdated(proposalId, newURI);
    }

    function getProposalMetadata(uint256 proposalId) external view returns (ProposalMetadata memory) {
        return _proposalMetadata[proposalId];
    }

    function getProposalVotes(uint256 proposalId) external view returns (uint256, uint256, uint256) {
        return proposalVotes(proposalId);
    }

    function getMetadataURI(uint256 proposalId) external view returns (string memory) {
        return _proposalMetadata[proposalId].metadataURI;
    }

    function castVote(uint256 proposalId, uint8 support) public override returns (uint256) {
        address proposer = _proposalMetadata[proposalId].proposer;
        if (proposer != address(0) && msg.sender == proposer) {
            revert GovernorError.CreatorCannotVote();
        }
        return super.castVote(proposalId, support);
    }

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) public override returns (uint256) {
        address proposer = _proposalMetadata[proposalId].proposer;
        if (proposer != address(0) && msg.sender == proposer) {
            revert GovernorError.CreatorCannotVote();
        }
        return super.castVoteWithReason(proposalId, support, reason);
    }

    // -----------------------
    // Minting voting power helper
    // -----------------------

    function _mintVotingPower(address to, uint256 amount) internal {
        (bool ok, ) = address(token()).call(
            abi.encodeWithSignature("mint(address,uint256)", to, amount)
        );
        if (!ok) {
            for (uint256 i; i < amount; ++i) {
                (bool okNft, bytes memory retNft) = address(token()).call(
                    abi.encodeWithSignature("mint(address)", to)
                );
                if (!okNft) {
                    if (retNft.length > 0) {
                        assembly {
                            revert(add(retNft, 32), mload(retNft))
                        }
                    }
                    revert GovernorError.MintFailed();
                }
            }
        }
    }

    function mintVotingPower(address to, uint256 amount) external onlyOwner {
        try IERC20(address(token())).balanceOf(to) returns (uint256 currentBalance) {
            if (currentBalance + amount >= MAX_VOTING_POWER) revert GovernorError.ExceedsAllowedLimit();
        } catch {}

        _mintVotingPower(to, amount);
    }

    // -----------------------
    // Quorum / overrides
    // -----------------------

    function quorum(uint256 blockNumber) public view override returns (uint256) {
        uint256 totalSupply = token().getPastTotalSupply(blockNumber);
        return (totalSupply * _quorumPercentage) / 100;
    }

    function quorumPercentage() public view returns (uint256) {
        return _quorumPercentage;
    }

    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
