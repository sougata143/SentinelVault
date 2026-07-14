# syntax=docker/dockerfile:1

# ---- Dependencies ----
FROM node:20-alpine AS dependencies
WORKDIR /app
COPY package*.json ./
RUN npm ci

# ---- Build ----
FROM node:20-alpine AS build
WORKDIR /app
COPY package*.json ./
COPY --from=dependencies /app/node_modules ./node_modules
COPY . .
RUN npm run build

# ---- Production ----
FROM node:20-alpine AS production
WORKDIR /app
ENV NODE_ENV=production
ENV AUTH_PORT=3001

RUN addgroup -S sentinel && adduser -S sentinel -G sentinel

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist

USER sentinel
EXPOSE 3001

# Requires a real GET /health endpoint returning 200 — see AGENTS.md/skill
# notes on adding one if not yet implemented. Uses Node's own http module
# so no extra package (curl, wget) needs to be installed in the image.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:'+(process.env.AUTH_PORT||3001)+'/health',(r)=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "dist/main.js"]
