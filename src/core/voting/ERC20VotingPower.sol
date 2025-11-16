// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title DGPTreasury
 * @dev DAO-controlled treasury for managing ETH and ERC20 assets.
 * Execution of spending is restricted to Governor through Timelock.
 * The governor address should be the Timelock contract, not the Governor directly.
 */
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract DGPTreasury {
    using SafeERC20 for IERC20;

    address public immutable timelock;
    address public immutable governor;
    
    event ETHWithdrawn(address indexed recipient, uint256 amount);
    event TokenWithdrawn(address indexed token, address indexed recipient, uint256 amount);
    event ETHReceived(address indexed sender, uint256 amount);

    modifier onlyTimelock() {
        require(msg.sender == timelock, "DGPTreasury: caller is not timelock");
        _;
    }

    /**
     * @param _timelock Address of the TimelockController (not the Governor directly)
     * @param _governor Address of the Governor contract
     */
    constructor(address _timelock, address _governor) {
        require(_timelock != address(0), "DGPTreasury: invalid timelock address");
        require(_governor != address(0), "DGPTreasury: invalid governor address");
        timelock = _timelock;
        governor = _governor;
    }

    /**
     * @dev Withdraw ETH from treasury
     * @param recipient Address to receive ETH
     * @param amount Amount of ETH to withdraw
     */
    function withdrawETH(address payable recipient, uint256 amount) external onlyTimelock {
        require(recipient != address(0), "DGPTreasury: invalid recipient");
        require(amount > 0, "DGPTreasury: amount must be greater than 0");
        require(address(this).balance >= amount, "DGPTreasury: insufficient balance");
        
        (bool success, ) = recipient.call{value: amount}("");
        require(success, "DGPTreasury: ETH transfer failed");
        
        emit ETHWithdrawn(recipient, amount);
    }

    /**
     * @dev Withdraw ERC20 tokens from treasury
     * @param token Address of the ERC20 token
     * @param recipient Address to receive tokens
     * @param amount Amount of tokens to withdraw
     */
    function withdrawToken(address token, address recipient, uint256 amount) external onlyTimelock {
        require(token != address(0), "DGPTreasury: invalid token address");
        require(recipient != address(0), "DGPTreasury: invalid recipient");
        require(amount > 0, "DGPTreasury: amount must be greater than 0");
        
        IERC20(token).safeTransfer(recipient, amount);

        emit TokenWithdrawn(token, recipient, amount);
    }

    /**
     * @dev Get ETH balance of treasury
     */
    function getETHBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get token balance of treasury
     * @param token Address of the ERC20 token
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
    /**
     * @dev Receive ETH
     */
    receive() external payable {
        emit ETHReceived(msg.sender, msg.value);
    }
}