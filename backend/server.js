const express = require("express");
const mqtt = require("mqtt");
const axios = require("axios");
const WebSocket = require("ws");
const fs = require("fs");
const path = require("path");
const cors = require("cors");
const { parse: csvParse } = require("csv-parse/sync");
const crypto = require("crypto");

const KEY = Buffer.from(process.env.AES_SHARED_KEY, "base64");
if (!KEY || KEY.length !== 32) {
  throw new Error("Invalid AES_SHARED_KEY");
}
const AAD = Buffer.from(process.env.AAD || "iot-lab-shared");

function decryptToNumber(b64) {
  const buf = Buffer.from(b64, "base64");
  if (buf.length < 12 + 16) throw new Error("Invalid payload length");
  const iv = buf.subarray(0, 12);
  const tag = buf.subarray(12, 28);
  const ciphertext = buf.subarray(28);
  const decipher = crypto.createDecipheriv("aes-256-gcm", KEY, iv);
  decipher.setAAD(AAD);
  decipher.setAuthTag(tag);
  const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
  // convert to number if possible
  const s = plain.toString("utf8");
  const n = Number(s);
  if (Number.isNaN(n)) throw new Error("Decrypted value is not a number: " + s);
  return n;
}

const app = express();
app.use(cors());
const host = "backend";
const serverPort = 3001;

const server = app.listen(serverPort, () =>
  console.log(`Backend on ${host}:${serverPort}`)
);
const wss = new WebSocket.Server({ server });
console.log(`WebSocket server running on ws://${host}:${serverPort}`);

app.get("/api/logs/:type", (req, res) => {
  const type = req.params.type;
  const date = req.query.date || new Date().toISOString().slice(0, 10);
  const filePath = path.join(__dirname, "logs", date, `${type}.log`);

  if (!fs.existsSync(filePath)) {
    console.log(`No log of ${type} found for ${date}`);
    return res.status(404).send(`No log found for ${date}`);
  }

  console.log(`Sending log of ${type} for ${date}`);
  res.download(filePath, `${type}-${date}.log`);
});

// ===== MQTT Config =====
const mqttOptions = {
  clientId: "backend-subscriber",
  ca: fs.readFileSync("/app/certs/express/ca_bundle.crt"),
  key: fs.readFileSync("/app/certs/express/express.key"),
  cert: fs.readFileSync("/app/certs/express/express.crt"),
  rejectUnauthorized: true,
  protocol: "mqtts",
  clean: true,
  connectTimeout: 30000,
  reconnectPeriod: 0,
  keepalive: 60,
};

let mqttClient = null;
let reconnectTimer = null;

// ====== Log sensor data to daily file ======
function logSensorData(type, message) {
  const today = new Date().toISOString().slice(0, 10); // YYYY-MM-DD
  console.log("Today is", today);
  const dir = path.join(__dirname, "logs", today);
  const filePath = path.join(dir, `${type}.log`);

  // Tạo thư mục nếu chưa có
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const line = `[${new Date().toISOString()}] ${message}\n`;
  fs.appendFile(filePath, line, (err) => {
    if (err) console.error("Log write error:", err);
  });
}

// ====== HAProxy Stats ======
async function checkHaproxyStats() {
  try {
    const res = await axios.get("http://admin:admin@haproxy:8404/stats;csv", {
      timeout: 4000,
    });

    const cleanCsv = res.data
      .split("\n")
      .map((line) => (line.startsWith("#") ? line.slice(1) : line))
      .filter((line) => line.trim() !== "")
      .join("\n");

    const records = csvParse(cleanCsv, {
      columns: true,
      skip_empty_lines: true,
      trim: true,
    });

    const brokers = records
      .filter((r) => r.pxname === "mqtt_tls_out" && r.svname !== "BACKEND")
      .map((r) => ({
        name: r.svname,
        status: r.status,
      }));

    console.log("✅ Brokers status:", brokers);

    broadcast({
      topic: "status",
      payload: brokers,
      timestamp: Date.now(),
    });
  } catch (e) {
    console.error("Stats fetch failed:", e.message);
    broadcast({
      topic: "status-error",
      payload: e.message,
      timestamp: Date.now(),
    });
  }
}

