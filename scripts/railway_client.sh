#!/bin/bash
# Railway GraphQL API client helper
# Usage: ./railway_client.sh <command> [args...]
#
# Commands:
#   list-projects                    List all projects
#   create-project <name>            Create a new project
#   create-service <projectId> <name> <image>  Create a service from Docker image
#   get-variables <projectId> <envId> <serviceId>  Get service variables
#   set-variable <projectId> <envId> <serviceId> <key> <value>  Set env var
#   deploy <envId> <serviceId>       Trigger deployment
#   create-domain <envId> <instanceId> <domain>  Add custom domain
#
# Requires: RAILWAY_API_TOKEN environment variable

set -euo pipefail

API_URL="https://backboard.railway.com/graphql/v2"

if [ -z "${RAILWAY_API_TOKEN:-}" ]; then
    echo "Error: RAILWAY_API_TOKEN not set" >&2
    exit 1
fi

gql() {
    local query="$1"
    local variables="${2:-{}}"

    curl -s \
        -H "Authorization: Bearer ${RAILWAY_API_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{\"query\": $(echo "$query" | jq -Rs .), \"variables\": $variables}" \
        "$API_URL"
}

cmd_list_projects() {
    gql '
        query {
            projects {
                edges {
                    node {
                        id
                        name
                        updatedAt
                        services {
                            edges {
                                node {
                                    id
                                    name
                                }
                            }
                        }
                    }
                }
            }
        }
    ' | jq '.data.projects.edges[].node | {id, name, updatedAt, services: [.services.edges[].node]}'
}

cmd_create_project() {
    local name="$1"
    gql '
        mutation($input: ProjectCreateInput!) {
            projectCreate(input: $input) {
                id
                name
                environments {
                    edges {
                        node {
                            id
                            name
                        }
                    }
                }
            }
        }
    ' "{\"input\": {\"name\": \"$name\"}}" | jq '.data.projectCreate'
}

cmd_create_service() {
    local project_id="$1"
    local name="$2"
    local image="$3"

    gql '
        mutation($input: ServiceCreateInput!) {
            serviceCreate(input: $input) {
                id
                name
            }
        }
    ' "{\"input\": {\"projectId\": \"$project_id\", \"name\": \"$name\", \"source\": {\"image\": \"$image\"}}}" | jq '.data.serviceCreate'
}

cmd_get_variables() {
    local project_id="$1"
    local env_id="$2"
    local service_id="$3"

    gql '
        query($projectId: String!, $environmentId: String!, $serviceId: String!) {
            variables(projectId: $projectId, environmentId: $environmentId, serviceId: $serviceId)
        }
    ' "{\"projectId\": \"$project_id\", \"environmentId\": \"$env_id\", \"serviceId\": \"$service_id\"}" | jq '.data.variables'
}

cmd_set_variable() {
    local project_id="$1"
    local env_id="$2"
    local service_id="$3"
    local key="$4"
    local value="$5"

    gql '
        mutation($input: VariableUpsertInput!) {
            variableUpsert(input: $input)
        }
    ' "{\"input\": {\"projectId\": \"$project_id\", \"environmentId\": \"$env_id\", \"serviceId\": \"$service_id\", \"name\": \"$key\", \"value\": \"$value\"}}" | jq '.'
}

cmd_deploy() {
    local env_id="$1"
    local service_id="$2"

    gql '
        mutation($input: ServiceInstanceDeployV2Input!) {
            serviceInstanceDeployV2(input: $input)
        }
    ' "{\"input\": {\"environmentId\": \"$env_id\", \"serviceId\": \"$service_id\"}}" | jq '.'
}

cmd_create_domain() {
    local env_id="$1"
    local instance_id="$2"
    local domain="$3"

    gql '
        mutation($input: CustomDomainCreateInput!) {
            customDomainCreate(input: $input) {
                id
                domain
                status {
                    dnsRecords {
                        type
                        hostlabel
                        value
                    }
                }
            }
        }
    ' "{\"input\": {\"environmentId\": \"$env_id\", \"serviceInstanceId\": \"$instance_id\", \"domain\": \"$domain\"}}" | jq '.data.customDomainCreate'
}

# Main dispatch
command="${1:-}"
shift || true

case "$command" in
    list-projects)      cmd_list_projects ;;
    create-project)     cmd_create_project "$@" ;;
    create-service)     cmd_create_service "$@" ;;
    get-variables)      cmd_get_variables "$@" ;;
    set-variable)       cmd_set_variable "$@" ;;
    deploy)             cmd_deploy "$@" ;;
    create-domain)      cmd_create_domain "$@" ;;
    *)
        echo "Usage: $0 <command> [args...]"
        echo "Commands: list-projects, create-project, create-service, get-variables, set-variable, deploy, create-domain"
        exit 1
        ;;
esac
