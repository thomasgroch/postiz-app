# Stage 1: Dependencies
FROM node:20-alpine AS dependencies

# Install system dependencies
RUN apk add --no-cache g++ make python3 git ffmpeg sqlite openssl curl postgresql-client

# Install pnpm
RUN corepack enable && corepack prepare pnpm@10.6.1 --activate

# Set working directory
WORKDIR /app

# Copy package.json files to leverage Docker cache
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./

# Copy all package.json files to leverage Docker cache
COPY apps/**/package.json ./apps/
COPY libraries/**/package.json ./libraries/

# Install dependencies, allowing lockfile updates if needed
RUN pnpm install --no-frozen-lockfile

# Stage 2: Build
FROM node:20-alpine AS builder

# Install system dependencies for build phase
RUN apk add --no-cache g++ make python3 git

# Install pnpm
RUN corepack enable && corepack prepare pnpm@10.6.1 --activate

WORKDIR /app

# Copy from dependencies stage
COPY --from=dependencies /app/node_modules ./node_modules
COPY --from=dependencies /app/apps ./apps
COPY --from=dependencies /app/libraries ./libraries

# Copy source files
COPY . .

# Generate Prisma client
RUN pnpm prisma-generate

# Build all applications
RUN pnpm run build

# Stage 3: Production
FROM node:20-alpine AS runner

# Install production system dependencies
RUN apk add --no-cache ffmpeg sqlite postgresql-client openssl curl bash supervisor caddy

# Install pnpm globally
RUN corepack enable && corepack prepare pnpm@10.6.1 --activate

# Set NODE_ENV to production
ENV NODE_ENV=production

WORKDIR /app

# Copy necessary files from builder stage
COPY --from=builder /app/package.json /app/pnpm-lock.yaml /app/pnpm-workspace.yaml ./

# Copy built applications
COPY --from=builder /app/apps/backend/dist ./apps/backend/dist
COPY --from=builder /app/apps/frontend/dist ./apps/frontend/dist
COPY --from=builder /app/apps/workers/dist ./apps/workers/dist
COPY --from=builder /app/apps/cron/dist ./apps/cron/dist
COPY --from=builder /app/libraries/nestjs-libraries/dist ./libraries/nestjs-libraries/dist
COPY --from=builder /app/node_modules ./node_modules

# Copy prisma schema and migrations
COPY --from=builder /app/libraries/nestjs-libraries/src/database/prisma/schema.prisma ./libraries/nestjs-libraries/src/database/prisma/

# Copy Docker configuration files
COPY var/docker/supervisord.conf /etc/supervisord.conf
COPY var/docker/Caddyfile ./Caddyfile
COPY var/docker/entrypoint.sh ./entrypoint.sh
COPY var/docker/supervisord/*.conf /etc/supervisor.d/

# Make the entrypoint script executable
RUN chmod +x /app/entrypoint.sh

# Create necessary directories with proper permissions
RUN mkdir -p /uploads /config && \
    chown -R node:node /app /uploads /config

# Expose necessary ports
# Backend
EXPOSE 3000
# Frontend
EXPOSE 3001
# Caddy
EXPOSE 4200

# Set up volumes for persistent data
VOLUME ["/uploads", "/config"]

# Use the existing entrypoint script
ENTRYPOINT ["/app/entrypoint.sh"]

