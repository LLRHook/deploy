# Railway GraphQL API Reference

## Endpoint & Auth

- **Endpoint:** `https://backboard.railway.com/graphql/v2`
- **Auth:** `Authorization: Bearer <RAILWAY_API_TOKEN>`
- **Method:** POST with JSON body `{ "query": "...", "variables": { ... } }`

## Token Validation

```graphql
query {
  me {
    id
    email
    name
  }
}
```

If this returns a valid response, the token is good. A 401 means expired or invalid.

## Discovering the Schema

Railway supports GraphQL introspection. The best way to explore available operations
is the GraphiQL playground or sending an introspection query. The mutations and queries
below are based on the documented public API, but field names or required inputs may
evolve — introspect first if something doesn't work.

## Core Mutations

### Create a Project

```graphql
mutation ProjectCreate($input: ProjectCreateInput!) {
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
```

Variables:
```json
{
  "input": {
    "name": "my-saas-app",
    "teamId": "optional-team-uuid"
  }
}
```

The response includes the default environment (usually "production"). Save the `environmentId`
— you'll need it for service creation and variable management.

### Create a Service (Database)

```graphql
mutation ServiceCreate($input: ServiceCreateInput!) {
  serviceCreate(input: $input) {
    id
    name
  }
}
```

For Postgres:
```json
{
  "input": {
    "projectId": "project-uuid",
    "name": "postgres",
    "source": {
      "image": "postgres"
    }
  }
}
```

For Redis:
```json
{
  "input": {
    "projectId": "project-uuid",
    "name": "redis",
    "source": {
      "image": "redis"
    }
  }
}
```

**Important:** After creating a database service, Railway auto-generates connection variables.
You need to attach a volume for Postgres persistence:

```graphql
mutation VolumeCreate($input: VolumeCreateInput!) {
  volumeCreate(input: $input) {
    id
  }
}
```

With mount path `/var/lib/postgresql/data` for Postgres.

### Create a Service (From Repo)

For a backend service deployed from a GitHub repo:
```json
{
  "input": {
    "projectId": "project-uuid",
    "name": "backend-api",
    "source": {
      "repo": "github.com/username/repo",
      "branch": "main"
    }
  }
}
```

### Set Environment Variables

```graphql
mutation VariableUpsert($input: VariableUpsertInput!) {
  variableUpsert(input: $input)
}
```

Variables:
```json
{
  "input": {
    "projectId": "project-uuid",
    "environmentId": "env-uuid",
    "serviceId": "service-uuid",
    "name": "CORS_ORIGIN",
    "value": "https://my-app.vercel.app"
  }
}
```

### Trigger Deployment

```graphql
mutation ServiceInstanceDeployV2($input: ServiceInstanceDeployV2Input!) {
  serviceInstanceDeployV2(input: $input)
}
```

Variables — note the `environmentId` and `serviceId` are required:
```json
{
  "input": {
    "environmentId": "env-uuid",
    "serviceId": "service-uuid"
  }
}
```

### Add Custom Domain

```graphql
mutation CustomDomainCreate($input: CustomDomainCreateInput!) {
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
```

Variables:
```json
{
  "input": {
    "environmentId": "env-uuid",
    "serviceInstanceId": "instance-uuid",
    "domain": "api.my-saas.com"
  }
}
```

The `dnsRecords` in the response tell the user what CNAME to add at their DNS provider.

## Core Queries

### List Projects

```graphql
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
```

Use this for Mode 2 (Inspect & Integrate) — let the user pick which project maps to their repo.

### Get Project Details

```graphql
query Project($id: String!) {
  project(id: $id) {
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
    services {
      edges {
        node {
          id
          name
          serviceInstances {
            edges {
              node {
                id
                domains {
                  serviceDomains {
                    domain
                  }
                  customDomains {
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
              }
            }
          }
        }
      }
    }
  }
}
```

### Get Service Variables (Connection Strings)

```graphql
query Variables($projectId: String!, $environmentId: String!, $serviceId: String!) {
  variables(
    projectId: $projectId
    environmentId: $environmentId
    serviceId: $serviceId
  )
}
```

This returns a JSON object of all variables. For a Postgres service, expect:
`DATABASE_URL`, `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`

For Redis: `REDIS_URL`, `REDISHOST`, `REDISPORT`, `REDISPASSWORD`

### Get Deployment Status

```graphql
query Deployments($input: DeploymentListInput!) {
  deployments(input: $input) {
    edges {
      node {
        id
        status
        createdAt
      }
    }
  }
}
```

Status values: `BUILDING`, `DEPLOYING`, `SUCCESS`, `FAILED`, `CRASHED`, `REMOVED`

## Rate Limits

Railway's API has rate limits but they're generous for typical deployment workflows.
If you hit a 429, wait and retry with exponential backoff. The response headers include
rate limit information.

## Common Gotchas

1. **Volume required for Postgres persistence** — Without a volume, Postgres data is lost on redeploy
2. **Reference variables** — Railway uses `${{ServiceName.VAR}}` syntax for inter-service references.
   When reading variables via API, these are resolved to actual values.
3. **Environment isolation** — Variables and deployments are scoped to environments (production, staging, etc.).
   Always specify the environmentId.
4. **GitHub integration auth** — If deploying from a repo, the Railway account needs GitHub access.
   This is a one-time OAuth flow the user does in the Railway dashboard.
5. **Free tier limits** — Check project/service limits. The API will return errors if exceeded.
