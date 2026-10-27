# Без npm install и без компиляции: сборка на сервере — это только копирование файлов.
FROM node:24-alpine

ENV NODE_ENV=production \
    PORT=3000 \
    DATA_DIR=/data

WORKDIR /app
COPY package.json ./
COPY src ./src
COPY public ./public

RUN mkdir -p /data && chown node:node /data
USER node
VOLUME /data
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health >/dev/null || exit 1

# Ограничиваем кучу V8, чтобы процесс гарантированно оставался маленьким.
CMD ["node", "--disable-warning=ExperimentalWarning", "--max-old-space-size=96", "src/index.js"]
