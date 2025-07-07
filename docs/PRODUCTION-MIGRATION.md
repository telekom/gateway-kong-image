<!--
SPDX-FileCopyrightText: 2025 Deutsche Telekom AG

SPDX-License-Identifier: CC0-1.0    
-->

# Production Migration Plan: Kong 2.8.3 → 3.9.1

## Overview

This document outlines the production migration strategy for upgrading an existing `gateway-kong-image with Kong v2.8.3` deployment from Kong 2.8.3 to Kong 3.9.1 with AWS Aurora PostgreSQL backend.

**Target**: Zero-downtime migration with drop-in replacement capability where possible.

## ⚠️ Critical Migration Constraints

### 🚫 **Downtime Requirements - UNAVOIDABLE**

**Issue**: Kong database migrations between major versions (2.8.3 → 3.9.1) are **one-way and incompatible**.

- Kong 3.9.1 requires database schema changes that break Kong 2.8.3 compatibility
- `kong migrations up` cannot be rolled back automatically
- Running mixed Kong versions against the same database will cause failures

**Mitigation**: Planned maintenance window with database snapshot strategy (see Blue-Green approach below).

### 🚫 **Drop-in Replacement - PARTIAL COMPATIBILITY**

**Issues**:

1. **Plugin Configuration Schema Changes**: Some plugin configurations may need updates
2. **Behavioral Differences**: Kong 3.9.1 has different defaults and behaviors
3. **Custom Plugin Loading**: Plugin loading mechanisms have changed

**Mitigation**: Comprehensive pre-migration validation and configuration transformation.

### 📋 **Critical Plugin Schema Differences (Kong 2.8.3 → 3.9.1)**

#### Core Kong Plugins

**Rate Limiting Plugin** (NO BREAKING CHANGES):

```yaml
# Kong 2.8.3 and 3.9.1 (identical schema - backward compatible)
plugins:
- name: rate-limiting
  config:
    minute: 100
    hour: 1000
    policy: local

# Note: rate-limiting-advanced is a separate Kong Enterprise plugin
# rate-limiting (OSS) remains unchanged between versions
```

**Most Core Plugins** (NO BREAKING CHANGES):

```yaml
# Kong 2.8.3 and 3.9.1 (backward compatible)
plugins:
- name: basic-auth
  config:
    hide_credentials: true

# Same for: cors, jwt, oauth2, key-auth, rate-limiting, 
# response-ratelimiting, request-transformer, response-transformer, etc.
```

**Request Transformer Plugin**:

```yaml
# Kong 2.8.3 and 3.9.1 (backward compatible)
plugins:
- name: request-transformer
  config:
    add:
      headers: ["X-Custom-Header:value"]
    # Other sections (remove, replace, rename, append) are optional
    # Kong automatically provides empty defaults

# Advanced Kong 3.9.1 features (new capabilities)
plugins:
- name: request-transformer
  config:
    add:
      headers: ["X-Custom-Header:value"]
      querystring: ["param:value"]
      body: ["field:value"]
    http_method: "POST"  # New field for HTTP method transformation
```

**Response Transformer Plugin**:

```yaml
# Kong 2.8.3 and 3.9.1 (backward compatible)
plugins:
- name: response-transformer
  config:
    remove:
      headers: ["server"]
    # Other sections (add, replace, append) are optional
    # Kong automatically provides empty defaults

# Kong 3.9.1 new features (enhanced JSON support)
plugins:
- name: response-transformer
  config:
    add:
      headers: ["X-Response-Header:value"]
      json: ["new_field:value"]          # Enhanced JSON manipulation
      json_types: ["new_field:string"]   # Type specification for JSON fields
```

#### Deutsche Telekom Custom Plugins

**JWT-Keycloak Plugin**:

```yaml
# Kong 2.8.3 (existing configuration)
plugins:
- name: jwt-keycloak
  config:
    allowed_iss: ["https://keycloak.example.com/auth/realms/master"]
    consumer_match: true
    consumer_match_claim: "azp"

# Kong 3.9.1 (enhanced schema)
plugins:
- name: jwt-keycloak  
  config:
    allowed_iss: ["https://keycloak.example.com/auth/realms/master"]
    consumer_match: true
    consumer_match_claim: "azp"
    consumer_match_ignore_not_found: true  # New field with default
    maximum_expiration: 0  # New expiration control
    cookie_names: []  # New authentication method
    uri_param_names: ["jwt"]  # Enhanced parameter support
```

