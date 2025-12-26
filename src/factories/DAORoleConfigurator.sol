// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

contract DAORoleConfigurator {
    /* ---------------- Timelock roles ---------------- */
    bytes32 internal constant TIMELOCK_ADMIN_ROLE = keccak256("TIMELOCK_ADMIN_ROLE");
    bytes32 internal constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 internal constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");

    /* ---------------- Treasury roles ---------------- */
    bytes32 internal constant TREASURY_ADMIN_ROLE = keccak256("TREASURY_ADMIN_ROLE");

    /* ---------------- Token roles ---------------- */
    bytes32 internal constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function configure(
        address timelock,
        address governor,
        address treasury,
        address token,
        address deployer
    ) external {
        _configureTimelock(timelock, governor, deployer);
        _configureTreasury(treasury, timelock, deployer);
        _configureToken(token, governor, deployer);
    }

    /* ---------------- Internal helpers ---------------- */

    function _configureTimelock(
        address timelock,
        address governor,
        address deployer
    ) internal {
        IAccessControl tl = IAccessControl(timelock);

        tl.grantRole(PROPOSER_ROLE, governor);
        tl.grantRole(EXECUTOR_ROLE, address(0)); // open execution
        tl.grantRole(CANCELLER_ROLE, governor);

        tl.revokeRole(TIMELOCK_ADMIN_ROLE, deployer);
    }

    function _configureTreasury(
        address treasury,
        address timelock,
        address deployer
    ) internal {
        IAccessControl tr = IAccessControl(treasury);

        tr.grantRole(TREASURY_ADMIN_ROLE, timelock);
        tr.revokeRole(TREASURY_ADMIN_ROLE, deployer);
    }

    function _configureToken(
        address token,
        address governor,
        address deployer
    ) internal {
        if (token == address(0)) return;

        IAccessControl tk = IAccessControl(token);

        tk.grantRole(MINTER_ROLE, governor);
        tk.revokeRole(MINTER_ROLE, deployer);
    }
}
