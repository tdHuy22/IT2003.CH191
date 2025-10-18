<template>
  <div class="history">
    <h1>Sensor Log Viewer</h1>

    <div class="controls">
      <div class="date-picker">
        <label for="logDate">📅 Date:</label>
        <input
          id="logDate"
          name="logDate"
          type="date"
          v-model="selectedDate"
          @change="loadData(selectedType)"
        />
      </div>

      <div class="buttons">
        <button
          v-for="t in types"
          :key="t"
          :class="{ active: selectedType === t }"
          @click="changeType(t)"
        >
          {{ t.toUpperCase() }}
        </button>
      </div>

      <button class="download" @click="downloadLog">
        ⬇️ Download log file
      </button>
    </div>

    <div v-if="loading" class="loading">⏳ Loading...</div>

    <div v-if="logText" class="log-box">
      <pre>{{ logText }}</pre>
    </div>

    <div v-else-if="!loading">
      <p>No log found for {{ selectedDate }}.</p>
    </div>
  </div>
</template>

<script setup>
import { ref } from "vue";

const types = ["temp", "rain", "wind"];
const selectedType = ref("temp");
const selectedDate = ref(new Date().toISOString().slice(0, 10));
const loading = ref(false);
const logText = ref("");

function changeType(t) {
  selectedType.value = t;
  loadData(t);
}

async function loadData(type) {
  loading.value = true;
  logText.value = "";

  try {
    const res = await fetch(
      `/api/logs/${type}?date=${selectedDate.value}`
    );
    if (!res.ok) throw new Error("No log found");
    logText.value = await res.text();
    console.log("Load success");
  } catch {
    logText.value = "";
  }
  loading.value = false;
}

function downloadLog() {
  const url = `/api/logs/${selectedType.value}?date=${selectedDate.value}`;
  const a = document.createElement("a");
  a.href = url;
  a.download = `${selectedType.value}-${selectedDate.value}.log`;
  a.click();
}

loadData(selectedType.value);
</script>

<style scoped>
.history {
  padding: 2rem;
  text-align: center;
  background: linear-gradient(180deg, #f5f7fa, #e4ebf1);
  min-height: 100vh;
}

h1 {
  font-size: 2.4rem;
  font-weight: 800;
  color: #1b5e20;
  margin-bottom: 2rem;
}

.controls {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1rem;
  margin-bottom: 1.5rem;
}

.date-picker {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

label {
  font-weight: 600;
  color: #333;
}

input[type="date"] {
  padding: 0.4rem 0.8rem;
  border: 1px solid #ccc;
  border-radius: 6px;
  font-size: 1rem;
}

.buttons {
  display: flex;
  gap: 0.5rem;
}

button {
  padding: 0.5rem 1rem;
  border: none;
  border-radius: 6px;
  color: white;
  background: #43a047;
  cursor: pointer;
  font-weight: 600;
}

button.active {
  background: #2e7d32;
}

button.download {
  background: #1e88e5;
}

.log-box {
  background: #fff;
  padding: 1rem;
  border-radius: 1rem;
  box-shadow: 0 4px 10px rgba(0, 0, 0, 0.1);
  width: 90%;
  max-width: 800px;
  margin: 1rem auto;
  text-align: left;
  overflow-x: auto; /* Thêm để có thanh cuộn ngang */
  overflow-y: auto;
  max-height: 60vh; /* Giới hạn chiều cao */
  white-space: pre; /* Giữ log 1 dòng nếu dài */
}

pre {
  font-family: "Courier New", monospace;
  font-size: 0.9rem;
  line-height: 1.3;
  color: #222;
  margin: 0;
}

.loading {
  color: #777;
}
</style>
