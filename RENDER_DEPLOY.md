# Render.com Deployment Guide - Pharma Transport

## FDA 21 CFR Part 11 Compliant Cold Chain Platform

---

## Quick Start (5 Minutes)

### 1. Connect Repository
```
Render Dashboard → New → Blueprint → Connect GitHub Repo
Select: Pharma_Transport_all
Render auto-detects render.yaml
```

### 2. Set Secret Environment Variables

In Render Dashboard → Environment → Add the following:

| Variable | Where to Get It |
|----------|-----------------|
| `RAILS_MASTER_KEY` | `cat config/master.key` |
| `STRIPE_SECRET_KEY` | Stripe Dashboard → API Keys → Secret key |
| `STRIPE_PUBLISHABLE_KEY` | Stripe Dashboard → API Keys → Publishable key |
| `STRIPE_WEBHOOK_SECRET` | Stripe Dashboard → Webhooks → Signing secret |

### 3. Create Redis Instance

```
Render Dashboard → New → Redis
Name: pharma-transport-redis
Region: Ohio (same as web service)
Plan: Starter ($10/mo)
```

### 4. Deploy
```
Click "Create Services" → Wait for build (~5 min)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Render.com Infrastructure                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   Web x2    │    │   Worker    │    │    Cron     │     │
│  │   (Puma)    │    │  (Sidekiq)  │    │  (Verify)   │     │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘     │
│         │                  │                  │             │
│         └────────────┬─────┴──────────────────┘             │
│                      │                                      │
│         ┌────────────┴────────────┐                        │
│         ▼                         ▼                        │
│  ┌─────────────┐          ┌─────────────┐                  │
│  │ PostgreSQL  │          │    Redis    │                  │
│  │  (Primary)  │          │   (Cache)   │                  │
│  └─────────────┘          └─────────────┘                  │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Environment Variables Reference

### Required (Set Manually)

```bash
# Rails
RAILS_MASTER_KEY=<from config/master.key>

# Stripe Live Mode
STRIPE_SECRET_KEY=sk_live_xxxxxxxxxxxxxxxxxxxxx
STRIPE_PUBLISHABLE_KEY=pk_live_xxxxxxxxxxxxxxxxxxxxx
STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxx

# Stripe Price IDs (create in Stripe Dashboard → Products)
STRIPE_PRICE_SMB=price_xxxxx           # $299/mo
STRIPE_PRICE_ENTERPRISE=price_xxxxx    # $999/mo
STRIPE_PRICE_PFIZER=price_xxxxx        # Custom
```

### Auto-Configured (render.yaml)

```bash
RAILS_ENV=production
DATABASE_URL=<auto from Render PostgreSQL>
REDIS_URL=<auto from Render Redis>
ALLOWED_ORIGIN=https://pharmatransport.io
WEB_CONCURRENCY=2
RAILS_MAX_THREADS=5
LOG_FORMAT=json
```

---

## Stripe Webhook Setup

### 1. Create Webhook Endpoint

```
Stripe Dashboard → Developers → Webhooks → Add endpoint

Endpoint URL: https://pharmatransport.io/stripe/webhooks
API Version: 2024-12-18.acacia (latest)
```

### 2. Select Events

```
✓ checkout.session.completed
✓ customer.subscription.created
✓ customer.subscription.updated
✓ customer.subscription.deleted
✓ invoice.paid
✓ invoice.payment_failed
✓ invoice.payment_action_required
```

### 3. Copy Signing Secret

```
Webhooks → Your endpoint → Reveal signing secret
Copy whsec_xxxxx → Paste to STRIPE_WEBHOOK_SECRET in Render
```

---

## Database Migrations

### Automatic (Default)
Migrations run automatically via `bin/docker-entrypoint` on each deploy.

### Manual (If Needed)
```bash
# SSH into Render shell
render ssh pharma-transport-web

# Run migrations
bundle exec rails db:migrate

