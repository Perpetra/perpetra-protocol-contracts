// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/contracts/interfaces/IRouterClient.sol";
import {OwnerIsCreator} from "@chainlink/contracts/src/v0.8/shared/access/OwnerIsCreator.sol";
import {Client} from "@chainlink/contracts-ccip/contracts/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/contracts/applications/CCIPReceiver.sol";
import {IERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/utils/SafeERC20.sol";

interface ISafeVault {
    function processDeposit(address wallet, uint256 amount) external;
    function requestWithdraw(address wallet, uint256 amount) external;
}

contract CrossChainBridge is CCIPReceiver, OwnerIsCreator {
    using SafeERC20 for IERC20;

    uint64 public constant VAULT_CHAIN_ID = 11155111; // Sepolia

    IERC20 public immutable usdc;
    address public safeVaultSepolia;
    address public perpetraCrossChainBridgeSepolia;
    uint64 public destinationChainSelector;

    bytes32 public lastReceivedMessageId;

    enum ActionType { Deposit, Withdraw }

    error NotEnoughNativeFee(uint256 balance, uint256 fee);

    constructor(
        address _router,
        address _usdc,
        uint64 _destinationChainSelector
    ) CCIPReceiver(_router) {
        usdc = IERC20(_usdc);
        destinationChainSelector = _destinationChainSelector;
    }

    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        usdc.safeTransferFrom(msg.sender, address(this), amount);

        if (block.chainid == VAULT_CHAIN_ID) {
            ISafeVault(safeVaultSepolia).processDeposit(msg.sender, amount);
        } else {
            _sendCrossChain(ActionType.Deposit, msg.sender, amount);
        }
    }

    function requestWithdraw(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");

        if (block.chainid == VAULT_CHAIN_ID) {
            ISafeVault(safeVaultSepolia).requestWithdraw(msg.sender, amount);
        } else {
            _sendCrossChain(ActionType.Withdraw, msg.sender, amount);
        }
    }

    function _sendCrossChain(ActionType _action, address _wallet, uint256 _amount) internal returns (bytes32 messageId) {
        Client.EVM2AnyMessage memory msgToSend = _action == ActionType.Deposit
            ? _buildCCIPMessageForDeposit(_wallet, _amount)
            : _buildCCIPMessageForWithdraw(_wallet, _amount);

        IRouterClient router = IRouterClient(this.getRouter());

        uint256 fee = router.getFee(destinationChainSelector, msgToSend);
        if (fee > address(this).balance) {
            revert NotEnoughNativeFee(address(this).balance, fee);
        }

        if (_action == ActionType.Deposit) {
            usdc.safeApprove(address(router), _amount);
        }

        messageId = router.ccipSend{value: fee}(
            destinationChainSelector,
            msgToSend
        );

        return messageId;
    }

    function _buildCCIPMessageForDeposit(
        address wallet,
        uint256 amount
    ) private view returns (Client.EVM2AnyMessage memory) {
        Client.EVMTokenAmount[]
        memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(usdc),
            amount: amount
        });

        bytes memory data = abi.encode(uint8(ActionType.Deposit), wallet, amount);

        return
            Client.EVM2AnyMessage({
            receiver: abi.encode(perpetraCrossChainBridgeSepolia),
            data: data,
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: 200_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: address(0)
        });
    }

    function _buildCCIPMessageForWithdraw(
        address wallet,
        uint256 amount
    ) private view returns (Client.EVM2AnyMessage memory) {
        bytes memory data = abi.encode(uint8(ActionType.Withdraw), wallet, amount);

        return
            Client.EVM2AnyMessage({
            receiver: abi.encode(perpetraCrossChainBridgeSepolia),
            data: data,
            tokenAmounts: new Client.EVMTokenAmount[](0),
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: 200_000,
                    allowOutOfOrderExecution: true
                })
            ),
            feeToken: address(0)
        });
    }

    function _ccipReceive(
        Client.Any2EVMMessage memory any2EvmMessage
    )
    internal
    override
    {
        lastReceivedMessageId = any2EvmMessage.messageId; // fetch the messageId

        if (block.chainid != VAULT_CHAIN_ID) {
            return;
        }

        (uint8 actionUint, address wallet, uint256 amount) = abi.decode(
            any2EvmMessage.data,
            (uint8, address, uint256)
        );

        ActionType action = ActionType(actionUint);
        if (action == ActionType.Deposit) {
            ISafeVault(safeVaultSepolia).processDeposit(wallet, amount);
        } else {
            ISafeVault(safeVaultSepolia).requestWithdraw(wallet, amount);
        }

    }

    // --- Admin ---

    function setSafeVaultSepolia(address _vault) external onlyOwner {
        safeVaultSepolia = _vault;
    }

    function setPerpetraCrossChainBridgeSepolia(address _address) external onlyOwner {
        perpetraCrossChainBridgeSepolia = _address;
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
