import { defineConfig } from 'vite';

export default defineConfig({
  esbuild: { jsx: 'automatic' },
  css: { devSourcemap: false },
  build: { sourcemap: false },
  server: {
    host: '127.0.0.1',
    proxy: {
      '/bff': {
        target: 'http://127.0.0.1:8089',
        changeOrigin: false,
      },
      '/oauth2/authorization': {
        target: 'http://127.0.0.1:8089',
        changeOrigin: false,
      },
    },
  },
});
