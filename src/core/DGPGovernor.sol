// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title DGPGovernor
 * @dev Governor implementation using OpenZeppelin Governor modules (Settings, CountingSimple, Votes, TimelockControl)
 * - Uses TimelockController from OpenZeppelin for execution/queueing.
 * - Minimal persistent proposal metadata (text fields) stored; vote totals are computed on-read to avoid stale state and save gas.
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
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";

// Optional: use your custom error library if present. If not, replace these with require(...) messages.
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

    /// @notice members tracked by owner (simple membership registry)
    mapping(address => bool) private _isMember;
    address[] private _members;

    event MemberAdded(address indexed member, uint256 votingPower);
    event MemberRemoved(address indexed member);

    enum ProposalStatus { Draft, Active, Passed, Failed, Queued, Executed }

    struct ProposalMetadata {
        string title;
        string description;
        string proposalType;
        string proposedSolution;
        string rationale;
        string expectedOutcomes;
        string timeline;
        string budget;
        address proposer;
        uint256 timestamp;
    }

    /// @notice minimal metadata stored per proposal (heavy text fields stored; vote counts computed on read)
    mapping(uint256 => ProposalMetadata) private _proposalMetadata;

    uint256 public constant MAX_VOTING_POWER = 10_000 * 1e18;

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
        Governor("Decentralized Governance Protocol Governor")
        GovernorSettings(
            SafeCast.toUint48(_votingDelay),
            SafeCast.toUint32(_votingPeriod),
            _proposalThreshold
        )
        GovernorVotes(_token)
        GovernorTimelockControl(_timelock)
        Ownable(admin)
    {
        // validate quorum: 1 <= quorumPercentage < 100
        if (!(quorumPercentage_ >= 1 && quorumPercentage_ < 100)) {
            revert GovernorError.InvalidQuorumPercentage();
        }
        _quorumPercentage = quorumPercentage_;
        // set owner
        _transferOwnership(admin);
    }

    // -----------------------
    // Member management
    // -----------------------

    function addMember(address member, uint256 votingPower) external onlyOwner {
        if (member == address(0)) revert GovernorError.InvalidMember();
        if (_isMember[member]) revert GovernorError.AlreadyAMember();
        _isMember[member] = true;
        _members.push(member);
        // mint voting power (tries ERC20 mint then ERC721 mint)
        _mintVotingPower(member, votingPower);
        emit MemberAdded(member, votingPower);
    }

    function batchAddMembers(address[] calldata members, uint256[] calldata votingPowers) external onlyOwner {
        if (members.length != votingPowers.length) revert GovernorError.LengthMismatch();
        for (uint256 i = 0; i < members.length; i++) {
            address m = members[i];
            uint256 vp = votingPowers[i];
            if (m == address(0)) revert GovernorError.InvalidMember();
            if (_isMember[m]) revert GovernorError.AlreadyAMember();
            _isMember[m] = true;
            _members.push(m);
            _mintVotingPower(m, vp);
            emit MemberAdded(m, vp);
        }
    }

    function removeMember(address member) external onlyOwner {
        if (!_isMember[member]) revert GovernorError.NotAMember();
        _isMember[member] = false;
        // remove from array (swap-pop)
        for (uint256 i = 0; i < _members.length; i++) {
            if (_members[i] == member) {
                _members[i] = _members[_members.length - 1];
                _members.pop();
                break;
            }
        }
        emit MemberRemoved(member);
    }

    function listMembers() external view returns (address[] memory) {
        return _members;
    }

    // -----------------------
    // Proposal metadata + creation
    // -----------------------

    /**
     * @dev Create a proposal with human-readable metadata stored on-chain.
     * The actual proposal executable payloads are the (targets, values, calldatas).
     */
    function createProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory title,
        string memory description,
        string memory proposalType,
        string memory proposedSolution,
        string memory rationale,
        string memory expectedOutcomes,
        string memory timeline,
        string memory budget
    ) public returns (uint256 proposalId) {
        // compose description for governor (title + newline + description)
        string memory fullDescription = string(abi.encodePacked(title, "\n", description));
        proposalId = propose(targets, values, calldatas, fullDescription);

        _proposalMetadata[proposalId] = ProposalMetadata({
            title: title,
            description: description,
            proposalType: proposalType,
            proposedSolution: proposedSolution,
            rationale: rationale,
            expectedOutcomes: expectedOutcomes,
            timeline: timeline,
            budget: budget,
            proposer: msg.sender,
            timestamp: block.timestamp
        });
    }

    /**
     * @dev Return on-chain metadata + computed vote totals and quorum percentage reached at snapshot.
     */
    function getProposalMetadata(uint256 proposalId) external view returns (
        ProposalMetadata memory meta,
        uint256 votesFor,
        uint256 votesAgainst,
        uint256 quorumReachedPct,
        ProposalStatus status
    ) {
        meta = _proposalMetadata[proposalId];

        // compute votes
        (votesFor, votesAgainst, ) = proposalVotes(proposalId);

        // compute total supply at snapshot and derive quorum percentage reached
        uint256 snapshot = proposalSnapshot(proposalId);
        uint256 totalSupply = token().getPastTotalSupply(snapshot);
        quorumReachedPct = totalSupply > 0 ? (votesFor * 100) / totalSupply : 0;

        // map Governor's ProposalState to ProposalStatus
        ProposalState st = state(proposalId);
        if (st == ProposalState.Pending) status = ProposalStatus.Draft;
        else if (st == ProposalState.Active) status = ProposalStatus.Active;
        else if (st == ProposalState.Succeeded) status = ProposalStatus.Passed;
        else if (st == ProposalState.Defeated) status = ProposalStatus.Failed;
        else if (st == ProposalState.Queued) status = ProposalStatus.Queued;
        else if (st == ProposalState.Executed) status = ProposalStatus.Executed;
        else status = ProposalStatus.Draft; // fallback
    }

    // Prevent proposal creator from voting on their own proposal (custom rule)
    function castVote(uint256 proposalId, uint8 support) public override returns (uint256) {
        ProposalMetadata memory meta = _proposalMetadata[proposalId];
        if (meta.proposer != address(0) && msg.sender == meta.proposer) revert GovernorError.CreatorCannotVote();
        return super.castVote(proposalId, support);
    }

    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) public override returns (uint256) {
        ProposalMetadata memory meta = _proposalMetadata[proposalId];
        if (meta.proposer != address(0) && msg.sender == meta.proposer) revert GovernorError.CreatorCannotVote();
        return super.castVoteWithReason(proposalId, support, reason);
    }

    // -----------------------
    // Minting voting power helper
    // -----------------------

    /**
     * @dev Internal helper that tries to mint voting power.
     * First attempts ERC20-style mint(address,uint256).
     * If that fails, attempts ERC721-style mint(address) `amount` times.
     * Reverts if neither succeeds.
     */
    function _mintVotingPower(address to, uint256 amount) internal {
        // try ERC20 mint(address,uint256)
        (bool ok, bytes memory ret) = address(token()).call(
            abi.encodeWithSignature("mint(address,uint256)", to, amount)
        );
        if (ok) {
            // success on ERC20-style mint
            return;
        }

        // try ERC721 mint(address) repeated amount times
        for (uint256 i = 0; i < amount; i++) {
            (bool okNft, bytes memory retNft) = address(token()).call(
                abi.encodeWithSignature("mint(address)", to)
            );
            if (!okNft) {
                // bubble up revert reason if present, otherwise revert with custom error
                if (retNft.length > 0) {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(retNft, 32), mload(retNft))
                    }
                }
                revert GovernorError.MintFailed();
            }
        }
    }

    /**
     * @dev External owner function to mint voting power (with optional safety cap check for ERC20).
     */
    function mintVotingPower(address to, uint256 amount) external onlyOwner {
        if (!_isMember[to]) revert GovernorError.NotAMember();

        // try to check ERC20 balance cap; if token isn't ERC20, skip
        try IERC20(address(token())).balanceOf(to) returns (uint256 currentBalance) {
            if (currentBalance + amount >= MAX_VOTING_POWER) revert GovernorError.ExceedsAllowedLimit();
        } catch {
            // treat as non-ERC20 (ERC721) — skip cap check
        }

        _mintVotingPower(to, amount);
    }

    // -----------------------
    // Quorum / overrides
    // -----------------------

    /**
     * @dev quorum calculated as percentage of past total supply at `blockNumber`.
     */
    function quorum(uint256 blockNumber) public view override returns (uint256) {
        uint256 totalSupply = token().getPastTotalSupply(blockNumber);
        return (totalSupply * _quorumPercentage) / 100;
    }

    function quorumPercentage() public view returns (uint256) {
        return _quorumPercentage;
    }

    // preserve GovernorSettings' proposalThreshold
    function proposalThreshold()
        public
        view
        override(Governor, GovernorSettings)
        returns (uint256)
    {
        return super.proposalThreshold();
    }

    // Required overrides for multiple inheritance

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

    // support interface
    // function supportsInterface(bytes4 interfaceId)
    //     public
    //     view
    //     override(Governor, GovernorTimelockControl)
    //     returns (bool)
    // {
    //     return super.supportsInterface(interfaceId);
    // }
}
