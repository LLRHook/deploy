# Vercel REST API Reference

## Endpoint & Auth

- **Base URL:** `https://api.vercel.com`
- **Auth:** `Authorization: Bearer <VERCEL_TOKEN>`
- **Team scope:** Append `?teamId=<team_id>` to requests when operating on team resources

## Token Validation

```
GET /v2/user
Authorization: Bearer <token>
```

Returns user profile if valid. 403 means invalid or insufficient scope.

## Core Endpoints

### Create a Project

```
POST /v10/projects
```

Body:
```json
{
  "name": "my-saas-app",
  "framework": "nextjs",
  "gitRepository": {
    "type": "github",
    "repo": "username/repo-name"
  }
}
```

Response includes `id` (the projectId you'll use everywhere) and `name`.

**Framework values:** `nextjs`, `create-react-app`, `vue`, `nuxt`, `svelte`, `sveltekit`,
`gatsby`, `remix`, `astro`, `angular`, `vite`, `hydrogen`, `blitz`, `redwood`, `ember`, `hugo`,
`jekyll`, `11ty`, `hexo`, `docusaurus`, `brunch`, `middleman`, `zola`, `parcel`, `sanity`,
`storybook`

If unsure, omit `framework` and Vercel will auto-detect.

### List Projects

```
GET /v9/projects
```

Optional query params: `search=name-fragment`, `limit=20`

Response includes paginated list of projects with `id`, `name`, `framework`, `latestDeployments`.
Use this for Mode 2 (Inspect & Integrate).

### Set Environment Variables

```
POST /v10/projects/{projectId}/env
```

Body (array of env vars):
```json
[
  {
    "key": "DATABASE_URL",
    "value": "postgres://...",
    "type": "encrypted",
    "target": ["production", "preview", "development"]
  },
  {
    "key": "NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY",
    "value": "pk_test_...",
    "type": "plain",
    "target": ["production", "preview", "development"]
  }
]
```

**Type values:**
- `encrypted` — For secrets (DATABASE_URL, API keys). Encrypted at rest, not visible in logs.
- `plain` — For non-sensitive values (public URLs, feature flags)
- `sensitive` — Like encrypted but also redacted in the Vercel dashboard

**Target values:** `production`, `preview`, `development`. Use all three unless you have
a reason to scope differently.

### Get Environment Variables

```
GET /v9/projects/{projectId}/env
```

Returns all env vars for the project. Use this to check if Stripe keys exist (Mode 2/3).
Note: encrypted values are returned as empty strings — you can check existence but not read values.

### Create a Deployment (from Git)

```
POST /v13/deployments
```

Body:
```json
{
  "name": "my-saas-app",
  "project": "prj_xxxx",
  "gitSource": {
    "type": "github",
    "ref": "main",
    "repoId": 123456789
  }
}
```

### Create a Deployment (file upload)

For non-Git workflows, upload files first, then create a deployment:

**Step 1 — Upload files:**
```
POST /v2/files
Content-Type: application/octet-stream
x-vercel-digest: <sha1-of-file>

<file contents>
```

**Step 2 — Create deployment with file references:**
```
POST /v13/deployments
```

Body:
```json
{
  "name": "my-saas-app",
  "project": "prj_xxxx",
  "files": [
    {
      "file": "package.json",
      "sha": "<sha1>",
      "size": 1234
    }
  ]
}
```

For most use cases, the Git-based deployment is simpler and preferred.

### Get Deployment Status

```
GET /v13/deployments/{deploymentId}
```

Response includes `readyState`:
- `QUEUED` — Waiting to build
- `BUILDING` — Build in progress
- `READY` — Successfully deployed
- `ERROR` — Build or deployment failed
- `CANCELED` — Deployment was canceled

Poll this endpoint until `READY` or `ERROR`. Typical build time is 30-120 seconds.

Also includes `url` (the deployment URL) and `alias` (production URL if aliased).

### Add a Domain

```
POST /v10/projects/{projectId}/domains
```

Body:
```json
{
  "name": "my-saas.com"
}
```

Response includes verification status and required DNS records.

### List Domains

```
GET /v9/projects/{projectId}/domains
```

Use this to check existing domain configuration in Mode 2/3.

## Deployment Build Logs

When a deployment fails, you want the build logs:

```
GET /v7/deployments/{deploymentId}/events
```

Returns an array of log events. Filter for `type: "stderr"` or `type: "error"` to find
what went wrong. Surface the last ~20 error lines to the user.

## Rate Limits

Vercel returns rate limit headers on every response:
- `X-RateLimit-Limit` — Max requests per window
- `X-RateLimit-Remaining` — Requests remaining
- `X-RateLimit-Reset` — Unix timestamp when window resets

When you get a 429, wait until `X-RateLimit-Reset` before retrying.

Typical limits: 100 requests per 60 seconds for most endpoints.

## Common Gotchas

1. **Team vs. Personal** — If the user has both, you need to ask which one. Team operations
   require `?teamId=xxx` on every request. Use `GET /v2/teams` to list teams.
2. **Git integration required** — For repo-based deployments, the user's Vercel account needs
   the GitHub integration installed. If `POST /v13/deployments` with `gitSource` fails with
   a permissions error, guide the user to install the Vercel GitHub App.
3. **Environment variable conflicts** — If you try to create an env var that already exists,
   the API returns a 409 conflict. Use `PATCH /v9/projects/{projectId}/env/{envId}` to update
   existing vars, or delete and recreate.
4. **NEXT_PUBLIC_ prefix** — Client-side env vars in Next.js MUST start with `NEXT_PUBLIC_`.
   If the user's code references `process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`, you need to
   set that exact key — not just `STRIPE_PUBLISHABLE_KEY`.
5. **Deployment URL vs. Production URL** — Each deployment gets a unique URL (xxx-yyy.vercel.app).
   The production URL (my-app.vercel.app) only updates when the production branch deploys.
   Custom domains alias to the production URL.
