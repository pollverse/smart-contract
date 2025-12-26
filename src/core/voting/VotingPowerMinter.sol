// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import {GovernorError} from "../../libraries/Errors.sol";

contract VotingPowerMinter {
    uint256 public constant MAX_VOTING_POWER = 10_000 * 1e18;

    address public immutable governor;
    IVotes public immutable token;

    modifier onlyGovernor() {
        require(msg.sender == governor, "Only governor");
        _;
    }

    constructor(address _governor, IVotes _token) {
        governor = _governor;
        token = _token;
    }

    function mint(address to, uint256 amount) external onlyGovernor {
        // ERC20 balance check (safe to fail)
        try IERC20(address(token)).balanceOf(to) returns (uint256 bal) {
            if (bal + amount >= MAX_VOTING_POWER) {
                revert GovernorError.ExceedsAllowedLimit();
            }
        } catch {}

        // Try ERC20 mint
        (bool ok, ) = address(token).call(
            abi.encodeWithSignature("mint(address,uint256)", to, amount)
        );

        if (ok) return;

        // Fallback → ERC721 mint loop
        for (uint256 i; i < amount; ++i) {
            (bool okNft, bytes memory ret) = address(token).call(
                abi.encodeWithSignature("mint(address)", to)
            );

            if (!okNft) {
                if (ret.length > 0) {
                    assembly {
                        revert(add(ret, 32), mload(ret))
                    }
                }
                revert GovernorError.MintFailed();
            }
        }
    }
}
