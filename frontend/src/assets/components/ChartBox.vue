<template>
  <div class="chart-container">
    <h2>{{ title }}</h2>
    <Line :data="chartData" :options="options" />
  </div>
</template>

<script setup>
import { computed } from "vue";
import { Line } from "vue-chartjs";
import {
  Chart as ChartJS,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  Tooltip,
  Legend,
  TimeScale,
} from "chart.js";
import "chartjs-adapter-date-fns";

ChartJS.register(CategoryScale, LinearScale, PointElement, LineElement, Title, Tooltip, Legend, TimeScale);

const props = defineProps({
  title: String,
  color: String,
  data: Array,
  options: Object,
});

const chartData = computed(() => ({
  datasets: [
    {
      label: props.title,
      data: props.data.slice(-20),
      borderColor: props.color,
      borderWidth: 2,
      tension: 0.25,
      pointRadius: 2,
    },
  ],
}));

const options = {
  responsive: true,
  maintainAspectRatio: false,
  scales: {
    x: {
      type: "time",
      time: { unit: "second", tooltipFormat: "HH:mm:ss" },
      title: { display: true, text: "Time" },
    },
    y: {
      title: { display: true, text: props.options.unit || "" },
      suggestedMin: props.options.min || 0,
      suggestedMax: props.options.max || 100,
    },
  },
  plugins: {
    legend: { display: false },
    title: { display: false },
    tooltip: {
      callbacks: {
        label: (ctx) => `${ctx.dataset.label}: ${ctx.parsed.y.toFixed(2)} ${props.unit || ""}`
      }
    }
  }
};

</script>
