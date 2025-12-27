# Pharma Transport - Final Production Deployment Checklist

## FDA 21 CFR Part 11 Compliant | Stripe Live Mode | Render.com

---

## Pre-Deployment Verification

### Stripe Integration Files

| File | Status | Purpose |
|------|--------|---------|
| `app/controllers/stripe/checkout_sessions_controller.rb` | VERIFIED | Creates checkout sessions, handles success/cancel |
| `app/controllers/stripe/webhooks_controller.rb` | VERIFIED | STRIPE_WEBHOOK_SECRET verification, subscription lifecycle |
| `app/controllers/concerns/require_active_subscription.rb` | VERIFIED | Blocks unpaid tenants, 7-day grace period |
| `app/models/tenant.rb` | VERIFIED | stripe_customer_id, stripe_subscription_id, subscription_status |
| `app/models/stripe_event.rb` | VERIFIED | Idempotent webhook processing |
| `config/initializers/stripe.rb` | VERIFIED | API config, version lock, boot verification |

### FDA 21 CFR Part 11 Audit System

| File | Status | Purpose |
|------|--------|---------|
| `app/models/audit_event.rb` | VERIFIED | Immutable hash-chain audit log |
| `app/services/audit_logger.rb` | VERIFIED | Service for automatic audit logging |
| `app/models/audit_log.rb` | VERIFIED | Legacy audit logging support |
| `lib/tasks/fda.rake` | VERIFIED | Daily chain verification cron task |

### Routes & Dashboard

| Route | Controller | Purpose |
|-------|------------|---------|
| `POST /stripe/webhooks` | Stripe::WebhooksController | Webhook endpoint |
| `POST /stripe/checkout_sessions` | Stripe::CheckoutSessionsController | Create checkout |
| `GET /stripe/checkout_sessions/success` | Stripe::CheckoutSessionsController | Payment success |
| `GET /stripe/checkout_sessions/cancel` | Stripe::CheckoutSessionsController | Payment cancelled |
| `POST /stripe/checkout_sessions/portal` | Stripe::CheckoutSessionsController | Billing portal |
| `GET /billing` | BillingController | Billing dashboard |
| `GET /dashboard` | DashboardController | Main dashboard |
| `GET /dashboard/subscription_required` | DashboardController | Subscription gate |
| `GET /health/ready` | HealthController | Render health check |

### Deployment Files

| File | Status | Purpose |
|------|--------|---------|
| `render.yaml` | VERIFIED | Blueprint: web x2, worker, PostgreSQL, cron |
| `Dockerfile` | VERIFIED | Multi-stage build, jemalloc, non-root user |
| `Procfile` | VERIFIED | Puma + Sidekiq + release migrations |
| `config/puma.rb` | VERIFIED | Production-tuned (2 workers, 5 threads) |
| `config/sidekiq.yml` | VERIFIED | Background job config |
| `config/environments/production.rb` | VERIFIED | SSL, logging, FDA compliance |
| `bin/docker-entrypoint` | VERIFIED | DB wait, migrations, audit verify |

### Database Migrations

| Migration | Purpose |
|-----------|---------|
| `create_tenants` | Core tenant table |
| `add_complete_stripe_fields_to_tenants` | Stripe billing fields |
| `create_stripe_events` | Webhook idempotency |
| `create_audit_events` | FDA audit trail |
| `add_fda_fields_to_audit_events` | Hash chain fields |

---

## Deployment Steps

### Step 1: Commit All Files

```bash
cd /home/zero/Pharma_Transport_all

# Verify all files are tracked
git status

# Add deployment files
git add render.yaml Dockerfile Procfile \
  config/puma.rb config/sidekiq.yml \
  config/initializers/stripe.rb \
  bin/docker-entrypoint \
  lib/tasks/fda.rake \
  RENDER_DEPLOY.md DEPLOY_CHECKLIST.md \
  Gemfile Gemfile.lock

# Commit
git commit -m "Production deployment: FDA 21 CFR Part 11 + Stripe Live Mode

- render.yaml blueprint for Render.com
- Multi-stage Dockerfile with jemalloc optimization
- Stripe webhook signature verification
- RequireActiveSubscription access control
- FDA audit chain verification cron job"

# Push to trigger deploy
git push origin main
```

### Step 2: Connect to Render