**Prometheus Plugin**:

```yaml
# Kong 2.8.3 (basic configuration)
plugins:
- name: prometheus
  config:
    per_consumer: true

# Kong 3.9.1 (enhanced Deutsche Telekom version)
plugins:
- name: prometheus
  config:
    per_consumer: true
    status_code_metrics: true     # New Kong 3.9.1 feature
    latency_metrics: true         # New Kong 3.9.1 feature  
    bandwidth_metrics: true       # New Kong 3.9.1 feature
    upstream_health_metrics: true # New Kong 3.9.1 feature
    ai_metrics: true             # Kong 3.9.1 AI Gateway metrics
```

**Rate-Limiting-Merged Plugin**:

```yaml
# Kong 2.8.3 (Deutsche Telekom custom)
plugins:
- name: rate-limiting-merged
  config:
    policy: local
    fault_tolerant: true
    limits:
      consumer:
        minute: 60
      service:
        minute: 100

# Kong 3.9.1 (updated for new PDK)
plugins:
- name: rate-limiting-merged
  config:
    policy: local
    fault_tolerant: true
    hide_client_headers: false    # New header control
    omit_consumer: "gateway"      # New consumer omission feature
    limits:
      consumer:
        minute: 60
        hour: 1000               # Enhanced period support
      service:
        minute: 100
        hour: 2000
    redis_timeout: 2000          # New Redis configuration options
    redis_ssl: false
    redis_ssl_verify: false
```

**Zipkin Plugin**:

```yaml
# Kong 2.8.3 (basic Zipkin)
plugins:
- name: zipkin
  config:
    http_endpoint: "http://jaeger:14268/api/traces"
    sample_ratio: 1.0

# Kong 3.9.1 (enhanced Deutsche Telekom version)
plugins:
- name: zipkin
  config:
    http_endpoint: "http://jaeger:9411/api/v2/spans"  # Updated endpoint format
    sample_ratio: 1.0
    include_credential: true      # New credential inclusion
    traceid_byte_count: 16       # Configurable trace ID length
    default_service_name: "kong-gateway"  # Default service naming
    local_service_name: null     # Local component naming
    force_sample: null           # Sample override capability
    connect_timeout: 2000        # New timeout configurations
    send_timeout: 5000
    read_timeout: 5000
```

#### Actual Breaking Changes (Based on Kong Changelog Analysis)

**Major Breaking Changes from Kong 3.0.0**:

```yaml
# Route Path Handling (Kong 3.0+)
routes:
- name: example-route
  paths: ["/api/~.*"]  # Regex paths must start with "~" in Kong 3.x
  # Kong 2.x auto-detected regex, Kong 3.x requires explicit "~" prefix

# No plugin-level schema breaking changes found in changelog analysis
# Most Kong OSS plugins maintain backward compatibility
```

**Minor Breaking Changes**:

- **Session Plugin**: New `read_body_for_logout` field (default `false`) changes logout detection behavior
- **AI Proxy**: Anthropic upstream path changed (not relevant for most users)
- **Path Normalization**: `kong.request.get_path()` now normalizes paths (use `get_raw_path()` for raw)

#### 🚨 **Critical Plugin Execution Order Changes**

**Kong 2.8.3 Plugin Order**:

```
1. pre-function
2. zipkin (100000)
3. bot-detection
4. cors
5. session
6. acme
7. jwt
8. oauth2
9. key-auth
10. ldap-auth
11. basic-auth
12. hmac-auth
13. grpc-gateway
14. ip-restriction
15. request-size-limiting
16. acl
17. rate-limiting
18. response-ratelimiting
19. request-transformer
20. response-transformer
21. aws-lambda
22. azure-functions
23. proxy-cache
24. prometheus (13)
25. [logging plugins...]
```

**Kong 3.9.1 Plugin Order** (New plugins inserted):

