# Supported App Architectures

## Architecture A: Next.js Full-Stack

The most common SaaS pattern. A single Next.js application handles both the frontend UI
and API routes (serverless functions). The database lives on Railway.

```
┌─────────────────────────────┐     ┌─────────────────────┐
│         Vercel              │     │      Railway         │
│                             │     │                      │
│  Next.js App                │     │  PostgreSQL          │
│  ├── Frontend (React)       │────▶│  └── DATABASE_URL    │
│  └── API Routes (/api/*)    │     │                      │
│       ├── Stripe webhooks   │     │  Redis (optional)    │
│       └── DB queries        │     │  └── REDIS_URL       │
└─────────────────────────────┘     └──────────────────────┘
```

### Detection Signals
- `next.config.*` exists
- `package.json` has `"next"` as dependency
- No separate `Dockerfile` or `railway.toml` for a backend
- API routes exist in `app/api/` or `pages/api/`

### Env Vars to Configure on Vercel

| Variable | Source | Type | Target |
|----------|--------|------|--------|
| `DATABASE_URL` | Railway Postgres service | `encrypted` | production, preview, development |
| `REDIS_URL` | Railway Redis service (if used) | `encrypted` | production, preview, development |
| `STRIPE_SECRET_KEY` | Vercel-Stripe integration | auto-injected | production, preview |
| `STRIPE_PUBLISHABLE_KEY` | Vercel-Stripe integration | auto-injected | production, preview |
| `STRIPE_WEBHOOK_SECRET` | Vercel-Stripe integration | auto-injected | production, preview |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | Copy of STRIPE_PUBLISHABLE_KEY | `plain` | production, preview, development |
| `NEXT_PUBLIC_APP_URL` | Vercel deployment URL | `plain` | production, preview |

### Prisma-Specific Considerations

If the app uses Prisma (detected by `prisma/` directory or `@prisma/client` in dependencies):
- `DATABASE_URL` must be a valid Postgres connection string
- Prisma needs `directUrl` for migrations in some setups — Railway provides this via
  the non-pooled connection string
