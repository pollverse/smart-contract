// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract GovernorRegistry {
    struct DAOConfig {
        address governor;
        address timelock;
        address treasury;
        address token;
        address creator;
        uint8 tokenType;
        uint32 createdAt;
        bool isHidden;
        bool isDeleted;
        string metadataURI;
    }

    DAOConfig[] private _daos;
    mapping(address => uint256[]) private _daoIdsByCreator;

    event DAOCreated(uint256 indexed daoId, address indexed governor, string metadataURI, address creator);
    event DAOHidden(uint256 indexed daoId, bool status);
    event DAODeleted(uint256 indexed daoId);

    /* ---------------- DAO lifecycle ---------------- */

    function registerDAO(DAOConfig calldata cfg) external returns (uint256 daoId) {
        daoId = _daos.length;
        _daos.push(cfg);
        _daoIdsByCreator[cfg.creator].push(daoId);

        emit DAOCreated(daoId, cfg.governor, cfg.metadataURI, cfg.creator);
    }

    function setHidden(uint256 daoId, bool status) external {
        require(msg.sender == _daos[daoId].creator, "Only creator");
        _daos[daoId].isHidden = status;
        emit DAOHidden(daoId, status);
    }

    function deleteDAO(uint256 daoId) external {
        require(msg.sender == _daos[daoId].creator, "Only creator");
        require(!_daos[daoId].isDeleted, "Already deleted");

        _daos[daoId].isDeleted = true;
        _daos[daoId].isHidden = true;

        emit DAODeleted(daoId);
    }

    /* ---------------- View helpers ---------------- */

    function getDAO(uint256 daoId) external view returns (DAOConfig memory) {
        return _daos[daoId];
    }

    function getDaosByCreator(address creator) external view returns (uint256[] memory) {
        return _daoIdsByCreator[creator];
    }

    function isDeleted(uint256 daoId) external view returns (bool) {
        return _daos[daoId].isDeleted;
    }
}
