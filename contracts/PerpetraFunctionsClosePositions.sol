// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {FunctionsClient} from "@chainlink/contracts@1.4.0/src/v0.8/functions/v1_0_0/FunctionsClient.sol";
import {ConfirmedOwner} from "@chainlink/contracts@1.4.0/src/v0.8/shared/access/ConfirmedOwner.sol";
import {FunctionsRequest} from "@chainlink/contracts@1.4.0/src/v0.8/functions/v1_0_0/libraries/FunctionsRequest.sol";

/**
 * Request testnet LINK and ETH here: https://faucets.chain.link/
 * Find information on LINK Token Contracts and get the latest ETH and LINK faucets here: https://docs.chain.link/resources/link-token-contracts/
 */

/**
 * @title GettingStartedFunctionsConsumer
 * @notice This is an example contract to show how to make HTTP requests using Chainlink
 * @dev This contract uses hardcoded values and should not be used in production.
 */
contract PerpetraFunctionsClosePositions is FunctionsClient, ConfirmedOwner {
    using FunctionsRequest for FunctionsRequest.Request;

    // State variables to store the last request ID, response, and error
    bytes32 public s_lastRequestId;
    bytes public s_lastResponse;
    bytes public s_lastError;

    // Custom error type
    error UnexpectedRequestID(bytes32 requestId);

    // Event to log responses
    event Response(bytes32 indexed requestId, bytes response, bytes err);

    // Router address - Hardcoded for Sepolia
    // Check to get the router address for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    address router = 0xb83E47C2bC239B3bf370bc41e1459A34b41238D0;

    string source =
    "const backend=\"https://perpetra-api.aftermiracle.com\",rpc=\"https://eth.llamarpc.com\",headers={\"Content-Type\":\"application/json\"},http=(u,{method:m=\"GET\",data:d}={})=>Functions.makeHttpRequest({url:u,method:m,headers,data:d}),getBTC=async()=>{const r=await Functions.makeHttpRequest({url:rpc,method:\"POST\",headers,data:{jsonrpc:\"2.0\",method:\"eth_call\",params:[{to:\"0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c\",data:\"0x50d25bcd\"},\"latest\"],id:1}}),h=r?.data?.result;if(!h||h===\"0x\")throw new Error(\"No result from Chainlink feed\");const p=Number(BigInt(h))/1e8;if(!(p>0))throw new Error(\"Invalid price parsed\");return p},getPos=async()=>{const r=await http(`${backend}/positions/all-opened-positions`);return Array.isArray(r.data?.data)?r.data.data:[]},shouldCloseFn=async o=>{const r=await http(`${backend}/should-close`,{method:\"POST\",data:{direction:o.type,entryPrice:Number(o.entryPrice),currentPrice:await getBTC(),pnl:Number(o.pnl),size:Number(o.size),leverage:Number(o.leverage)}});if(typeof r.data?.shouldClose!==\"boolean\")throw new Error(`Invalid response: ${JSON.stringify(r.data)}`);return r.data.shouldClose},closePos=async(i,b)=>http(`${backend}/positions/position/${i}/close`,{method:\"POST\",data:{closePrice:b}});try{const p=await getBTC(),a=await getPos(),c=[];await Promise.all(a.map(async x=>{try{if(await shouldCloseFn(x)){await closePos(x.id,p);c.push(x.id)}}catch(_){}}));return Functions.encodeUint256(c.length)}catch(e){throw new Error(`Function failed: ${e.message}`)}";

    //Callback gas limit
    uint32 gasLimit = 300000;

    // donID - Hardcoded for Sepolia
    // Check to get the donID for your supported network https://docs.chain.link/chainlink-functions/supported-networks
    bytes32 donID =
    0x66756e2d657468657265756d2d7365706f6c69612d3100000000000000000000;

    /**
     * @notice Initializes the contract with the Chainlink router address and sets the contract owner
     */
    constructor() FunctionsClient(router) ConfirmedOwner(msg.sender) {}

    /**
     * @param subscriptionId The ID for the Chainlink subscription
     * @param args The arguments to pass to the HTTP request
     * @return requestId The ID of the request
     */
    function sendRequest(
        uint64 subscriptionId,
        string[] calldata args
    ) external onlyOwner returns (bytes32 requestId) {
        FunctionsRequest.Request memory req;
        req.initializeRequestForInlineJavaScript(source); // Initialize the request with JS code
        if (args.length > 0) req.setArgs(args); // Set the arguments for the request

        // Send the request and store the request ID
        s_lastRequestId = _sendRequest(
            req.encodeCBOR(),
            subscriptionId,
            gasLimit,
            donID
        );

        return s_lastRequestId;
    }

    /**
     * @notice Callback function for fulfilling a request
     * @param requestId The ID of the request to fulfill
     * @param response The HTTP response data
     * @param err Any errors from the Functions request
     */
    function fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (s_lastRequestId != requestId) {
            revert UnexpectedRequestID(requestId);
        }
        s_lastResponse = response;
        s_lastError = err;

        emit Response(requestId, s_lastResponse, s_lastError);
    }
}