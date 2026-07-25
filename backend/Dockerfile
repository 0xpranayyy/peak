# Peak trading API — build from the backend/ directory.
# Example: docker build -t peak-api .
FROM node:22-alpine
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY *.mjs ./

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

# Session store: mount Railway volume at /data and set PEAK_SESSION_STORE=/data (Dockerfile VOLUME unsupported on Railway).

CMD ["node", "server.mjs"]