```
1. pre-function
2. correlation-id         # ← NEW: Moved to early position
3. zipkin (100000)
4. bot-detection
5. cors
6. session
7. acme
8. jwt
9. oauth2
10. key-auth
11. ldap-auth
12. basic-auth
13. hmac-auth
14. grpc-gateway
15. ip-restriction
16. request-size-limiting
17. acl
18. rate-limiting
19. response-ratelimiting
20. request-transformer
21. response-transformer
22. redirect              # ← NEW
23. ai-request-transformer # ← NEW
24. ai-prompt-template     # ← NEW
25. ai-prompt-decorator    # ← NEW
26. ai-prompt-guard        # ← NEW
27. ai-proxy               # ← NEW
28. ai-response-transformer # ← NEW
29. standard-webhooks      # ← NEW
30. aws-lambda
31. azure-functions
32. proxy-cache
33. opentelemetry         # ← NEW
34. prometheus (13)
35. [logging plugins...]
```

**Deutsche Telekom Custom Plugin Priorities**:

```yaml
# Plugin execution order (higher PRIORITY = earlier execution)
jwt-keycloak: 1005          # Before core auth plugins
rate-limiting-merged: 900   # Before rate-limiting (901)
zipkin: 100000             # Very early (tracing)
prometheus: 13             # Late (metrics collection)
```

## Migration Strategies

### Strategy 1: Blue-Green Deployment (RECOMMENDED)

**Minimizes Downtime**: ~5-10 minutes for DNS/load balancer switching

#### Prerequisites

```bash
# Required infrastructure
- AWS Aurora PostgreSQL cluster with backup/restore capability
- Load balancer (ALB/NLB) with health checks
- Container orchestration (ECS/EKS/Docker Swarm)
- Monitoring and alerting system
```

#### Phase 1: Environment Preparation (1-2 days)

1. **Create Aurora Snapshot**

   ```bash
   # Create snapshot of current production database
   aws rds create-db-cluster-snapshot \
     --db-cluster-identifier gateway-kong-prod \
     --db-cluster-snapshot-identifier kong-2-8-3-pre-migration-$(date +%Y%m%d)
   ```

2. **Provision Green Environment**

   ```bash
   # Restore snapshot to new Aurora cluster
   aws rds restore-db-cluster-from-snapshot \
     --db-cluster-identifier gateway-kong-green \
     --snapshot-identifier kong-2-8-3-pre-migration-$(date +%Y%m%d)
   ```

3. **Deploy Kong 3.9.1 to Green Environment**

   ```bash
   # Use this repository's Kong 3.9.1 image
   docker pull your-registry/gateway-kong-image:3.9.1
   
   # Deploy to green environment (but don't start yet)
   docker-compose -f docker-compose.green.yml pull
   ```

#### Phase 2: Configuration Validation (1 day)

1. **Export Current Kong Configuration**

   ```bash
   # Export from Kong 2.8.3 (Blue environment)
   deck dump --kong-addr http://kong-blue:8001 \
     --output-file kong-2.8.3-config.yaml
   ```

2. **Transform Configuration for Kong 3.9.1**

   ```bash
   # Create configuration transformation script
   cat > scripts/transform-kong-config.sh << 'EOF'
   #!/bin/bash
   # Kong 2.8.3 → 3.9.1 Configuration Transformer
   
   INPUT_FILE="$1"
   
   # Handle regex route paths (Kong 3.x requires "~" prefix for regex)
   yq eval '
     (.routes[]?.paths[]?) |= (
       if (test("\\.|\\*|\\+|\\?|\\[|\\]|\\(|\\)|\\^|\\$") and (startswith("~") | not))
       then "~" + .
       else .
       end
     )
   ' "$INPUT_FILE" |
   
   # Note: Most plugin configurations are backward compatible
   # Only route path regex detection changed in Kong 3.x
   
   # Transform Deutsche Telekom custom plugins
   yq eval '
     (.plugins[] | select(.name == "jwt-keycloak").config) |= (
       .consumer_match_ignore_not_found = (.consumer_match_ignore_not_found // true) |
       .maximum_expiration = (.maximum_expiration // 0) |
       .cookie_names = (.cookie_names // []) |
       .uri_param_names = (.uri_param_names // ["jwt"])
     )
   ' |
   
   # Update Prometheus plugin with Kong 3.9.1 features
   yq eval '
     (.plugins[] | select(.name == "prometheus").config) |= (
       .status_code_metrics = (.status_code_metrics // true) |
       .latency_metrics = (.latency_metrics // true) |
       .bandwidth_metrics = (.bandwidth_metrics // true) |
       .upstream_health_metrics = (.upstream_health_metrics // true) |
       .ai_metrics = (.ai_metrics // true)
     )
   ' |
   
   # Update Zipkin plugin endpoint format
   yq eval '
     (.plugins[] | select(.name == "zipkin").config) |= (
       .http_endpoint = (.http_endpoint | sub("14268/api/traces"; "9411/api/v2/spans")) |
       .include_credential = (.include_credential // true) |
       .traceid_byte_count = (.traceid_byte_count // 16) |
       .default_service_name = (.default_service_name // "kong-gateway") |
       .connect_timeout = (.connect_timeout // 2000) |
       .send_timeout = (.send_timeout // 5000) |
       .read_timeout = (.read_timeout // 5000)
     )
   ' |
   
   # Update rate-limiting-merged with new fields
   yq eval '
     (.plugins[] | select(.name == "rate-limiting-merged").config) |= (
       .hide_client_headers = (.hide_client_headers // false) |
       .omit_consumer = (.omit_consumer // "gateway") |
       .redis_timeout = (.redis_timeout // 2000) |
       .redis_ssl = (.redis_ssl // false) |
       .redis_ssl_verify = (.redis_ssl_verify // false)
     )
   '
   EOF
   
   chmod +x scripts/transform-kong-config.sh
   
   # Execute transformation
   ./scripts/transform-kong-config.sh kong-2.8.3-config.yaml > kong-3.9.1-config.yaml
   ```

