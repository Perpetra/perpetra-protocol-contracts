// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip@1.6.0/contracts/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts@1.4.0/src/v0.8/shared/access/OwnerIsCreator.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {Client} from "@chainlink/contracts-ccip@1.6.0/contracts/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISafeVault {
    function processDeposit(address user, uint256 amount) external;
    function requestWithdraw(address user, uint256 amount) external;
}

contract CrossChainBridge is OwnerIsCreator {
    using SafeERC20 for IERC20;

    uint64 public constant VAULT_CHAIN_ID = 11155111; // Sepolia

    IRouterClient private s_router;
    IERC20 public immutable usdc;
    address public safeVault;
    uint64 public destinationChainSelector;

    event LocalDeposit(address indexed user, uint256 amount);
    event CCIPDepositSent(address indexed user, uint256 amount, bytes32 messageId);
    event CCIPDepositReceived(address indexed user, uint256 amount);

    error DestinationChainNotAllowlisted(uint64 chain);
    error NotEnoughNativeFee(uint256 balance, uint256 fee);

    constructor(
        address _router,
        address _usdc,
        address _safeVault,
        uint64 _destinationChainSelector
    ) {
        s_router = IRouterClient(_router);
        usdc = IERC20(_usdc);
        safeVault = _safeVault;
        destinationChainSelector = _destinationChainSelector;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        usdc.safeTransferFrom(msg.sender, address(this), amount);

        emit LocalDeposit(msg.sender, amount);

        if (block.chainid == VAULT_CHAIN_ID) {
            ISafeVault(safeVault).processDeposit(msg.sender, amount);
        } else {
            bytes32 messageId = _sendCrossChain(amount);
            emit CCIPDepositSent(msg.sender, amount, messageId);
        }
    }

    function requestWithdraw(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        if (block.chainid == VAULT_CHAIN_ID) {
            ISafeVault(safeVault).requestWithdraw(msg.sender, amount);
        }
    }

    function _sendCrossChain(uint256 amount) internal returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            safeVault,
            address(usdc),
            amount,
            address(0)
        );

        uint256 fees = s_router.getFee(
            destinationChainSelector,
            evm2AnyMessage
        );

        if (fees > address(this).balance)
            revert NotEnoughNativeFee(address(this).balance, fees);

        IERC20(usdc).approve(address(s_router), amount);

        messageId = s_router.ccipSend{value: fees}(
            destinationChainSelector,
            evm2AnyMessage
        );

        return messageId;
    }

    function _buildCCIPMessage(
        address _receiver,
        address _token,
        uint256 _amount,
        address _feeTokenAddress
    ) private pure returns (Client.EVM2AnyMessage memory) {
        // Set the token amounts
        Client.EVMTokenAmount[]
        memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });

        // Create an EVM2AnyMessage struct in memory with necessary information for sending a cross-chain message
        return
            Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver), // ABI-encoded receiver address
            data: "", // No data
            tokenAmounts: tokenAmounts, // The amount and type of token being transferred
            extraArgs: Client._argsToBytes(
        // Additional arguments, setting gas limit and allowing out-of-order execution.
        // Best Practice: For simplicity, the values are hardcoded. It is advisable to use a more dynamic approach
        // where you set the extra arguments off-chain. This allows adaptation depending on the lanes, messages,
        // and ensures compatibility with future CCIP upgrades. Read more about it here: https://docs.chain.link/ccip/concepts/best-practices/evm#using-extraargs
                Client.GenericExtraArgsV2({
                    gasLimit: 0, // Gas limit for the callback on the destination chain
                    allowOutOfOrderExecution: true // Allows the message to be executed out of order relative to other messages from the same sender
                })
            ),
        // Set the feeToken to a feeTokenAddress, indicating specific asset will be used for fees
            feeToken: _feeTokenAddress
        });
    }

    // --- Admin ---

    function setSafeVault(address _vault) external onlyOwner {
        safeVault = _vault;
    }

    function setDestinationChainSelector(uint64 selector) external onlyOwner {
        destinationChainSelector = selector;
    }

    function withdrawToken(address _token, address to) external onlyOwner {
        uint256 bal = IERC20(_token).balanceOf(address(this));
        require(bal > 0, "Nothing to withdraw");
        IERC20(_token).safeTransfer(to, bal);
    }

    function withdrawNative(address to) external onlyOwner {
        uint256 amount = address(this).balance;
        require(amount > 0, "Nothing to withdraw");
        (bool success, ) = to.call{value: amount}("");
        require(success, "Withdraw failed");
    }

    receive() external payable {}
}
