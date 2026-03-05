#!/bin/bash
# Validates Vercel and Railway API tokens
# Usage: ./validate_tokens.sh [vercel|railway|both] <token>
# Returns 0 on success, 1 on failure

set -euo pipefail

validate_vercel() {
    local token="$1"
    local response
    local http_code

    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        "https://api.vercel.com/v2/user")

    if [ "$http_code" = "200" ]; then
        response=$(curl -s -H "Authorization: Bearer ${token}" \
            "https://api.vercel.com/v2/user")
        local username=$(echo "$response" | jq -r '.user.username // .user.name // "unknown"')
        echo "VERCEL_VALID|${username}"
        return 0
    else
        echo "VERCEL_INVALID|HTTP ${http_code}"
        return 1
    fi
}

validate_railway() {
    local token="$1"
    local response
    local http_code

    response=$(curl -s -w "\n%{http_code}" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d '{"query":"query { me { id email name } }"}' \
        "https://backboard.railway.com/graphql/v2")

    http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')

    if [ "$http_code" = "200" ]; then
        local has_errors=$(echo "$body" | jq -r '.errors // empty')
        if [ -n "$has_errors" ]; then
            local error_msg=$(echo "$body" | jq -r '.errors[0].message // "Unknown error"')
            echo "RAILWAY_INVALID|${error_msg}"
            return 1
        fi
        local email=$(echo "$body" | jq -r '.data.me.email // "unknown"')
        echo "RAILWAY_VALID|${email}"
        return 0
    else
        echo "RAILWAY_INVALID|HTTP ${http_code}"
        return 1
    fi
}

# Main
service="${1:-both}"
token="${2:-}"

if [ -z "$token" ] && [ "$service" != "both" ]; then
    echo "Usage: $0 [vercel|railway|both] <token>"
    echo "  For 'both': $0 both <vercel_token> <railway_token>"
    exit 1
fi

case "$service" in
    vercel)
        validate_vercel "$token"
        ;;
    railway)
        validate_railway "$token"
        ;;
    both)
        vercel_token="${2:-}"
        railway_token="${3:-}"
        if [ -z "$vercel_token" ] || [ -z "$railway_token" ]; then
            echo "Usage: $0 both <vercel_token> <railway_token>"
            exit 1
        fi
        echo "--- Vercel ---"
        validate_vercel "$vercel_token" || true
        echo "--- Railway ---"
        validate_railway "$railway_token" || true
        ;;
    *)
        echo "Unknown service: $service"
        exit 1
        ;;
esac
