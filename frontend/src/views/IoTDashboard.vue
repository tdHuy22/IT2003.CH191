<template>
  <div id="app">
    <h1>IoT Sensor Dashboard</h1>

    <div class="dashboard-container">
      <ChartBox title="Temperature (°C)" color="rgb(255, 99, 132)" :data="dataTemp" :options="chartOptionsTemp" />
      <ChartBox title="Rainfall (mm/h)" color="rgb(54, 162, 235)" :data="dataRain" :options="chartOptionsRain" />
      <ChartBox title="Wind Speed (km/h)" color="rgb(75, 192, 192)" :data="dataWind" :options="chartOptionsWind" />
    </div>

    <BrokerStatus :brokers="brokers" />
  </div>
</template>

<!-- <script setup>
import { ref, onMounted } from "vue";
import ChartBox from "../assets/components/ChartBox.vue";
import BrokerStatus from "../assets/components/BrokerStatus.vue";

const today = new Date().toISOString().slice('T')[0];
const cacheData = ref([]);
const cacheKey = `iot-dashboard-${today}`;

const chartOptionsTemp = { title: "Temperature", min: 0, max: 50, unit: "°C" };
const chartOptionsRain = { title: "Rainfall", min: 0, max: 20, unit: "mm/h" };
const chartOptionsWind = { title: "Wind Speed", min: 0, max: 80, unit: "km/h" };

const logText = ref("");
const dataTemp = ref([]);
const dataRain = ref([]);
const dataWind = ref([]);
const brokers = ref([
  { name: "broker1", status: "DOWN" },
  { name: "broker2", status: "DOWN" },
  { name: "broker3", status: "DOWN" },
]);

function loadCache() {
  const cached = localStorage.getItem(cacheKey);
  if (cached) {
    try {
      const parsed = JSON.parse(cached);
      if (Array.isArray(parsed)) {
        cacheData.value = parsed;
        console.log("♻️ Loaded cached data:", parsed.length, "entries");
        // Distribute cached data into respective datasets
        parsed.forEach(entry => {
          if (entry.topic.includes("temp")) dataTemp.value.push({ x: entry.timestamp, y: parseFloat(entry.payload) });
          if (entry.topic.includes("rain")) dataRain.value.push({ x: entry.timestamp, y: parseFloat(entry.payload) });
          if (entry.topic.includes("wind")) dataWind.value.push({ x: entry.timestamp, y: parseFloat(entry.payload) });
        });
      }
    } catch (e) {
      console.error("❌ Failed to parse cached data:", e);
    }
  }
}

function saveCache(newEntry) {
  if (!newEntry || !newEntry.topic || !newEntry.payload) return;

  const today = new Date().toISOString().split("T")[0]; // YYYY-MM-DD
  const cacheKey = `iot_data_${today}`;

  try {
    cacheData.value.push(newEntry);

    if (cacheData.value.length > 5000) {
      cacheData.value.splice(0, cacheData.value.length - 5000);
    }

    localStorage.setItem(cacheKey, JSON.stringify(cacheData.value));

    console.log(
      `💾 Cached ${cacheData.value.length} entries (latest topic: ${newEntry.topic})`
    );
  } catch (e) {
    console.error("❌ Failed to save cache:", e);
  }
}


function websocket(){
  const ws = new WebSocket("ws://127.0.0.1:3001");

  ws.onopen = () => console.log("✅ Connected to backend WebSocket");
  ws.onclose = () => console.log("❌ Disconnected from backend WebSocket");
  ws.onerror = (err) => console.error("⚠️ WebSocket error:", err);
  ws.onmessage = (msg) => {
    const { topic, payload, timestamp } = JSON.parse(msg.data);
    console.log("📩", topic, payload);
    const value = parseFloat(payload);
    const entry = { topic, payload, timestamp };

    if (topic.includes("temp")) {
      dataTemp.value.push({ x: timestamp, y: value });
      saveCache(entry);
    }
    if (topic.includes("rain")) {
      dataRain.value.push({ x: timestamp, y: value });
      saveCache(entry);
    }
    if (topic.includes("wind")) {
      dataWind.value.push({ x: timestamp, y: value });
      saveCache(entry);
    }
    if (topic === "status") {
      console.log("🔄 Broker status update:", payload)
      brokers.value = payload;
    };
    if (topic === "status-error") console.error("❌", payload);
    if (topic === "welcome") console.log("👋", payload);
    if (topic === "mqtt-disconnect") console.warn("⚠️", payload);
  };
}

