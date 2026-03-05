#!/bin/bash
# Detects the app architecture of a given repo directory
# Usage: ./detect_architecture.sh <repo_path>
# Outputs JSON with detection results

set -euo pipefail

REPO_PATH="${1:-.}"

if [ ! -d "$REPO_PATH" ]; then
    echo '{"error": "Directory not found: '"$REPO_PATH"'"}'
    exit 1
fi

cd "$REPO_PATH"

# Initialize detection flags
HAS_NEXTJS=false
HAS_SEPARATE_BACKEND=false
HAS_DOCKERFILE=false
HAS_RAILWAY_TOML=false
HAS_PRISMA=false
HAS_DRIZZLE=false
HAS_REDIS_DEPS=false
HAS_MONOREPO=false
FRAMEWORK=""
BACKEND_TYPE=""
DB_TYPE=""

# Check for monorepo
if [ -f "turbo.json" ] || [ -f "nx.json" ] || [ -f "pnpm-workspace.yaml" ] || [ -f "lerna.json" ]; then
    HAS_MONOREPO=true
fi

# Check for Next.js
if ls next.config.* 2>/dev/null | head -1 > /dev/null; then
    HAS_NEXTJS=true
    FRAMEWORK="nextjs"
elif [ -f "package.json" ] && jq -e '.dependencies.next // .devDependencies.next' package.json > /dev/null 2>&1; then
    HAS_NEXTJS=true
    FRAMEWORK="nextjs"
fi

# Check for other frontend frameworks if not Next.js
if [ "$HAS_NEXTJS" = false ] && [ -f "package.json" ]; then
    if jq -e '.dependencies.react // .devDependencies.react' package.json > /dev/null 2>&1; then
        FRAMEWORK="react"
    elif jq -e '.dependencies.vue // .devDependencies.vue' package.json > /dev/null 2>&1; then
        FRAMEWORK="vue"
    elif jq -e '.dependencies.svelte // .devDependencies.svelte' package.json > /dev/null 2>&1; then
        FRAMEWORK="svelte"
    fi
fi

# Check for Dockerfile
if [ -f "Dockerfile" ] || [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
    HAS_DOCKERFILE=true
fi

# Check for railway.toml
if [ -f "railway.toml" ]; then
    HAS_RAILWAY_TOML=true
fi

# Check for separate backend
if [ -d "backend" ] || [ -d "server" ] || [ -d "api" ]; then
    HAS_SEPARATE_BACKEND=true
fi

# Check for Python backend
if [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "Pipfile" ]; then
    HAS_SEPARATE_BACKEND=true
    BACKEND_TYPE="python"
fi

# Check for Go backend
if [ -f "go.mod" ]; then
    HAS_SEPARATE_BACKEND=true
    BACKEND_TYPE="go"
fi

# Check for Rust backend
if [ -f "Cargo.toml" ]; then
    HAS_SEPARATE_BACKEND=true
    BACKEND_TYPE="rust"
fi

# Check for Express/Fastify/Hono (non-Next.js Node backend)
if [ -f "package.json" ] && [ "$HAS_NEXTJS" = false ]; then
    if jq -e '.dependencies.express // .dependencies.fastify // .dependencies.hono // .dependencies.koa' package.json > /dev/null 2>&1; then
        HAS_SEPARATE_BACKEND=true
        BACKEND_TYPE="node"
    fi
fi

# Check for Prisma
if [ -d "prisma" ] || ([ -f "package.json" ] && jq -e '.dependencies["@prisma/client"] // .devDependencies["@prisma/client"]' package.json > /dev/null 2>&1); then
    HAS_PRISMA=true
    DB_TYPE="postgresql"
fi

# Check for Drizzle
if ls drizzle.config.* 2>/dev/null | head -1 > /dev/null; then
    HAS_DRIZZLE=true
    DB_TYPE="postgresql"
elif [ -f "package.json" ] && jq -e '.dependencies["drizzle-orm"] // .devDependencies["drizzle-orm"]' package.json > /dev/null 2>&1; then
    HAS_DRIZZLE=true
    DB_TYPE="postgresql"
fi

# Check for MongoDB (unsupported but detectable)
if [ -f "package.json" ] && jq -e '.dependencies.mongoose // .dependencies.mongodb' package.json > /dev/null 2>&1; then
    DB_TYPE="mongodb"
fi

# Check for Redis dependencies
if [ -f "package.json" ] && jq -e '.dependencies.ioredis // .dependencies.redis // .dependencies.bull // .dependencies.bullmq // .dependencies["@upstash/redis"]' package.json > /dev/null 2>&1; then
    HAS_REDIS_DEPS=true
fi

# Check .env.example for hints
ENV_HINTS=()
if [ -f ".env.example" ] || [ -f ".env.local.example" ]; then
    ENV_FILE=$(ls .env.example .env.local.example 2>/dev/null | head -1 || true)
    if grep -q "DATABASE_URL" "$ENV_FILE" 2>/dev/null; then
        if [ -z "$DB_TYPE" ]; then DB_TYPE="postgresql"; fi
    fi
    if grep -q "REDIS_URL" "$ENV_FILE" 2>/dev/null; then
        HAS_REDIS_DEPS=true
    fi
    # Extract expected env var names (lines with = that aren't comments)
    while IFS= read -r line; do
        key=$(echo "$line" | cut -d'=' -f1 | xargs)
        if [ -n "$key" ] && [[ ! "$key" =~ ^# ]]; then
            ENV_HINTS+=("$key")
        fi
    done < "$ENV_FILE"
fi

# Determine architecture
if [ "$HAS_NEXTJS" = true ] && [ "$HAS_SEPARATE_BACKEND" = false ]; then
    ARCHITECTURE="nextjs-fullstack"
elif [ "$HAS_SEPARATE_BACKEND" = true ]; then
    ARCHITECTURE="separate-frontend-backend"
else
    ARCHITECTURE="unknown"
fi

# Output JSON
cat <<EOF
{
  "architecture": "$ARCHITECTURE",
  "framework": "$FRAMEWORK",
  "hasNextjs": $HAS_NEXTJS,
  "hasSeparateBackend": $HAS_SEPARATE_BACKEND,
  "backendType": "$BACKEND_TYPE",
  "hasDockerfile": $HAS_DOCKERFILE,
  "hasRailwayToml": $HAS_RAILWAY_TOML,
  "hasPrisma": $HAS_PRISMA,
  "hasDrizzle": $HAS_DRIZZLE,
  "dbType": "$DB_TYPE",
  "hasRedisDeps": $HAS_REDIS_DEPS,
  "isMonorepo": $HAS_MONOREPO,
  "envHints": $(printf '%s\n' "${ENV_HINTS[@]:-}" | jq -R . | jq -s .)
}
EOF