# Verify
bundle exec rails db:version
```

---

## Health Checks

| Endpoint | Purpose | Expected Response |
|----------|---------|-------------------|
| `GET /health/live` | Kubernetes liveness | `200 OK` |
| `GET /health/ready` | Kubernetes readiness | `200 OK` (DB + Redis connected) |
| `GET /health/detailed` | Monitoring | JSON with component status |

Render uses `/health/ready` for deployment health checks.

---

## FDA 21 CFR Part 11 Compliance

### Audit Chain Verification

Daily cron job verifies audit trail integrity:
```
Schedule: 0 6 * * * (6 AM UTC)
Command: bundle exec rails fda:verify_audit_chain
```

### Manual Verification
```bash
# In Render shell
bundle exec rails runner "puts AuditEvent.verify_chain.to_json"
```

### Backup Retention
- Enable **Point-in-Time Recovery (PITR)** in Render PostgreSQL settings
- Set retention to **35 days minimum** for FDA compliance

---

## Scaling

### Vertical (Upgrade Plan)

| Plan | RAM | CPU | Use Case |
|------|-----|-----|----------|
| Starter | 512MB | 0.5 | Development |
| Standard | 1GB | 1 | Production (< 100 trucks) |
| Pro | 2GB | 2 | Production (100-500 trucks) |
| Pro Plus | 4GB | 4 | Enterprise (500+ trucks) |

### Horizontal (Add Instances)

```yaml
# In render.yaml
numInstances: 4  # Scale to 4 web instances
```

---

## Monitoring

### Render Dashboard
- CPU/Memory usage per service
- Request latency
- Error rates

### Application Logs
```bash
# Stream logs
render logs pharma-transport-web --tail

# Search logs
render logs pharma-transport-web --since 1h | grep ERROR
```

### Prometheus Metrics
```
GET /metrics  # Prometheus endpoint (if enabled)
```

---

## Troubleshooting

### Build Fails
```bash
# Check Gemfile.lock is committed
git add Gemfile.lock
git commit -m "Update Gemfile.lock"
git push
```

### Database Connection Error
```bash
# Verify DATABASE_URL is set
render env pharma-transport-web | grep DATABASE

# Test connection
render shell pharma-transport-web
bundle exec rails db:version
```

### Stripe Webhooks Not Working
```bash
# Check webhook secret is set
render env pharma-transport-web | grep STRIPE_WEBHOOK

# Check logs for webhook errors
render logs pharma-transport-web | grep -i stripe
```

### Memory Issues
```bash
# Check memory usage
render metrics pharma-transport-web

# Reduce workers if OOM
WEB_CONCURRENCY=1  # Single worker mode
```

---

## Cost Estimate

| Service | Plan | Monthly Cost |
|---------|------|--------------|
| Web (x2 instances) | Standard | $50 |
| Worker | Starter | $7 |
| PostgreSQL | Standard | $20 |
| Redis | Starter | $10 |
| **Total** | | **$87/mo** |

For enterprise (500+ trucks): ~$200/mo with Pro plans.

---

## Go Live Checklist

- [ ] `RAILS_MASTER_KEY` set in Render
- [ ] `STRIPE_SECRET_KEY` set (sk_live_xxx)
- [ ] `STRIPE_PUBLISHABLE_KEY` set (pk_live_xxx)
- [ ] `STRIPE_WEBHOOK_SECRET` set (whsec_xxx)
- [ ] Stripe webhook endpoint created and verified
- [ ] Custom domain configured (pharmatransport.io)
- [ ] SSL certificate auto-provisioned
- [ ] Database PITR enabled (35-day retention)
- [ ] Health check passing (`/health/ready`)
- [ ] First test subscription created successfully
- [ ] Audit chain verification passing

---

## Support

- **Render Docs**: https://render.com/docs
- **Stripe Docs**: https://stripe.com/docs
- **FDA 21 CFR Part 11**: https://www.fda.gov/regulatory-information/search-fda-guidance-documents/part-11-electronic-records-electronic-signatures-scope-and-application

---

*Pharma Transport - FDA 21 CFR Part 11 Compliant Cold Chain Platform*