async function fetchLog() {
  try {
    console.log("🔍 Fetching logs from backend...");
    const today = new Date().toISOString().split("T")[0];
    const cacheKey = `iot_data_${today}`;
    const types = ["temp", "rain", "wind"];
    const allEntries = [];

    for (const type of types) {
      const res = await fetch(`http://127.0.0.1:3001/api/logs/${type}?date=${today}`);
      if (!res.ok) {
        console.warn(`⚠️ No log found for ${type}`);
        continue;
      }

      const text = await res.text();
      if (!text.trim()) {
        console.log(`❌ Empty log for ${type}`);
        continue;
      }

      console.log(`📥 Loaded log for ${type}, ${text.split("\n").length} lines`);

      // 🧩 Parse từng dòng log
      const lines = text.trim().split("\n");
      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          // Nếu log backend lưu JSON: {"topic":"sensor/temp","payload":"34.5","timestamp":"..."}
          let entry = null;
          if (line.startsWith("{")) {
            entry = JSON.parse(line);
          } else {
            // Nếu log lưu kiểu CSV: timestamp,payload
            const [timestamp, payload] = line.split(",");
            entry = {
              topic: `sensor/${type}`,
              payload: payload?.trim(),
              timestamp: timestamp?.trim()
            };
          }

          // Thêm vào bộ nhớ tổng
          if (entry?.topic && entry?.payload) {
            allEntries.push(entry);
          }
        } catch (e) {
          console.warn(`⚠️ Skipped invalid log line in ${type}:`, line);
          console.error(e);
        }
      }
    }

    // 💾 Lưu cache tổng hợp
    if (allEntries.length > 0) {
      cacheData.value = allEntries;
      localStorage.setItem(cacheKey, JSON.stringify(allEntries));
      console.log(`💾 Saved ${allEntries.length} log entries to cache`);

      // 🚀 Đổ dữ liệu lên các biểu đồ
      dataTemp.value = allEntries
        .filter((e) => e.topic.includes("temp"))
        .map((e) => ({ x: e.timestamp, y: parseFloat(e.payload) }));

      dataRain.value = allEntries
        .filter((e) => e.topic.includes("rain"))
        .map((e) => ({ x: e.timestamp, y: parseFloat(e.payload) }));

      dataWind.value = allEntries
        .filter((e) => e.topic.includes("wind"))
        .map((e) => ({ x: e.timestamp, y: parseFloat(e.payload) }));
    } else {
      console.warn("⚠️ No valid log data fetched from backend.");
    }

  } catch (err) {
    console.error("❌ Failed to fetch logs:", err);
  }
}


onMounted(() => {
  loadCache();
  fetchLog();
  websocket();
});

</script> -->

<script setup>
import { ref, onMounted, onBeforeUnmount } from "vue";
import ChartBox from "../assets/components/ChartBox.vue";
import BrokerStatus from "../assets/components/BrokerStatus.vue";

const chartOptionsTemp = { title: "Temperature", min: 0, max: 50, unit: "°C" };
const chartOptionsRain = { title: "Rainfall", min: 0, max: 20, unit: "mm/h" };
const chartOptionsWind = { title: "Wind Speed", min: 0, max: 80, unit: "km/h" };

const dataTemp = ref([]);
const dataRain = ref([]);
const dataWind = ref([]);
const brokers = ref([
  { name: "broker1", status: "DOWN" },
  { name: "broker2", status: "DOWN" },
  { name: "broker3", status: "DOWN" },
]);
const cacheData = ref([]);

const today = new Date().toISOString().split("T")[0];
const cacheKey = `iot_data_${today}`;
let ws = null;
let batchTimer = null;
let cacheDirty = false;

// 🧠 Load cache từ localStorage
function loadCache() {
  const cached = localStorage.getItem(cacheKey);
  if (cached) {
    try {
      const parsed = JSON.parse(cached);
      if (Array.isArray(parsed)) {
        cacheData.value = parsed;
        console.log("♻️ Loaded cached data:", parsed.length, "entries");
        parsed.forEach((entry) => {
          if (entry.topic.includes("temp"))
            dataTemp.value.push({ x: entry.timestamp, y: parseFloat(entry.payload) });
          if (entry.topic.includes("rain"))
            dataRain.value.push({ x: entry.timestamp, y: parseFloat(entry.payload) });
          if (entry.topic.includes("wind"))
            dataWind.value.push({ x: entry.timestamp, y: parseFloat(entry.payload) });
        });
      }
    } catch (e) {
      console.error("❌ Failed to parse cached data:", e);
    }
  } else {
    console.log("♻️ No cached data found");
  }
}

// 💾 Batch save cache mỗi 10s
function startBatchSaver() {
  if (batchTimer) return;

  batchTimer = setInterval(() => {
    if (cacheDirty) {
      try {
        if (cacheData.value.length > 0) {
          localStorage.setItem(cacheKey, JSON.stringify(cacheData.value));
          console.log("💾 [AutoSave] Batch saved:", cacheData.value.length, "entries");
        }
        cacheDirty = false;
      } catch (e) {
        console.error("❌ Failed to batch save cache:", e);
      }
    }
  }, 10000);
}

