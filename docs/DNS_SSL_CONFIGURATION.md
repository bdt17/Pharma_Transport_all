# Phase 5: DNS & SSL Configuration Guide

## Production Domain: pharmatransport.io

This guide covers DNS configuration, SSL certificate setup, and HTTPS enforcement for FDA 21 CFR Part 11 compliant production deployment.

---

## 1. DNS Configuration

### 1.1 Root Domain Setup (pharmatransport.io)

```dns
# A Record (for root domain)
pharmatransport.io.    IN    A      <RENDER_OR_EKS_IP>

# AAAA Record (IPv6)
pharmatransport.io.    IN    AAAA   <RENDER_OR_EKS_IPV6>

# CNAME for www subdomain
www.pharmatransport.io.    IN    CNAME    pharmatransport.io.
```

### 1.2 AWS EKS (Route 53)

```json
{
  "Name": "pharmatransport.io",
  "Type": "A",
  "AliasTarget": {
    "HostedZoneId": "Z32O12XQLNTSW2",
    "DNSName": "dualstack.pharma-alb-123456.us-east-1.elb.amazonaws.com",
    "EvaluateTargetHealth": true
  }
}
```

### 1.3 Multi-Tenant Subdomains

```dns
# Wildcard for tenant subdomains (*.pharmatransport.io)
*.pharmatransport.io.    IN    CNAME    pharmatransport.io.

# Examples:
# pfizer.pharmatransport.io -> Pfizer tenant
# cvs.pharmatransport.io -> CVS tenant
# walgreens.pharmatransport.io -> Walgreens tenant
```

### 1.4 API Subdomain

```dns
api.pharmatransport.io.    IN    CNAME    pharmatransport.io.
```

---

## 2. SSL/TLS Certificate Setup

### 2.1 Render (Automatic)

Render automatically provisions and renews Let's Encrypt certificates for custom domains.

1. Go to **Render Dashboard > Your Service > Settings > Custom Domain**
2. Add `pharmatransport.io`
3. Add `*.pharmatransport.io` for wildcard
4. Wait for DNS verification (green checkmark)

### 2.2 AWS Certificate Manager (ACM)

```bash
# Request certificate for root + wildcard
aws acm request-certificate \
  --domain-name pharmatransport.io \
  --subject-alternative-names "*.pharmatransport.io" \
  --validation-method DNS \
  --region us-east-1

# Add DNS validation records to Route 53
aws acm describe-certificate --certificate-arn <ARN> --query Certificate.DomainValidationOptions
```

### 2.3 Let's Encrypt (Manual/Certbot)

```bash
# Install certbot
apt-get install certbot python3-certbot-nginx

# Obtain wildcard certificate (requires DNS challenge)
certbot certonly \
  --manual \
  --preferred-challenges dns \
  -d pharmatransport.io \
  -d "*.pharmatransport.io"

# Auto-renewal
certbot renew --dry-run
```

---

## 3. Rails SSL Configuration

### 3.1 Force SSL in Production

**config/environments/production.rb:**

```ruby
Rails.application.configure do
  # Force all access to the app over SSL
  config.force_ssl = true

  # HSTS (HTTP Strict Transport Security)
  config.ssl_options = {
    hsts: {
      expires: 1.year,
      subdomains: true,
      preload: true
    },
    redirect: {
      exclude: ->(request) {
        # Exclude health checks from SSL redirect
        request.path.start_with?('/health')
      }
    }
  }

  # Secure cookies
  config.session_store :cookie_store,
    key: '_pharma_transport_session',
    secure: true,
    same_site: :strict

  # Trust proxy headers (required behind load balancer)
  config.action_dispatch.trusted_proxies = [
    IPAddr.new('10.0.0.0/8'),      # AWS VPC
    IPAddr.new('172.16.0.0/12'),   # Docker
    IPAddr.new('192.168.0.0/16')   # Private networks
  ]
end
```

### 3.2 Security Headers Middleware

**config/initializers/security_headers.rb:**

```ruby
Rails.application.config.middleware.insert_before 0, Rack::Headers do
  set 'Strict-Transport-Security', 'max-age=31536000; includeSubDomains; preload'
  set 'X-Frame-Options', 'DENY'
  set 'X-Content-Type-Options', 'nosniff'
  set 'X-XSS-Protection', '1; mode=block'
  set 'Referrer-Policy', 'strict-origin-when-cross-origin'
  set 'Permissions-Policy', 'geolocation=(self), microphone=()'
  set 'Content-Security-Policy', "default-src 'self'; script-src 'self' 'unsafe-inline' https://js.stripe.com; frame-src https://js.stripe.com; connect-src 'self' https://api.stripe.com wss://pharmatransport.io"
end
```

