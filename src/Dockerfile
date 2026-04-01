# ============================================================
# Stage 1: Dependency Installation
# Installs ALL deps (including dev) needed for building
# ============================================================
ARG NODE_VERSION=16
ARG IMAGE_BASE=${NODE_VERSION}-alpine

FROM node:${IMAGE_BASE} AS deps

WORKDIR /app

# Copy lockfiles first for better layer caching
COPY package*.json ./

# Use `npm ci` for deterministic, clean installs
# --ignore-scripts prevents malicious postinstall hooks
RUN npm ci --ignore-scripts


# ============================================================
# Stage 2: Builder
# Compiles/transpiles source if needed (e.g. TypeScript, Vite)
# ============================================================
FROM node:${IMAGE_BASE} AS builder

WORKDIR /app

# Bring in node_modules from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy full source
COPY . .

# If you have a build step (tsc, vite build, webpack, etc.), run it here:
# RUN npm run build

# Prune down to only production dependencies
RUN npm prune --production


# ============================================================
# Stage 3: Production Runtime
# Minimal, hardened image with no dev tooling
# ============================================================
FROM node:${IMAGE_BASE} AS production

LABEL Name="Node.js Demo App" \
      Version="4.8.5" \
      org.opencontainers.image.source="https://github.com/benc-uk/nodejs-demoapp" \
      org.opencontainers.image.description="Production Node.js Demo App" \
      org.opencontainers.image.licenses="MIT"

# Install dumb-init: proper PID 1 signal handling & zombie reaping
RUN apk add --no-cache dumb-init

# Set production environment
ENV NODE_ENV=production \
    PORT=3000 \
    # Prevent npm update checks at runtime
    NO_UPDATE_NOTIFIER=1

WORKDIR /app

# Copy only what's needed to run the app from the builder stage
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --chown=node:node . .

# Drop root privileges — run as the built-in 'node' user
USER node

# Expose the app port
EXPOSE 3000

# Healthcheck so orchestrators (K8s, ECS, Swarm) know when app is ready
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
  CMD wget -qO- http://localhost:3000/health || exit 1

# dumb-init as PID 1 ensures SIGTERM is forwarded to Node correctly
ENTRYPOINT ["dumb-init", "--"]
CMD ["node", "src/app.js"]