// 🧩 Lưu dữ liệu mới vào cache
function saveCache(newEntry) {
  if (!newEntry || !newEntry.topic || !newEntry.payload) return;

  cacheData.value.push(newEntry);
  if (cacheData.value.length > 5000)
    cacheData.value.splice(0, cacheData.value.length - 5000);

  cacheDirty = true;
}

// 🧾 Fetch log từ backend (nếu cache trống)
async function fetchLog() {
  try {
    console.log("🔍 Fetching logs from backend...");
    const types = ["temp", "rain", "wind"];
    const allEntries = [];

    for (const type of types) {
      const res = await fetch(`/api/logs/${type}?date=${today}`);
      if (!res.ok) continue;

      const text = await res.text();
      if (!text.trim()) continue;

      console.log(`📥 Loaded log for ${type}, ${text.split("\n").length} lines`);

      const lines = text.trim().split("\n");

      for (const line of lines) {
        if (!line.trim()) continue;
        let entry;
        try {
          if (line.startsWith("{")) {
            // JSON format
            entry = JSON.parse(line);
          } else {
            // 🕒 Match dạng [timestamp] payload
            const match = line.match(/^\[(.+?)\]\s+(.+)$/);
            if (match) {
              const timestamp = match[1].trim();
              const payload = match[2].trim();
              entry = {
                topic: `sensor/${type}`,
                payload,
                timestamp
              };
            }
          }

          if (entry?.topic && entry?.payload) allEntries.push(entry);
        } catch (e) {
          console.warn(`⚠️ Skipped invalid log line (${type}):`, line);
          console.error(e);
        }
      }
    }

    if (allEntries.length > 0) {
      cacheData.value = allEntries;
      localStorage.setItem(cacheKey, JSON.stringify(allEntries));
      console.log(`💾 Saved ${allEntries.length} log entries to cache`);

      dataTemp.value = allEntries
        .filter((e) => e.topic.includes("temp"))
        .map((e) => ({ x: e.timestamp, y: parseFloat(e.payload) }));

      dataRain.value = allEntries
        .filter((e) => e.topic.includes("rain"))
        .map((e) => ({ x: e.timestamp, y: parseFloat(e.payload) }));

      dataWind.value = allEntries
        .filter((e) => e.topic.includes("wind"))
        .map((e) => ({ x: e.timestamp, y: parseFloat(e.payload) }));
    }
  } catch (err) {
    console.error("❌ Failed to fetch logs:", err);
  }
}

// 🔌 WebSocket kết nối realtime
function websocket() {
  ws = new WebSocket("/ws/");


  ws.onopen = () => console.log("✅ Connected to backend WebSocket");
  ws.onclose = () => console.log("❌ Disconnected from backend WebSocket");
  ws.onerror = (err) => console.error("⚠️ WebSocket error:", err);

  ws.onmessage = (msg) => {
    try {
      const { topic, payload, timestamp } = JSON.parse(msg.data);
      if (!topic || !payload) return;

      const value = parseFloat(payload);
      const entry = { topic, payload, timestamp };

      if (topic.includes("temp")) dataTemp.value.push({ x: timestamp, y: value });
      if (topic.includes("rain")) dataRain.value.push({ x: timestamp, y: value });
      if (topic.includes("wind")) dataWind.value.push({ x: timestamp, y: value });

      if (topic.includes("sensor")) saveCache(entry);

      if (topic === "status") brokers.value = payload;
      if (topic === "status-error") console.error("❌", payload);
      if (topic === "welcome") console.log("👋", payload);
      if (topic === "mqtt-disconnect") console.warn("⚠️", payload);
    } catch (err) {
      console.error("❌ Failed to parse WebSocket message:", err, msg.data);
    }
  };
}

function clearAllOnExit() {
  console.log("🧹 Clearing cache and closing connections...");

  try {
    // localStorage.removeItem(cacheKey);
    localStorage.clear();
    console.log("🗑️ Cache cleared:", cacheKey);

    cacheData.value = [];
    dataTemp.value = [];
    dataRain.value = [];
    dataWind.value = [];

    // Đóng WebSocket
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.close(1000, "User closed tab");
      console.log("🔌 WebSocket closed cleanly");
    } else {
      console.log("🔌 WebSocket not connected");
    }

    // Clear interval
    if (batchTimer) {`1`
      clearInterval(batchTimer);
      batchTimer = null;
      console.log("🕒 Batch saver stopped");
    }
  } catch (e) {
    console.error("⚠️ Cleanup error:", e);
  }
}

onMounted(async () => {
  loadCache();
  if (cacheData.value.length === 0) {
    await fetchLog();
  }
  websocket();
  startBatchSaver();
  window.addEventListener("beforeunload", clearAllOnExit);
});

onBeforeUnmount(() => {
  clearAllOnExit();
  window.removeEventListener("beforeunload", clearAllOnExit);
});
</script>

<style scoped>
@import "../assets/main.css";
</style>