3. **Test Configuration Compatibility**

   ```bash
   # Test against Kong 3.9.1 in staging
   deck validate --kong-addr http://kong-green:8001 \
     --state kong-3.9.1-config.yaml
   ```

#### Phase 3: Database Migration (Maintenance Window - 10 minutes)

```bash
#!/bin/bash
# Migration script with rollback capability

set -e

echo "🚀 Starting Kong 2.8.3 → 3.9.1 migration"

# Step 1: Stop Kong 2.8.3 services (Blue)
echo "📴 Stopping Kong 2.8.3 services..."
docker-compose -f docker-compose.blue.yml down

# Step 2: Create final snapshot before migration
echo "📸 Creating final pre-migration snapshot..."
aws rds create-db-cluster-snapshot \
  --db-cluster-identifier gateway-kong-green \
  --db-cluster-snapshot-identifier kong-final-pre-migration-$(date +%Y%m%d-%H%M)

# Step 3: Run Kong 3.9.1 migrations
echo "🔄 Running Kong 3.9.1 database migrations..."
docker run --rm \
  -e KONG_DATABASE=postgres \
  -e KONG_PG_HOST=kong-green-aurora.cluster-xxx.region.rds.amazonaws.com \
  -e KONG_PG_DATABASE=kong \
  -e KONG_PG_USER=kong \
  -e KONG_PG_PASSWORD="$KONG_PG_PASSWORD" \
  your-registry/gateway-kong-image:3.9.1 \
  kong migrations bootstrap

# Step 4: Start Kong 3.9.1 services
echo "🚀 Starting Kong 3.9.1 services..."
docker-compose -f docker-compose.green.yml up -d

# Step 5: Health check
echo "🔍 Waiting for Kong 3.9.1 to be healthy..."
timeout 120 bash -c 'until curl -f http://kong-green:8001/status; do sleep 2; done'

# Step 6: Apply configuration
echo "⚙️ Applying Kong 3.9.1 configuration..."
deck sync --kong-addr http://kong-green:8001 \
  --state kong-3.9.1-config.yaml

# Step 7: Switch load balancer target
echo "🔄 Switching load balancer to Kong 3.9.1..."
# Update ALB target group or DNS CNAME
aws elbv2 modify-target-group \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --targets Id=kong-green-instance

echo "✅ Migration completed successfully!"
```

#### Rollback Plan

```bash
#!/bin/bash
# Rollback script in case of issues

echo "🔄 Rolling back to Kong 2.8.3..."

# Step 1: Switch load balancer back
aws elbv2 modify-target-group \
  --target-group-arn "$TARGET_GROUP_ARN" \
  --targets Id=kong-blue-instance

# Step 2: Restore database from snapshot
aws rds restore-db-cluster-from-snapshot \
  --db-cluster-identifier gateway-kong-prod \
  --snapshot-identifier kong-2-8-3-pre-migration-$(date +%Y%m%d) \
  --deletion-protection

# Step 3: Start Kong 2.8.3 services
docker-compose -f docker-compose.blue.yml up -d

echo "✅ Rollback completed - Kong 2.8.3 restored"
```

