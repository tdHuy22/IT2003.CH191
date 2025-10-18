import { createRouter, createWebHistory } from 'vue-router'
import IoTDashboard from '../views/IoTDashboard.vue'
import DataHistory from '../views/DataHistory.vue'

const routes = [
  { path: '/', name: 'IoTDashboard', component: IoTDashboard },
  { path: '/history', name: 'DataHistory', component: DataHistory },
]

const router = createRouter({
  history: createWebHistory(),
  routes,
})

export default router
