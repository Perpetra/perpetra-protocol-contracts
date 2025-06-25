const backendBaseUrl = "https://perpetra-api.aftermiracle.com";
const rpcUrl         = "https://eth.llamarpc.com";

const apiHeaders = {
    "Content-Type": "application/json"
};

const http = (url, { method = "GET", data } = {}) =>
    Functions.makeHttpRequest({ url, method, headers: apiHeaders, data });

// Fetch latest BTC/USD from Chainlink on Mainnet
async function getBTCPrice() {
    const callData = "0x50d25bcd"; // latestAnswer()
    const body = {
        jsonrpc: "2.0",
        method:  "eth_call",
        params: [{
            to:   "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
            data: callData,
        }, "latest"],
        id: 1,
    };

    const res = await Functions.makeHttpRequest({
        url:    rpcUrl,
        method: "POST",
        headers:{ "Content-Type": "application/json" },
        data:   body,
    });

    const hex = res?.data?.result;
    if (!hex || hex === "0x") throw new Error("No result from Chainlink feed");

    const price = Number(BigInt(hex)) / 1e8;
    if (!(price > 0)) throw new Error("Invalid BTC price parsed");
    return price;
}

// Get all open orders
async function getOpenOrders() {
    const res = await http(`${backendBaseUrl}/orders/all-opened-orders`);
    return Array.isArray(res.data?.data) ? res.data.data : [];
}

// Ask “Eliza” whether to execute
async function shouldExecute(order) {
    const payload = {
        direction:  order.type,
        amount:     order.amount,
        leverage:   order.leverage,
        volatility: 1.3,
    };
    const res = await http(`${backendBaseUrl}/should-execute`, {
        method: "POST",
        data: payload,
    });
    const ok = res.data?.shouldExecute;
    if (typeof ok !== "boolean") {
        throw new Error(`Invalid response: ${JSON.stringify(res.data)}`);
    }
    return ok;
}

// Execute a single order
async function executeOrder(orderId, entryPrice) {
    return http(
        `${backendBaseUrl}/orders/order/${orderId}/execute`,
        { method: "POST", data: { entryPrice } }
    );
}

// Main entrypoint for Chainlink Functions
try {
    // Fetch price + orders in parallel
    const [price, orders] = await Promise.all([
        getBTCPrice(),
        getOpenOrders(),
    ]);

    const executedIds = [];

    // Process all orders concurrently
    await Promise.all(orders.map(async (order) => {
        try {
            if (await shouldExecute(order)) {
                await executeOrder(order.id, price);
                executedIds.push(order.id);
            }
        } catch (err) {
            console.warn(`Order ${order.id} failed:`, err.message);
        }
    }));

    return Functions.encodeString(JSON.stringify(executedIds));
} catch (err) {
    throw new Error(`Function failed: ${err.message}`);
}