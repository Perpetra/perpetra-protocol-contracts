// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PerpetraSafeVault is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    IERC20 public immutable usdc;
    AggregatorV3Interface public priceFeed;

    mapping(address => uint256) public _balances;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(uint256 available, uint256 required);

    constructor(
        address defaultAdmin,
        address usdcAddress,
        address priceFeedAddress
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        usdc = IERC20(usdcAddress);
        priceFeed = AggregatorV3Interface(priceFeedAddress);
    }

    function processDeposit(
        address user,
        uint256 amount
    ) external onlyRole(DEPOSITOR_ROLE) {
        if (user == address(0)) revert ZeroAddress();
        if (amount == 0) revert ZeroAmount();

        _balances[user] += amount;
        emit Deposit(user, amount);
    }

    function requestWithdraw(
        address user,
        uint256 amount
    ) external onlyRole(DEPOSITOR_ROLE) nonReentrant {
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

    function getLatestPrice() public view returns (int256) {
        // Chainlink Data Feed
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }

    function getBalanceInUSD(address user) external view returns (uint256) {
        uint256 balance = _balances[user];
        int256 price = getLatestPrice();
        require(price > 0, "Invalid price");

        return (balance * uint256(price)) / 1e8;
    }
}
