// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Funding is Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address initialOwner, address _tokenAddress) Ownable(initialOwner) {
        require(_tokenAddress != address(0), "Invalid token address");
        token = IERC20(_tokenAddress);
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        // Transfer USDT from the sender to this contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Update user balance
        balances[msg.sender] += amount;

        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        uint256 userBalance = balances[msg.sender];
        require(userBalance >= amount, "Insufficient balance");

        // Update user balance
        balances[msg.sender] = userBalance - amount;

        // Transfer USDT back to the user
        token.safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

}
