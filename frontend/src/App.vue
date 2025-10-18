<template>
  <div id="app">
    <nav class="navbar">
      <router-link to="/" class="nav-link">📡 Realtime</router-link>
      <router-link to="/history" class="nav-link">🕒 History</router-link>
    </nav>
    <router-view />
  </div>
</template>

<style scoped>
.navbar {
  background: #1b5e20;
  display: flex;
  gap: 1.5rem;
  padding: 1rem 2rem;
  justify-content: center;
}
.nav-link {
  color: #fff;
  font-weight: 600;
  text-decoration: none;
}
.nav-link.router-link-exact-active {
  text-decoration: underline;
}
</style>
