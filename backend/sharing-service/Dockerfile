# syntax=docker/dockerfile:1

# ---- Dependencies ----
FROM node:20-alpine AS dependencies
WORKDIR /app
COPY package*.json ./
# --legacy-peer-deps matches this service's existing local install
# requirement (see RUNNING_LOCALLY.md) — revisit if the underlying
# dependency conflict ever gets resolved upstream.
RUN npm ci --legacy-peer-deps

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
ENV SHARING_PORT=3004

RUN addgroup -S sentinel && adduser -S sentinel -G sentinel

COPY package*.json ./
RUN npm ci --omit=dev --legacy-peer-deps && npm cache clean --force
COPY --from=build /app/dist ./dist

USER sentinel
EXPOSE 3004

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD node -e "require('http').get('http://localhost:'+(process.env.SHARING_PORT||3004)+'/health',(r)=>process.exit(r.statusCode===200?0:1)).on('error',()=>process.exit(1))"

CMD ["node", "dist/main.js"]