### Strategy 2: Rolling Update (NOT RECOMMENDED)

**Why Not Recommended**: Database incompatibility makes this approach risky and complex.

**Issues**:

- Cannot run Kong 2.8.3 and 3.9.1 against same database simultaneously
- Would require complex database replication setup
- Higher risk of data inconsistency

### Strategy 3: Maintenance Window Migration (FALLBACK)

**Downtime**: 30-60 minutes

If Blue-Green is not feasible:

```bash
# 1. Schedule maintenance window
# 2. Stop all Kong services
# 3. Backup database
# 4. Run migrations
# 5. Deploy Kong 3.9.1
# 6. Validate and restore service
```

## Pre-Migration Validation Checklist

### Infrastructure Requirements

- [ ] **AWS Aurora PostgreSQL**: Version compatibility verified
- [ ] **Container Registry**: Kong 3.9.1 image available
- [ ] **Load Balancer**: Health check configurations updated
- [ ] **Monitoring**: Alerting rules updated for Kong 3.9.1
- [ ] **Networking**: Security groups and VPC configurations reviewed

### Configuration Validation

- [ ] **Plugin Configurations**: All plugins validated against Kong 3.9.1 schemas
- [ ] **Custom Lua Scripts**: Compatibility with Kong 3.9.1 PDK verified
- [ ] **Environment Variables**: Kong 3.9.1 configuration options reviewed
- [ ] **TLS/SSL Certificates**: Certificate management approach confirmed
- [ ] **Rate Limiting Rules**: Rate-limiting-merged plugin configurations tested

### Deutsche Telekom Customizations

- [ ] **Prometheus Metrics**: O28M_ENI_LATENCY_BUCKETS functionality verified
- [ ] **Zipkin Tracing**: X-Tardis-Traceid header generation tested
- [ ] **JWT-Keycloak**: Consumer matching with azp claims validated
- [ ] **Rate-Limiting-Merged**: Multi-dimensional limiting functionality confirmed

### Plugin Execution Order Validation

- [ ] **Custom Plugin Priorities**: Verify Deutsche Telekom plugins execute in correct order
- [ ] **JWT-Keycloak Priority**: Confirm priority 1005 executes before core auth plugins
- [ ] **Rate-Limiting-Merged Priority**: Verify priority 900 executes before standard rate-limiting
- [ ] **Plugin Interaction Testing**: Test auth → rate limiting → transformation → logging flow
- [ ] **New Kong 3.9.1 Plugins**: Ensure AI and OpenTelemetry plugins don't interfere

**Critical Plugin Order Dependencies**:

```yaml
# Required execution sequence for Deutsche Telekom setup:
1. zipkin (100000)           # Trace ID generation first
2. jwt-keycloak (1005)       # Authentication before everything
3. acl                       # Authorization after authentication  
4. rate-limiting-merged (900) # Rate limiting after auth
5. request-transformer       # Transform requests after rate limiting
6. [upstream processing]
7. response-transformer      # Transform responses
8. prometheus (13)           # Metrics collection last
```

## Migration Testing Protocol

### Staging Environment Validation

```bash
# 1. Deploy Kong 3.9.1 to staging
docker-compose -f docker-compose.staging.yml up -d

# 2. Run comprehensive test suite
./tests/run_production_validation.sh

# 3. Performance testing
artillery run performance-test.yml

# 4. Load testing with realistic traffic patterns
k6 run load-test.js
```

### Critical Test Cases

1. **Authentication Flow**

   ```bash
   # Validate JWT-Keycloak with production Keycloak
   curl -H "Authorization: Bearer $PROD_JWT_TOKEN" \
     https://kong-staging/api/test
   ```

2. **Tracing Functionality**

   ```bash
   # Verify Tardis trace ID generation
   curl -H "X-Request-ID: test-$(date +%s)" \
     https://kong-staging/api/test \
     -v | grep X-Tardis-Traceid
   ```

3. **Rate Limiting**

   ```bash
   # Test rate limiting with production-like traffic
   for i in {1..100}; do
     curl https://kong-staging/api/test
   done | grep -c "X-RateLimit"
   ```

4. **Prometheus Metrics**

   ```bash
   # Validate enhanced consumer tracking
   curl https://kong-staging:8001/metrics | \
     grep 'consumer="production-consumer"'
   ```

