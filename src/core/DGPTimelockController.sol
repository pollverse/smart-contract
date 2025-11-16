// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title DGPTimelockController
 * @dev Enforces a mandatory delay before executing successful proposals.
 * Protects against malicious instant actions by giving community time to react.
 */
import "@openzeppelin/contracts/governance/TimelockController.sol";
import {TimelockError} from "../libraries/Errors.sol";

contract DGPTimelockController is TimelockController {
    /**
     * @param minDelay Minimum delay in seconds before execution
     * @param proposers Array of addresses that can propose (typically the Governor)
     * @param executors Array of addresses that can execute (address(0) = anyone can execute)
     * @param admin Address with admin rights (should be renounced after setup)
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    )
        TimelockController(minDelay, proposers, executors, admin)
    {
        if (minDelay < 1 days) revert TimelockError.DelayTooShortForSecurity();
    }
}