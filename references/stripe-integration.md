# Stripe Integration via Vercel Marketplace

## How It Works

Stripe is a first-class integration on Vercel's Marketplace. When installed, it handles
the entire Stripe setup lifecycle automatically — no manual key management needed.

## What the Integration Does Automatically

1. **OAuth Consent** — User clicks through Stripe's OAuth flow (this is the one manual step)
2. **Sandbox Provisioning** — Creates a claimable Stripe sandbox scoped to the Vercel project
3. **Key Injection** — Adds these env vars to the Vercel project:
   - `STRIPE_SECRET_KEY` — Server-side API key
   - `STRIPE_PUBLISHABLE_KEY` — Client-side publishable key
   - `STRIPE_WEBHOOK_SECRET` — Webhook signing secret
4. **Webhook Configuration** — Automatically creates a webhook endpoint pointing at the Vercel
   deployment URL (usually `https://<app>.vercel.app/api/webhooks/stripe` or similar)

## Detection Flow

To check if Stripe is configured on a Vercel project:

```
GET /v9/projects/{projectId}/env
Authorization: Bearer <VERCEL_TOKEN>
```

Look for env vars with keys: `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET`.
Since these are encrypted, you can't read the values — but you can confirm they exist by checking
the `key` field in the response array.

**All three must exist** for Stripe to be considered fully configured. If only some exist,
the integration may be partially set up or broken.

## Guiding the User Through Setup

If Stripe keys are missing, tell the user:

```
Stripe isn't connected to your Vercel project yet. To set it up:

1. Go to: https://vercel.com/marketplace/stripe
2. Click "Add Integration"
3. Select your Vercel account/team
4. Choose the project: [project name]
5. Complete the Stripe OAuth flow (sign in to Stripe and authorize)
6. Come back here when done

This is a one-time setup. After this, Stripe keys are managed automatically.
```

After the user says they're done, re-check the env vars to confirm.

## Client-Side Key

The Vercel-Stripe integration injects `STRIPE_PUBLISHABLE_KEY` as a server-side env var.
For Next.js apps, client-side code needs the `NEXT_PUBLIC_` prefix. The skill should also set:

```
NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY = <same value as STRIPE_PUBLISHABLE_KEY>
```

Since you can't read the encrypted value, there are two approaches:
1. If the user's code uses `NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY`, ask them to paste their
   publishable key (it starts with `pk_test_` or `pk_live_` — this isn't a secret)
2. Or tell them to add this mapping in their `next.config.js`:
   ```js
   env: {
     NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY: process.env.STRIPE_PUBLISHABLE_KEY,
   }
   ```

## Test vs. Live Mode

- After initial setup, Stripe is in **test/sandbox mode** — `pk_test_*` and `sk_test_*` keys
- Switching to live requires:
  1. Completing Stripe's account verification (KYC) in the Stripe Dashboard
  2. Activating live mode in the Stripe Dashboard
  3. The Vercel integration may auto-update keys, or the user may need to reinstall the integration

The skill should report which mode Stripe is in. Check the key prefix:
- `pk_test_*` / `sk_test_*` → Test mode
- `pk_live_*` / `sk_live_*` → Live mode

Since you can't read encrypted env var values, you can either:
- Ask the user what mode they're in
- Check if the Vercel project has a `STRIPE_LIVE_MODE` or similar flag
- Default to reporting "Test mode" for new integrations (safe assumption)

## Webhook URL Timing

The Vercel-Stripe integration auto-configures the webhook URL to match the Vercel deployment URL.
This means:
- On first deploy, the webhook URL is set correctly automatically
- If the user adds a custom domain, they may need to update the webhook URL in Stripe Dashboard
- The `STRIPE_WEBHOOK_SECRET` stays the same regardless of URL changes

For Architecture B (separate backend on Railway handling Stripe webhooks):
- The Vercel-Stripe integration won't know about the Railway URL
- The user needs to manually configure the webhook in Stripe Dashboard to point at the Railway backend
- Or: proxy webhook requests from Vercel to Railway via an API route

## Common Gotchas

1. **Integration scope** — The Stripe integration is scoped per Vercel project, not per account.
   If the user has multiple projects, each needs its own integration install.
2. **Sandbox vs. existing Stripe account** — The integration can either create a new sandbox or
   connect to an existing Stripe account. If the user already has a Stripe account with products
   and prices set up, they should connect that account, not create a new sandbox.
3. **Env var naming** — Different Stripe SDKs and Next.js templates may expect different env var
   names (e.g., `STRIPE_API_KEY` vs. `STRIPE_SECRET_KEY`). The Vercel integration uses the
   canonical names. If the user's code expects different names, add aliases.
4. **Restricted keys** — For production, Stripe recommends restricted API keys with minimal
   permissions. The integration initially provides full-access keys. This is fine for development
   but should be tightened for production.
