const backend = "https://perpetra-api.aftermiracle.com";
const rpc = "https://eth.llamarpc.com";

const headers = {
    "Content-Type": "application/json"
};

const http = (url, { method = "GET", data } = {}) =>
    Functions.makeHttpRequest({ url, method, headers, data });

// Get BTC price via Chainlink feed (mainnet)
async function getBTC() {
    const response = await Functions.makeHttpRequest({
        url: rpc,
        method: "POST",
        headers,
        data: {
            jsonrpc: "2.0",
            method: "eth_call",
            params: [
                {
                    to: "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
                    data: "0x50d25bcd" // latestAnswer()
                },
                "latest"
            ],
            id: 1
        }
    });

    const hex = response?.data?.result;
    if (!hex || hex === "0x") throw new Error("No result");

    const price = Number(BigInt(hex)) / 1e8;
    if (!(price > 0)) throw new Error("Invalid price");

    return price;
}

async function getOrders() {
    const res = await http(`${backend}/orders/all-opened-orders`);
    return Array.isArray(res.data?.data) ? res.data.data.slice(0, 3) : [];
}

async function shouldExec(order) {
    const res = await http(`${backend}/should-execute`, {
        method: "POST",
        data: {
            direction: order.type,
            amount: order.amount,
            leverage: order.leverage,
            volatility: 1.3
        }
    });

    const ok = res.data?.shouldExecute;
    if (typeof ok !== "boolean") throw new Error("Bad decision");

    return ok;
}

async function exec(orderId, entryPrice) {
    return http(`${backend}/orders/order/${orderId}/execute`, {
        method: "POST",
        data: { entryPrice }
    });
}

try {
    const [price, orders] = await Promise.all([
        getBTC(),
        getOrders()
    ]);

    let count = 0;

    await Promise.all(
        orders.map(async (order) => {
            try {
                if (await shouldExec(order)) {
                    await exec(order.id, price);
                    count++;
                }
            } catch (_) {
            }
        })
    );

    return Functions.encodeUint256(count);
} catch (e) {
    throw new Error(`Failed: ${e.message}`);
}