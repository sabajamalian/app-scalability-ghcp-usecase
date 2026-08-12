import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    host: '0.0.0.0',
    port: 5173,
    // The browser talks to the Vite dev server, which forwards /api to the
    // backend container. This keeps the demo free of CORS configuration and
    // means the UI works whether you run the backend in Docker or locally.
    proxy: {
      '/api': {
        target: process.env.BACKEND_URL || 'http://backend:8080',
        changeOrigin: true,
      },
    },
  },
})