1. Go to **Render Dashboard** (https://dashboard.render.com)
2. Click **New** → **Blueprint**
3. Connect your GitHub repository
4. Render auto-detects `render.yaml`
5. Review services and click **Apply**

### Step 3: Set Secret Environment Variables

In Render Dashboard → **Environment** tab for each service:

| Variable | Value | Notes |
|----------|-------|-------|
| `RAILS_MASTER_KEY` | `cat config/master.key` | Required for credentials |
| `STRIPE_SECRET_KEY` | `sk_live_xxxxx` | From Stripe Dashboard |
| `STRIPE_PUBLISHABLE_KEY` | `pk_live_xxxxx` | From Stripe Dashboard |
| `STRIPE_WEBHOOK_SECRET` | `whsec_xxxxx` | From Stripe Webhooks |

### Step 4: Create Redis Instance

1. Render Dashboard → **New** → **Redis**
2. Name: `pharma-transport-redis`
3. Region: `Ohio` (same as web)
4. Plan: `Starter` ($10/mo)

### Step 5: Configure Stripe Webhook

1. **Stripe Dashboard** → **Developers** → **Webhooks**
2. Click **Add endpoint**
3. URL: `https://pharmatransport.io/stripe/webhooks`
4. Select events:
   - `checkout.session.completed`
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.paid`
   - `invoice.payment_failed`
5. Copy signing secret → Set as `STRIPE_WEBHOOK_SECRET` in Render

### Step 6: Run Migrations

Migrations run automatically via `bin/docker-entrypoint` on deploy.

To verify manually:
```bash
# In Render Shell
bundle exec rails db:migrate:status
bundle exec rails db:version
```

### Step 7: Verify Health Check

```bash
curl https://pharmatransport.io/health/ready
# Expected: {"status":"ok","database":"connected","redis":"connected"}
```

---

## Post-Deployment Verification

### Test Stripe Webhooks

```bash
# Install Stripe CLI
brew install stripe/stripe-cli/stripe

# Login
stripe login

# Forward webhooks to local (for testing)
stripe listen --forward-to localhost:3000/stripe/webhooks

# Trigger test event
stripe trigger checkout.session.completed
```

### Verify Audit Chain

```bash
# In Render Shell or locally
bundle exec rails fda:verify_audit_chain

# Expected output:
# [FDA] Chain Status: VALID
# [FDA] Records Checked: X
```

### Test Subscription Flow

1. Visit `https://pharmatransport.io/billing`
2. Click "Subscribe" for SMB plan
3. Complete Stripe Checkout
4. Verify redirect to `/dashboard`
5. Check `tenant.subscription_status == "active"`

### Verify Logs

```bash
# Stream logs
render logs pharma-transport-web --tail

# Check for:
# - "[Stripe] Processing event: checkout.session.completed"
# - "[FDA Audit] stripe.webhook.subscription_activated"
```

---

## Final Checklist

### Stripe

- [ ] `STRIPE_SECRET_KEY` set (`sk_live_xxx`)
- [ ] `STRIPE_PUBLISHABLE_KEY` set (`pk_live_xxx`)
- [ ] `STRIPE_WEBHOOK_SECRET` set (`whsec_xxx`)
- [ ] Webhook endpoint created in Stripe Dashboard
- [ ] Webhook signing verified (check logs for "Invalid signature" errors)
- [ ] Test checkout completes successfully
- [ ] Webhook updates `tenant.subscription_status` to `active`

### FDA 21 CFR Part 11

- [ ] Audit chain verification passing (`rails fda:verify_audit_chain`)
- [ ] AuditEvent records created on checkout
- [ ] Hash chain integrity maintained (no tampering)
- [ ] Daily cron job scheduled (6 AM UTC)
- [ ] PostgreSQL PITR enabled (35-day retention)

### Infrastructure

- [ ] Health check passing (`/health/ready`)
- [ ] Web instances running (x2 for HA)
- [ ] Worker instance running (Sidekiq)
- [ ] Redis connected
- [ ] PostgreSQL connected
- [ ] SSL certificate provisioned
- [ ] Custom domain configured

### Security

- [ ] `RAILS_MASTER_KEY` set (not in git)
- [ ] Force SSL enabled
- [ ] Non-root Docker user
- [ ] No secrets in logs
- [ ] API authentication working

---

## Monthly Costs (Render.com)

| Service | Plan | Cost |
|---------|------|------|
| Web (x2 instances) | Standard | $50/mo |
| Worker | Starter | $7/mo |
| PostgreSQL | Standard | $20/mo |
| Redis | Starter | $10/mo |
| **Total** | | **$87/mo** |

---

## Support

- **Render Status**: https://status.render.com
- **Stripe Status**: https://status.stripe.com
- **FDA Part 11 Guide**: https://www.fda.gov/regulatory-information/search-fda-guidance-documents/part-11-electronic-records-electronic-signatures

---

*Pharma Transport - FDA 21 CFR Part 11 Compliant Cold Chain Logistics*
*Production Ready: Stripe Live Mode | Render.com | PostgreSQL*
