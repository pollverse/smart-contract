// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library FactoryError {
    error DAODoesNotExist();
}

library GovernorError {
    error InvalidQuorumPercentage();
    error InvalidMember();
    error AlreadyAMember();
    error LengthMismatch();
    error NotAMember();
    error CreatorCannotVote();
    error ExceedsAllowedLimit();
    error MintFailed();
}

library TimelockError {
    error DelayTooShortForSecurity();
}