- Add to Vercel env vars: `DIRECT_URL` (same as DATABASE_URL for Railway, since Railway
  doesn't use connection pooling by default)
- The build command should include `prisma generate` (usually in `postinstall` script)
- For first deploy, Prisma migrations need to run: `npx prisma migrate deploy`

### Drizzle-Specific Considerations

If the app uses Drizzle (detected by `drizzle.config.*` or `drizzle-orm` in dependencies):
- `DATABASE_URL` works the same way
- Migrations: `npx drizzle-kit migrate` or `npx drizzle-kit push`

---

## Architecture B: Separate Frontend/Backend

Frontend on Vercel, backend as a separate service on Railway alongside the database.
Common when using Python (FastAPI, Django), Go, Rust, or any non-Node.js backend.

```
┌──────────────────┐     ┌────────────────────────────┐
│     Vercel        │     │          Railway            │
│                   │     │                             │
│  Next.js Frontend │────▶│  Backend API                │
│  (React SPA or    │     │  ├── Express / FastAPI /etc │
│   SSR pages)      │     │  ├── Stripe webhooks        │
│                   │     │  └── DB queries              │
│                   │     │                             │
│                   │     │  PostgreSQL                  │
│                   │     │  └── DATABASE_URL            │
│                   │     │                             │
│                   │     │  Redis (optional)            │
│                   │     │  └── REDIS_URL               │
└──────────────────┘     └────────────────────────────┘
```

### Detection Signals
- Separate directories like `frontend/` + `backend/` or `web/` + `api/`
- `Dockerfile` in the repo root or a subdirectory
- `railway.toml` present
- `requirements.txt` / `pyproject.toml` / `go.mod` / `Cargo.toml` alongside a frontend
- `package.json` has a non-Next.js backend framework (Express, Fastify, Hono, etc.)

### Env Vars to Configure on Vercel (Frontend)

| Variable | Source | Type | Target |
|----------|--------|------|--------|
| `NEXT_PUBLIC_API_URL` | Railway backend service URL | `plain` | production, preview, development |
| `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY` | User provides or Stripe integration | `plain` | production, preview, development |
| `NEXT_PUBLIC_APP_URL` | Vercel deployment URL | `plain` | production, preview |

### Env Vars to Configure on Railway (Backend)

| Variable | Source | Type |
|----------|--------|------|
| `DATABASE_URL` | Railway Postgres (auto via reference vars) | auto |
| `REDIS_URL` | Railway Redis (auto via reference vars) | auto |
| `STRIPE_SECRET_KEY` | User provides manually | manual |
| `STRIPE_WEBHOOK_SECRET` | User configures webhook in Stripe Dashboard | manual |
| `CORS_ORIGIN` | Vercel frontend URL | manual |
| `PORT` | Railway auto-assigns or configured | auto |

### Important: Stripe Handling Differs

In Architecture B, Stripe webhooks go to the Railway backend, NOT to Vercel. This means:
- The Vercel-Stripe Marketplace integration is less useful (it configures webhooks for Vercel URLs)
- The user needs to:
  1. Get their Stripe API keys from the Stripe Dashboard manually
  2. Set them as Railway env vars on the backend service
  3. Configure the webhook endpoint in Stripe Dashboard pointing at `https://<railway-backend>/api/webhooks/stripe`
- The skill should detect this and adjust its Stripe guidance accordingly

### CORS Configuration

The backend MUST allow requests from the Vercel frontend domain. Typical setup:

```
CORS_ORIGIN=https://my-app.vercel.app
```

If the user has a custom domain, also add it:
```
CORS_ORIGIN=https://my-app.vercel.app,https://my-saas.com
```

### Cross-Service URL Chicken-and-Egg

Both services need each other's URL, but neither has one until deployed:

**Resolution order:**
1. Deploy the Railway backend first (it gets a `*.up.railway.app` URL immediately)
2. Set `NEXT_PUBLIC_API_URL` on Vercel to the Railway URL
3. Deploy the Vercel frontend
4. Set `CORS_ORIGIN` on the Railway backend to the Vercel URL
5. Redeploy the Railway backend (so it picks up the new CORS_ORIGIN)

This two-pass approach is unavoidable. The skill should handle it transparently.

---

## How to Detect Architecture

Run this detection in order:

1. **Check for monorepo markers**: `turbo.json`, `nx.json`, `pnpm-workspace.yaml`, `lerna.json`
   → If found, warn the user that monorepo support is limited and ask which app to deploy

2. **Check for Next.js**: `next.config.*` or `"next"` in package.json dependencies
   → If found, this is at minimum the Vercel frontend

3. **Check for separate backend**:
   - `Dockerfile` in root or subdirectory (not for the Next.js app)
   - `railway.toml` present
   - `requirements.txt` / `pyproject.toml` at root (Python backend)
   - `go.mod` / `Cargo.toml` at root
   - Separate `server/` or `api/` or `backend/` directory with its own package.json

4. **If Next.js + no separate backend** → Architecture A
5. **If Next.js + separate backend** → Architecture B
6. **If no Next.js but has a frontend framework** (React, Vue, Svelte) + backend → Architecture B

7. **Check for database need**:
   - `prisma/` directory → Postgres needed
   - `drizzle.config.*` → Postgres needed
   - `@prisma/client` or `drizzle-orm` in dependencies → Postgres needed
   - `.env.example` mentions `DATABASE_URL` → database needed
   - `mongoose` or `mongodb` in dependencies → MongoDB (not supported yet — warn user)

8. **Check for Redis need**:
   - `ioredis`, `redis`, `bull`, `bullmq`, `@upstash/redis` in dependencies
   - `.env.example` mentions `REDIS_URL`

Always confirm the detection with the user before provisioning.