## Post-Migration Validation

### Immediate Checks (First 30 minutes)

```bash
# Health status
curl -f http://kong:8001/status

# Plugin status
curl http://kong:8001/plugins/enabled | jq '.enabled_plugins'

# Database connectivity
curl http://kong:8001/ | jq '.configuration.database'

# Custom plugin loading
curl http://kong:8001/plugins | jq '.data[] | select(.name | contains("jwt-keycloak", "rate-limiting-merged"))'
```

### Extended Monitoring (First 24 hours)

- **Response Time Monitoring**: Compare latency percentiles with Kong 2.8.3 baseline
- **Error Rate Tracking**: Monitor 4xx/5xx response rates
- **Memory Usage**: Track memory consumption patterns
- **Database Performance**: Monitor Aurora PostgreSQL query performance
- **Custom Metrics**: Validate Deutsche Telekom specific metrics collection

## Risk Mitigation Strategies

### High-Risk Areas

1. **Database Migration Failures**
   - **Risk**: Corrupted database state during migration
   - **Mitigation**: Multiple backup snapshots, tested restore procedures
   - **Rollback**: Automated database restore from snapshot

2. **Plugin Configuration Incompatibilities**
   - **Risk**: Plugin configurations fail to load in Kong 3.9.1
   - **Mitigation**: Comprehensive staging validation, configuration transformation scripts
   - **Rollback**: Pre-validated Kong 2.8.3 configuration backup

3. **Performance Degradation**
   - **Risk**: Kong 3.9.1 performs worse than Kong 2.8.3
   - **Mitigation**: Load testing, gradual traffic ramping, performance baselines
   - **Rollback**: Immediate traffic switching to Kong 2.8.3

4. **Custom Plugin Failures**
   - **Risk**: Deutsche Telekom customizations don't work correctly
   - **Mitigation**: Extensive testing of all custom functionality
   - **Rollback**: Plugin-level rollback with configuration updates

### Monitoring and Alerting

```yaml
# CloudWatch/Grafana alerts
alerts:
  - name: kong_high_error_rate
    condition: error_rate > 5%
    duration: 2m
    action: alert_team
    
  - name: kong_high_latency
    condition: p95_latency > baseline * 1.5
    duration: 5m
    action: investigate
    
  - name: kong_plugin_failures
    condition: plugin_errors > 0
    duration: 1m
    action: immediate_alert
```

## Migration Timeline

### Week 1: Preparation

- [ ] Infrastructure provisioning
- [ ] Kong 3.9.1 image preparation
- [ ] Configuration validation scripts
- [ ] Staging environment setup

### Week 2: Testing

- [ ] Staging deployment and testing
- [ ] Performance baseline establishment
- [ ] Load testing execution
- [ ] Rollback procedure testing

### Week 3: Production Migration

- [ ] Final staging validation
- [ ] Production migration execution
- [ ] Post-migration monitoring
- [ ] Performance validation

### Week 4: Stabilization

- [ ] Extended monitoring
- [ ] Performance optimization
- [ ] Documentation updates
- [ ] Team training

## Emergency Contacts and Procedures

### Escalation Matrix

1. **Level 1**: DevOps Engineer (immediate response)
2. **Level 2**: Platform Architect (15 minutes)
3. **Level 3**: Engineering Manager (30 minutes)
4. **Level 4**: Deutsche Telekom Technical Lead (1 hour)

### Emergency Rollback Trigger

- Error rate > 10% for 5+ minutes
- Latency increase > 200% of baseline
- Any custom plugin complete failure
- Database connectivity issues

## Success Criteria

### Technical Success

- [ ] All services responding with < 2% error rate
- [ ] Latency within 20% of Kong 2.8.3 baseline
- [ ] All Deutsche Telekom customizations functional
- [ ] Zero data loss during migration

### Business Success

- [ ] No customer-impacting outages
- [ ] Monitoring and alerting operational
- [ ] Team trained on Kong 3.9.1 operations
- [ ] Documentation updated and accessible

---

**Migration Complexity**: HIGH  
**Estimated Downtime**: 5-10 minutes (Blue-Green) / 30-60 minutes (Maintenance Window)  
**Rollback Time**: < 15 minutes  
**Risk Level**: MEDIUM (with proper preparation and testing)

**Recommendation**: Proceed with Blue-Green deployment strategy after comprehensive staging validation.
