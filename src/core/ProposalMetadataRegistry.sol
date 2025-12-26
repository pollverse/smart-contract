// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {GovernorError} from "../libraries/Errors.sol";

/**
 * @title ProposalMetadataRegistry
 * @dev Stores lightweight proposal metadata for governors.
 * Governor remains the source of truth for proposal lifecycle.
 */
contract ProposalMetadataRegistry {
    struct ProposalMetadata {
        address proposer;
        uint64 timestamp;
        string metadataURI;
    }

    /// governor => proposalId => metadata
    mapping(address => mapping(uint256 => ProposalMetadata)) private _metadata;

    address public immutable governor;

    event ProposalMetadataStored(
        uint256 indexed proposalId,
        address indexed proposer,
        string metadataURI
    );

    event MetadataURIUpdated(uint256 indexed proposalId, string newURI);

    modifier onlyGovernor() {
        require(msg.sender == governor, "Only governor");
        _;
    }

    constructor(address _governor) {
        require(_governor != address(0), "Invalid governor");
        governor = _governor;
    }

    function store(
        uint256 proposalId,
        address proposer,
        string calldata metadataURI
    ) external onlyGovernor {
        if (bytes(metadataURI).length == 0) {
            revert GovernorError.InvalidMetadataURI();
        }

        _metadata[governor][proposalId] = ProposalMetadata({
            proposer: proposer,
            timestamp: uint64(block.timestamp),
            metadataURI: metadataURI
        });

        emit ProposalMetadataStored(proposalId, proposer, metadataURI);
    }

    function updateURI(uint256 proposalId, string calldata newURI) external onlyGovernor {
        if (bytes(newURI).length == 0) {
            revert GovernorError.InvalidMetadataURI();
        }

        _metadata[governor][proposalId].metadataURI = newURI;
        emit MetadataURIUpdated(proposalId, newURI);
    }

    function get(uint256 proposalId) external view returns (ProposalMetadata memory) {
        return _metadata[governor][proposalId];
    }

    function getURI(uint256 proposalId) external view returns (string memory) {
        return _metadata[governor][proposalId].metadataURI;
    }

    function getProposer(uint256 proposalId) external view returns (address) {
        return _metadata[governor][proposalId].proposer;
    }
}
