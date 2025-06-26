// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract SafeVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant BRIDGE_ROLE = keccak256("BRIDGE_ROLE");

    IERC20 public immutable usdc;

    mapping(address => uint256) public _balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 available, uint256 required);

    constructor(address defaultAdmin, address usdcAddress) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        usdc = IERC20(usdcAddress);
    }

    function processDeposit(address user, uint256 amount) external onlyRole(BRIDGE_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _balances[user] += amount;
        emit Deposit(user, amount);
    }

    function requestWithdraw(address user, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();
        uint256 bal = _balances[user];
        if (bal < amount) revert InsufficientBalance(bal, amount);
        _balances[user] = bal - amount;
        usdc.safeTransfer(user, amount);
        emit Withdraw(user, amount);
    }

    function getBalance(address user) external view returns (uint256) {
        return _balances[user];
    }
}