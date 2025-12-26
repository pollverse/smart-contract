// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../core/voting/ERC20VotingPower.sol";
import "../core/voting/ERC721VotingPower.sol";

contract DAOTokenFactory {
    enum TokenType {
        ERC20,
        ERC721
    }

    function deployToken(
        uint8 tokenType,
        string calldata name,
        string calldata symbol,
        uint256 initialSupply,
        uint256 maxSupply,
        string calldata baseURI,
        address creator
    ) external returns (address) {
        if (tokenType == uint8(TokenType.ERC20)) {
            return address(
                new ERC20VotingPower(
                    name,
                    symbol,
                    initialSupply,
                    maxSupply,
                    creator
                )
            );
        }

        return address(
            new ERC721VotingPower(
                name,
                symbol,
                maxSupply,
                baseURI
            )
        );
    }
}
