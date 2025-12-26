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

    /* ================= DAO LIFECYCLE ================= */

    /// @notice Step 1 — reserve DAO ID with minimal data
    function reserveDAOId(
        address creator,
        string calldata metadataURI,
        uint8 tokenType
    ) external returns (uint256 daoId) {
        daoId = _daos.length;

        _daos.push(
            DAOConfig({
                governor: address(0),
                timelock: address(0),
                treasury: address(0),
                token: address(0),
                creator: creator,
                tokenType: tokenType,
                createdAt: uint32(block.timestamp),
                isHidden: false,
                isDeleted: false,
                metadataURI: metadataURI
            })
        );

        _daoIdsByCreator[creator].push(daoId);
    }

    /// @notice Step 2 — finalize DAO after deployment
    function finalizeDAO(
        uint256 daoId,
        address governor,
        address timelock,
        address treasury,
        address token
    ) external {
        DAOConfig storage dao = _daos[daoId];

        require(dao.governor == address(0), "DAO already finalized");

        dao.governor = governor;
        dao.timelock = timelock;
        dao.treasury = treasury;
        dao.token = token;

        emit DAOCreated(daoId, governor, dao.metadataURI, dao.creator);
    }

    /* ================= DAO CONTROLS ================= */

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

    /* ================= VIEW HELPERS ================= */

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
