<template>
  <div class="broker-status">
    <div v-for="(b, i) in brokers" :key="i" class="broker-item">
      <span :class="['broker-dot', b.status]"></span>
      <span class="label">{{ b.name }}</span>
    </div>
  </div>
</template>

<script setup>
defineProps({ brokers: Array });
</script>
