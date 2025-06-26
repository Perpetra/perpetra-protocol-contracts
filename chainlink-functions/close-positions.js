const backendBaseUrl = "https://perpetra-api.aftermiracle.com";
const rpcUrl         = "https://eth.llamarpc.com";

const apiHeaders = {
    "Content-Type": "application/json"
};

const http = (url, { method = "GET", data } = {}) =>
    Functions.makeHttpRequest({ url, method, headers: apiHeaders, data });

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

async function getOpenPositions() {
    const res = await http(`${backendBaseUrl}/positions/all-opened-positions`);
    return Array.isArray(res.data?.data) ? res.data.data : [];
}

async function shouldClose(position) {
    const payload = {
        direction:    position.type,
        entryPrice:   Number(position.entryPrice),
        currentPrice: await getBTCPrice(),
        pnl:          Number(position.pnl),
        size:         Number(position.size),
        leverage:     Number(position.leverage),
    };

    const res = await http(`${backendBaseUrl}/should-close`, {
        method: "POST",
        data:   payload,
    });

    const ok = res.data?.shouldClose;
    if (typeof ok !== "boolean") {
        throw new Error(`Invalid response: ${JSON.stringify(res.data)}`);
    }
    return ok;
}

async function closePosition(positionId, closePrice) {
    return http(
        `${backendBaseUrl}/positions/position/${positionId}/close`,
        { method: "POST", data: { closePrice } }
    );
}

try {
    const price     = await getBTCPrice();
    const positions = await getOpenPositions();
    const closedIds = [];

    await Promise.all(positions.map(async (pos) => {
        try {
            if (await shouldClose(pos)) {
                await closePosition(pos.id, price);
                closedIds.push(pos.id);
            }
        } catch (err) {
            console.warn(`Position ${pos.id} failed to close:`, err.message);
        }
    }));

    return Functions.encodeUint256(closedIds.length);
} catch (err) {
    throw new Error(`Function failed: ${err.message}`);
}