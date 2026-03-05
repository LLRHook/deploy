# /deploy — SaaS Deployment Agent Skill

A [Claude Code](https://docs.anthropic.com/en/docs/claude-code) skill that automates end-to-end SaaS deployment using **Vercel** (frontend), **Railway** (backend + database), and **Stripe** (payments). Provision infrastructure, wire services together, and deploy — all from a single command.

## What It Does

Run `/deploy` in Claude Code and the agent will:

1. **Detect your app architecture** — Next.js full-stack or separate frontend/backend
2. **Provision infrastructure** — Railway Postgres (+ optional Redis), Vercel project
3. **Wire services together** — inject connection strings, set CORS origins, cross-link URLs
4. **Handle Stripe** — check integration status, guide setup if missing
5. **Deploy everything** — trigger builds on both platforms, poll until ready
6. **Validate** — health checks, env var drift detection, deployment status dashboard

## Supported Architectures

### Architecture A: Next.js Full-Stack
Frontend + API routes on Vercel, database on Railway. The most common SaaS pattern.

```
Vercel                          Railway
├── Next.js App          ──►    ├── PostgreSQL
│   ├── Frontend (React)        └── Redis (optional)
│   └── API Routes (/api/*)
│       ├── Stripe webhooks
│       └── DB queries
```

### Architecture B: Separate Frontend/Backend
Frontend on Vercel, backend service + database on Railway.

```
Vercel                          Railway
├── Next.js Frontend     ──►    ├── Backend API (Express/FastAPI/etc.)
│                               ├── PostgreSQL
│                               └── Redis (optional)
```

## Prerequisites

- A [Vercel](https://vercel.com) account with an API token ([create one](https://vercel.com/account/tokens))
- A [Railway](https://railway.app) account with an API token ([create one](https://railway.app/account/tokens))
- A [Stripe](https://stripe.com) account (keys managed via Vercel's Stripe Marketplace integration)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI installed

## Installation

### As a Claude Code Skill

Copy or symlink this directory into your Claude Code skills location, or reference it directly:

```bash
# Clone the repo
git clone https://github.com/vict0riv/deploy.git

# Or add as a skill in your Claude Code configuration
```

### Required Tools

The helper scripts use standard Unix tools:
- `curl` — API calls to Vercel and Railway
- `jq` — JSON parsing
- `python3` — config file management

## Usage

In Claude Code, just run:

```
/deploy
```

The agent will ask for your tokens and walk you through deployment. It operates in three modes:

| Mode | Trigger | Behavior |
|------|---------|----------|
| **Fresh Deploy** | No `.deploy.json` found | Provision everything from scratch |
| **Inspect & Integrate** | User has existing infra | Query APIs, find gaps, wire things up |
| **Redeploy** | `.deploy.json` exists | Validate services, check for drift, redeploy |

## Project Structure

```
deploy/
├── SKILL.md                        # Skill definition (agent prompt)
├── scripts/
│   ├── deploy_config.py            # .deploy.json config manager
│   ├── detect_architecture.sh      # App architecture detector
│   ├── railway_client.sh           # Railway GraphQL API client
│   ├── vercel_client.sh            # Vercel REST API client
│   └── validate_tokens.sh          # Token validation helper
├── references/
│   ├── architectures.md            # Env var mappings per architecture
│   ├── railway-api.md              # Railway API reference
│   ├── vercel-api.md               # Vercel API reference
│   └── stripe-integration.md       # Stripe integration guide
├── evals/
│   └── evals.json                  # Skill evaluation prompts
└── tests/
    ├── test_deploy_config.py       # Python config manager tests
    └── test_detect_architecture.sh # Architecture detection tests
```

## Helper Scripts

### `deploy_config.py` — Config Manager

Manages the `.deploy.json` state file:

```bash
python scripts/deploy_config.py init . --architecture nextjs-fullstack
python scripts/deploy_config.py read .
python scripts/deploy_config.py update . --key vercel.projectId --value prj_xxx
python scripts/deploy_config.py validate .
```

### `detect_architecture.sh` — Architecture Detector

Scans a repo directory and outputs a JSON detection report:

```bash
./scripts/detect_architecture.sh /path/to/repo
# {"architecture": "nextjs-fullstack", "framework": "nextjs", "hasPrisma": true, ...}
```

### `validate_tokens.sh` — Token Validator

Validates API tokens against live endpoints:

```bash
./scripts/validate_tokens.sh vercel "$VERCEL_TOKEN"
./scripts/validate_tokens.sh railway "$RAILWAY_API_TOKEN"
./scripts/validate_tokens.sh both "$VERCEL_TOKEN" "$RAILWAY_API_TOKEN"
```

### `railway_client.sh` / `vercel_client.sh` — API Clients

Thin wrappers around the Railway GraphQL and Vercel REST APIs:

```bash
# Railway
./scripts/railway_client.sh list-projects
./scripts/railway_client.sh create-project my-app

# Vercel
./scripts/vercel_client.sh whoami
./scripts/vercel_client.sh create-project my-app nextjs --repo owner/repo
```

## Running Tests

```bash
# Python tests (deploy_config.py)
python -m pytest tests/test_deploy_config.py -v

# Shell tests (detect_architecture.sh)
bash tests/test_detect_architecture.sh
```

## Limitations

- Cannot create accounts on Vercel, Railway, or Stripe
- Cannot complete Stripe OAuth flows (user must click through)
- Cannot configure DNS at domain registrars (provides records to add)
- Cannot switch Stripe to live mode (requires KYC in Stripe Dashboard)
- Monorepo support is limited — handles one app at a time
- Cannot enter payment information on any platform

## License

MIT