---

## 4. Load Balancer Configuration

### 4.1 AWS ALB (Application Load Balancer)

**kubernetes/base/ingress.yaml:**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: pharma-transport-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:us-east-1:123456789:certificate/abc-123
    alb.ingress.kubernetes.io/ssl-policy: ELBSecurityPolicy-TLS-1-2-2017-01
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/healthcheck-path: /health/ready
spec:
  rules:
  - host: pharmatransport.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pharma-transport-service
            port:
              number: 3000
  - host: "*.pharmatransport.io"
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: pharma-transport-service
            port:
              number: 3000
```

### 4.2 Nginx Configuration (Alternative)

```nginx
server {
    listen 80;
    server_name pharmatransport.io *.pharmatransport.io;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl http2;
    server_name pharmatransport.io *.pharmatransport.io;

    ssl_certificate /etc/letsencrypt/live/pharmatransport.io/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/pharmatransport.io/privkey.pem;

    # Modern TLS configuration
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:SSL:10m;
    ssl_session_tickets off;

    # HSTS
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # WebSocket support for GPS streaming
    location /cable {
        proxy_pass http://127.0.0.1:3000/cable;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

---

## 5. Environment Variables

### 5.1 Required Production Variables

```bash
# Domain Configuration
DOMAIN=pharmatransport.io
RAILS_SERVE_STATIC_FILES=true
RAILS_LOG_TO_STDOUT=true

# SSL/TLS
FORCE_SSL=true

# Stripe (Production Keys)
STRIPE_PUBLISHABLE_KEY=pk_live_xxx
STRIPE_SECRET_KEY=sk_live_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx

# Database
DATABASE_URL=postgres://user:pass@rds-endpoint:5432/pharma_production

# Redis (for ActionCable GPS streaming)
REDIS_URL=redis://elasticache-endpoint:6379/0

# Rails
SECRET_KEY_BASE=<generate with: rails secret>
```

### 5.2 Render Environment

Set via Render Dashboard > Environment:

```
RAILS_MASTER_KEY=<from config/master.key>
DATABASE_URL=<auto-provided by Render PostgreSQL>
REDIS_URL=<auto-provided by Render Redis>
```

---

## 6. DNS Propagation Verification

```bash
# Check A record
dig pharmatransport.io A +short

# Check CNAME for wildcard
dig *.pharmatransport.io CNAME +short

# Verify SSL certificate
openssl s_client -connect pharmatransport.io:443 -servername pharmatransport.io </dev/null 2>/dev/null | openssl x509 -noout -dates

# Test HSTS header
curl -I https://pharmatransport.io | grep -i strict-transport

# SSL Labs test (comprehensive)
# Visit: https://www.ssllabs.com/ssltest/analyze.html?d=pharmatransport.io
```

---

## 7. Troubleshooting

### 7.1 SSL Certificate Not Working

```bash
# Check certificate chain
openssl s_client -connect pharmatransport.io:443 -showcerts

# Verify DNS propagation
nslookup pharmatransport.io 8.8.8.8
```

### 7.2 Mixed Content Warnings

Ensure all assets use HTTPS:

```ruby
# config/environments/production.rb
config.asset_host = "https://pharmatransport.io"
config.action_controller.asset_host = "https://pharmatransport.io"
```

### 7.3 WebSocket Connection Failures

```javascript
// Ensure cable.js uses wss://
const wsUrl = `wss://${window.location.host}/cable`;
```

---

## 8. FDA 21 CFR Part 11 SSL Requirements

- **TLS 1.2 minimum**: Disable TLS 1.0/1.1
- **Strong ciphers**: AES-GCM preferred
- **Certificate validity**: Monitor expiration
- **HSTS enabled**: Prevent protocol downgrade attacks
- **Audit logging**: Log SSL/TLS connection metadata for compliance

---

## 9. Checklist

- [ ] DNS A record pointing to load balancer
- [ ] Wildcard DNS for tenant subdomains
- [ ] SSL certificate provisioned and valid
- [ ] HTTPS redirect configured (HTTP -> HTTPS)
- [ ] HSTS header enabled
- [ ] WebSocket (wss://) working for GPS streaming
- [ ] Health checks bypassing SSL redirect
- [ ] SSL Labs score A or A+
- [ ] Certificate auto-renewal configured
