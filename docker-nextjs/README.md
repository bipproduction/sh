# Docker Nextjs

Dockerfile

```Dockerfile
# Base image
FROM oven/bun:debian AS base
WORKDIR /app

# Step 1: install dependencies
FROM base AS deps
COPY bun.lock package.json ./
RUN --mount=type=cache,target=/root/.bun bun install --frozen-lockfile

# Step 2: build project
FROM base AS build
COPY --from=deps /app/node_modules ./node_modules
COPY . ./
RUN bun run build

# Step 3: production image
FROM base AS release
WORKDIR /app
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/public ./public
COPY --from=build /app/.next/static ./public/.next/static

USER bun
EXPOSE 3000
ENTRYPOINT ["bun","--bun", "run", "server.js"]

```

reset.sh

```sh
docker compose down
docker rmi makuro-studio -f
docker image prune -f
docker volume prune -f
docker network prune -f
# docker buildx prune -f 
docker builder prune --all --force 
docker system prune -a --force
docker compose up --build -d
```

docker-compose.yml

```yml
services:
  makuro-studio:
    build:
      context: .
    image: makuro-studio:latest
    container_name: makuro-studio
    ports:
      - "3000:3000"
    networks:
      - makuro-network
    volumes:
      - ./makuro-studio-app:/usr/src/app
    restart: unless-stopped

networks:
  makuro-network:
    external: true

```

.dockerignore

```.dockerignore
# Node.js dependencies
node_modules/

# Next.js build output
.next/

# Build outputs
dist/
build/
out/

# Version control
.git/
.gitignore

# IDE/editor files
.idea/
.vscode/
*.swp
*.swo

# Temporary and cache files
tmp/
temp/
*.tmp
*.log

# Environment and secrets
.env*
*.env
*.pem
*.key
*.crt

# Local and development config
.local/
local/
config.local.*
*.local.yml

# Test and debug
coverage/
*.test.js
*.test.ts
test/
tests/
debug/

# Documentation
README*
*.md
docs/

# Docker files (do not include Dockerfile or docker-compose for build context)
Dockerfile*
docker-compose*

# Project-specific: asset and source artifacts
.assets/
.source/

# Large binaries or artifacts
copas

# Ignore empty directories (optional, handled by Docker by default)
# **/.empty

# Exclude lock files from ignore (explicitly allow)
!*.lock

# Exclude .mvnw, .gradlew, .mvn, .gradle (not present, but for clarity)
# !.mvnw
# !.gradlew
# !.mvn/
# !.gradle/

```
