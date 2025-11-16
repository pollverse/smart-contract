// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Votes.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title ERC721VotingPower
 * @dev ERC721 token with voting power delegation and admin-controlled minting.
 * Each NFT = 1 vote. Snapshot balance is counted at proposal start.
 * Only accounts with MINTER_ROLE can mint new tokens.
 */
contract ERC721VotingPower is ERC721, EIP712, ERC721Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    uint256 private _nextTokenId;
    uint256 private immutable _maxSupply;
    string private _baseTokenURI;

    event NFTMinted(address indexed to, uint256 indexed tokenId);

    /**
     * @param name Token name
     * @param symbol Token symbol
     * @param maxSupply_ Maximum number of tokens that can be minted (0 = unlimited)
     * @param baseURI Base URI for token metadata
     */
    constructor(
        string memory name,
        string memory symbol,
        uint256 maxSupply_,
        string memory baseURI
    )
        ERC721(name, symbol)
        EIP712(name, "1")
    {
        _maxSupply = maxSupply_;
        _baseTokenURI = baseURI;

        _nextTokenId = 1;
        
        // Set up roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
    }

    /**
     * @dev Base URI for computing {tokenURI}
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Update the base token URI (only callable by DEFAULT_ADMIN_ROLE)
     * @param newBaseURI New base URI for token metadata
     */
    function setBaseURI(string memory newBaseURI) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _baseTokenURI = newBaseURI;
    }

    /**
     * @dev Mint a new token to the specified address (only callable by MINTER_ROLE)
     * @param to Address that will receive the minted token
     * @return tokenId The ID of the newly minted token
     */
    function mint(address to) external onlyRole(MINTER_ROLE) returns (uint256) {
        require(to != address(0), "Cannot mint to zero address");
        if (_maxSupply > 0) {
            require(_nextTokenId <= _maxSupply, "Max supply reached");
        }
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);

        emit NFTMinted(to, tokenId);

        return tokenId;
    }

    /**
     * @dev Batch mint multiple tokens to the specified address (only callable by MINTER_ROLE)
     * @param to Address that will receive the minted tokens
     * @param quantity Number of tokens to mint
     */
    function batchMint(address to, uint256 quantity) external onlyRole(MINTER_ROLE) {
        require(to != address(0), "Cannot mint to zero address");
        require(quantity > 0, "Quantity must be greater than 0");
        if (_maxSupply > 0) {
            require(_nextTokenId + quantity - 1 <= _maxSupply, "Exceeds max supply");
        }
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId++;
            _safeMint(to, tokenId);
            emit NFTMinted(to, tokenId);
        }
    }

    /**
     * @dev Get the total number of tokens in existence
     */
    function totalSupply() external view returns (uint256) {
        return _nextTokenId - 1;
    }

    /**
     * @dev Get the maximum supply of tokens (0 = unlimited)
     */
    function maxSupply() external view returns (uint256) {
        return _maxSupply;
    }

    // OpenZeppelin style overrides for ERC721Votes
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Votes)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Votes)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function setMinter(address newMinter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMinter != address(0), "Invalid minter");
        _grantRole(MINTER_ROLE, newMinter);
    }
}
