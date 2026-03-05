#!/bin/bash
# Vercel REST API client helper
# Usage: ./vercel_client.sh <command> [args...]
#
# Commands:
#   whoami                                     Get current user info
#   list-projects [--team <teamId>]            List projects
#   create-project <name> <framework> [--repo <owner/repo>] [--team <teamId>]
#   get-env <projectId> [--team <teamId>]      Get env vars
#   set-env <projectId> <key> <value> <type> [--team <teamId>]  Set env var
#   deploy <projectId> <gitRef> [--team <teamId>]  Trigger deployment
#   get-deployment <deploymentId> [--team <teamId>]  Get deployment status
#   add-domain <projectId> <domain> [--team <teamId>]  Add custom domain
#   list-teams                                 List teams
#
# Requires: VERCEL_TOKEN environment variable

set -euo pipefail

API_URL="https://api.vercel.com"

if [ -z "${VERCEL_TOKEN:-}" ]; then
    echo "Error: VERCEL_TOKEN not set" >&2
    exit 1
fi

# Parse --team flag from remaining args
parse_team() {
    local team=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --team) team="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    echo "$team"
}

team_param() {
    local team="$1"
    if [ -n "$team" ]; then
        echo "?teamId=${team}"
    else
        echo ""
    fi
}

api() {
    local method="$1"
    local path="$2"
    shift 2

    local args=(-s -H "Authorization: Bearer ${VERCEL_TOKEN}" -H "Content-Type: application/json")

    if [ "$method" = "POST" ] || [ "$method" = "PATCH" ]; then
        local body="${1:-{}}"
        args+=(-X "$method" -d "$body")
    fi

    curl "${args[@]}" "${API_URL}${path}"
}

cmd_whoami() {
    api GET "/v2/user" | jq '.user | {username, email, name}'
}

cmd_list_projects() {
    local team=$(parse_team "$@")
    api GET "/v9/projects$(team_param "$team")" | jq '.projects[] | {id, name, framework, updatedAt}'
}

cmd_create_project() {
    local name="$1"
    local framework="$2"
    shift 2

    local repo=""
    local team=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --repo) repo="$2"; shift 2 ;;
            --team) team="$2"; shift 2 ;;
            *) shift ;;
        esac
    done

    local body
    if [ -n "$repo" ]; then
        body=$(jq -n --arg name "$name" --arg fw "$framework" --arg repo "$repo" \
            '{name: $name, framework: $fw, gitRepository: {type: "github", repo: $repo}}')
    else
        body=$(jq -n --arg name "$name" --arg fw "$framework" \
            '{name: $name, framework: $fw}')
    fi

    api POST "/v10/projects$(team_param "$team")" "$body" | jq '{id, name, framework}'
}

cmd_get_env() {
    local project_id="$1"
    shift
    local team=$(parse_team "$@")

    api GET "/v9/projects/${project_id}/env$(team_param "$team")" | jq '.envs[] | {id, key, type, target}'
}

cmd_set_env() {
    local project_id="$1"
    local key="$2"
    local value="$3"
    local type="${4:-encrypted}"
    shift 4 || true
    local team=$(parse_team "$@")

    local body
    body=$(jq -n --arg key "$key" --arg value "$value" --arg type "$type" \
        '[{key: $key, value: $value, type: $type, target: ["production", "preview", "development"]}]')

    api POST "/v10/projects/${project_id}/env$(team_param "$team")" "$body" | jq '.'
}

cmd_deploy() {
    local project_id="$1"
    local git_ref="$2"
    shift 2
    local team=$(parse_team "$@")

    local body
    body=$(jq -n --arg project "$project_id" --arg ref "$git_ref" \
        '{name: $project, project: $project, gitSource: {type: "github", ref: $ref}}')

    api POST "/v13/deployments$(team_param "$team")" "$body" | jq '{id, url, readyState}'
}

cmd_get_deployment() {
    local deployment_id="$1"
    shift
    local team=$(parse_team "$@")

    api GET "/v13/deployments/${deployment_id}$(team_param "$team")" | jq '{id, url, readyState, alias}'
}

cmd_add_domain() {
    local project_id="$1"
    local domain="$2"
    shift 2
    local team=$(parse_team "$@")

    local body
    body=$(jq -n --arg domain "$domain" '{name: $domain}')

    api POST "/v10/projects/${project_id}/domains$(team_param "$team")" "$body" | jq '.'
}

cmd_list_teams() {
    api GET "/v2/teams" | jq '.teams[] | {id, name, slug}'
}

# Main dispatch
command="${1:-}"
shift || true

case "$command" in
    whoami)           cmd_whoami ;;
    list-projects)    cmd_list_projects "$@" ;;
    create-project)   cmd_create_project "$@" ;;
    get-env)          cmd_get_env "$@" ;;
    set-env)          cmd_set_env "$@" ;;
    deploy)           cmd_deploy "$@" ;;
    get-deployment)   cmd_get_deployment "$@" ;;
    add-domain)       cmd_add_domain "$@" ;;
    list-teams)       cmd_list_teams ;;
    *)
        echo "Usage: $0 <command> [args...]"
        echo "Commands: whoami, list-projects, create-project, get-env, set-env, deploy, get-deployment, add-domain, list-teams"
        exit 1
        ;;
esac
