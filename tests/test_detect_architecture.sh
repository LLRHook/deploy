#!/bin/bash
# Tests for detect_architecture.sh
# Usage: bash tests/test_detect_architecture.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DETECT="${SCRIPT_DIR}/scripts/detect_architecture.sh"
PASS=0
FAIL=0
TOTAL=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

assert_json_field() {
    local json="$1"
    local field="$2"
    local expected="$3"
    local test_name="$4"
    TOTAL=$((TOTAL + 1))

    local actual
    actual=$(echo "$json" | jq -r ".$field")

    if [ "$actual" = "$expected" ]; then
        echo -e "  ${GREEN}PASS${NC} $test_name ($field = $expected)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $test_name ($field: expected '$expected', got '$actual')"
        FAIL=$((FAIL + 1))
    fi
}

setup_repo() {
    local dir
    dir=$(mktemp -d)
    echo "$dir"
}

teardown_repo() {
    rm -rf "$1"
}

# ─── Test: Next.js full-stack (package.json with next) ───

echo "Test: Next.js full-stack detection"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "next": "14.0.0",
    "react": "18.0.0",
    "@prisma/client": "5.0.0"
  }
}
EOF
mkdir -p "$repo/prisma"
touch "$repo/next.config.js"

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "architecture" "nextjs-fullstack" "Next.js full-stack"
assert_json_field "$result" "framework" "nextjs" "Framework is nextjs"
assert_json_field "$result" "hasNextjs" "true" "hasNextjs flag"
assert_json_field "$result" "hasPrisma" "true" "Prisma detected"
assert_json_field "$result" "dbType" "postgresql" "DB type is postgresql"
assert_json_field "$result" "hasSeparateBackend" "false" "No separate backend"
teardown_repo "$repo"

# ─── Test: Separate frontend/backend (Python backend) ───

echo ""
echo "Test: Separate frontend/backend (Python)"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "next": "14.0.0",
    "react": "18.0.0"
  }
}
EOF
touch "$repo/next.config.js"
touch "$repo/requirements.txt"

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "architecture" "separate-frontend-backend" "Separate architecture"
assert_json_field "$result" "hasNextjs" "true" "Has Next.js frontend"
assert_json_field "$result" "hasSeparateBackend" "true" "Has separate backend"
assert_json_field "$result" "backendType" "python" "Backend type is python"
teardown_repo "$repo"

# ─── Test: Separate frontend/backend (Go backend) ───

echo ""
echo "Test: Separate frontend/backend (Go)"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "next": "14.0.0",
    "react": "18.0.0"
  }
}
EOF
touch "$repo/next.config.js"
cat > "$repo/go.mod" <<'EOF'
module myapp
go 1.21
EOF

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "architecture" "separate-frontend-backend" "Separate architecture"
assert_json_field "$result" "backendType" "go" "Backend type is go"
teardown_repo "$repo"

# ─── Test: Express backend without Next.js ───

echo ""
echo "Test: Express backend (no Next.js)"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "express": "4.18.0",
    "ioredis": "5.0.0"
  }
}
EOF

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "architecture" "separate-frontend-backend" "Separate architecture"
assert_json_field "$result" "backendType" "node" "Backend type is node"
assert_json_field "$result" "hasRedisDeps" "true" "Redis deps detected"
teardown_repo "$repo"

# ─── Test: Drizzle ORM detection ───

echo ""
echo "Test: Drizzle ORM detection"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "next": "14.0.0",
    "react": "18.0.0",
    "drizzle-orm": "0.30.0"
  },
  "devDependencies": {
    "drizzle-kit": "0.20.0"
  }
}
EOF
touch "$repo/next.config.mjs"
touch "$repo/drizzle.config.ts"

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "hasDrizzle" "true" "Drizzle detected"
assert_json_field "$result" "dbType" "postgresql" "DB type from Drizzle"
teardown_repo "$repo"

# ─── Test: Monorepo detection ───

echo ""
echo "Test: Monorepo detection (turbo)"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "next": "14.0.0"
  }
}
EOF
touch "$repo/next.config.js"
echo '{}' > "$repo/turbo.json"

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "isMonorepo" "true" "Monorepo flag set"
teardown_repo "$repo"

# ─── Test: Dockerfile detection ───

echo ""
echo "Test: Dockerfile detection"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "next": "14.0.0"
  }
}
EOF
touch "$repo/next.config.js"
touch "$repo/Dockerfile"

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "hasDockerfile" "true" "Dockerfile detected"
teardown_repo "$repo"

# ─── Test: .env.example hints ───

echo ""
echo "Test: .env.example env var hints"
repo=$(setup_repo)
cat > "$repo/package.json" <<'EOF'
{
  "dependencies": {
    "next": "14.0.0"
  }
}
EOF
touch "$repo/next.config.js"
cat > "$repo/.env.example" <<'EOF'
DATABASE_URL=postgresql://localhost:5432/mydb
REDIS_URL=redis://localhost:6379
STRIPE_SECRET_KEY=sk_test_xxx
EOF

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "dbType" "postgresql" "DB type from .env.example"
assert_json_field "$result" "hasRedisDeps" "true" "Redis from .env.example"
teardown_repo "$repo"

# ─── Test: Empty directory ───

echo ""
echo "Test: Empty directory (unknown architecture)"
repo=$(setup_repo)

result=$(bash "$DETECT" "$repo" 2>/dev/null || true)
assert_json_field "$result" "architecture" "unknown" "Unknown architecture"
assert_json_field "$result" "hasNextjs" "false" "No Next.js"
assert_json_field "$result" "hasSeparateBackend" "false" "No backend"
teardown_repo "$repo"

# ─── Test: Invalid directory ───

echo ""
echo "Test: Invalid directory"
TOTAL=$((TOTAL + 1))
result=$(bash "$DETECT" "/nonexistent/path" 2>/dev/null || true)
if echo "$result" | jq -e '.error' > /dev/null 2>&1; then
    echo -e "  ${GREEN}PASS${NC} Returns error for invalid directory"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} Should return error for invalid directory"
    FAIL=$((FAIL + 1))
fi

# ─── Summary ───

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${TOTAL} total"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