// ====== MQTT Connection ======
function scheduleReconnect() {
  if (reconnectTimer) return;
  console.log("⏳ Retrying MQTT connection in 1 seconds...");
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connectToMqtt();
  }, 1000);
}

function handleMqttDisconnect(reason) {
  console.warn(`Handling MQTT disconnect due to: ${reason}`);
  try {
    if (mqttClient && mqttClient.connected) {
      mqttClient.end(true);
      mqttClient = null;
    }
  } catch (error) {
    console.error("Error while handling MQTT disconnect:", error);
  }
  scheduleReconnect();
  broadcast({
    topic: "mqtt-disconnect",
    payload: reason,
    timestamp: Date.now(),
  });
}

function broadcast(msg) {
  wss.clients.forEach((c) => {
    if (c.readyState === WebSocket.OPEN) c.send(JSON.stringify(msg));
  });
}

function connectToMqtt() {
  console.log("🔌 Connecting to MQTT broker via HAProxy...");
  try {
    mqttClient = mqtt.connect("mqtts://haproxy:18884", mqttOptions);

    mqttClient.on("connect", () => {
      console.log("✅ Connected to HAProxy (MQTT TLS)");
      mqttClient.subscribe("sensor/+", (err) => {
        if (err) console.error("Subscription error:", err);
      });
      mqttClient.subscribe("+/sensor/+", (err) => {
        if (err) console.error("Subscription error:", err);
      });

      if (reconnectTimer) {
        clearTimeout(reconnectTimer);
        reconnectTimer = null;
      }
      checkHaproxyStats();
    });

    mqttClient.on("message", (topic, message) => {
      // const payload = message.toString();
      // console.log(`[MQTT] ${topic}: ${payload}`);

      // if (topic.includes("sensor/temp")) logSensorData("temp", payload);
      // else if (topic.includes("sensor/rain")) logSensorData("rain", payload);
      // else if (topic.includes("sensor/wind")) logSensorData("wind", payload);

      // broadcast({
      //   topic,
      //   payload,
      //   timestamp: Date.now(),
      // });

      try {
        // message is wrapper JSON { data: "<base64>" } or raw base64 text
        let payloadStr = message.toString();
        let b64;
        try {
          const obj = JSON.parse(payloadStr);
          if (obj && obj.data) b64 = obj.data;
          else throw new Error("no data field");
        } catch (e) {
          // not JSON, assume raw base64
          b64 = payloadStr.trim();
        }
        const num = decryptToNumber(b64);
        console.log("Received decrypted number from topic", topic, ":", num);

        if (topic.includes("sensor/temp")) logSensorData("temp", num);
        else if (topic.includes("sensor/rain")) logSensorData("rain", num);
        else if (topic.includes("sensor/wind")) logSensorData("wind", num);

        broadcast({
          topic,
          payload: num,
          timestamp: Date.now(),
        });
      } catch (err) {
        console.error("Failed to decrypt/process message:", err.message);
      }
    });

    mqttClient.on("error", (err) => {
      console.error("❌ MQTT error:", err.message);
      handleMqttDisconnect("error");
    });

    mqttClient.on("close", () => {
      console.warn("⚠️ MQTT connection closed");
      handleMqttDisconnect("close");
    });

    mqttClient.on("offline", () => {
      console.warn("📴 MQTT offline");
      handleMqttDisconnect("offline");
    });

    mqttClient.on("reconnect", () => {
      console.log("🔁 MQTT reconnecting...");
    });
  } catch (error) {
    console.error("Connection error:", error);
  }
}

connectToMqtt();

// ====== WebSocket Handling ======
wss.on("connection", (ws) => {
  console.log("New WebSocket client connected");
  ws.send(
    JSON.stringify({
      topic: "welcome",
      payload: "Welcome to the WebSocket server!",
      timestamp: Date.now(),
    })
  );

  checkHaproxyStats();

  ws.on("message", (message) => {
    console.log(`Received from client: ${message}`);
  });

  ws.on("close", () => {
    console.log("WebSocket client disconnected");
  });
});
