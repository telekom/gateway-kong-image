# Kong 2.8.3 to 3.9.1 Migration Analysis

## Executive Summary

This document provides a comprehensive analysis of the migration path from Kong 2.8.3 to Kong 3.9.1, with specific focus on breaking changes affecting the Admin API, plugins used by Tardis Stargate Kong, and general Kong infrastructure. The migration represents a significant architectural evolution requiring careful planning and testing.

**Key Findings:**
- **AI Gateway Revolution**: Kong 3.9.1 introduces comprehensive AI capabilities absent in 2.8.3
- **WebAssembly Support**: Native Wasm filter integration for enhanced extensibility
- **Router Evolution**: New expressions-based router with significant performance improvements
- **Security Enhancements**: OpenSSL 3.2 with stricter security requirements
- **Build System Modernization**: Complete migration from Makefiles to Bazel
- **Tardis Plugin Challenges**: All four custom plugins require significant updates

---

## 1. Kong Core Architecture Comparison

### Kong 2.8.3 (Legacy LTS)
- **Version**: 2.8.3 (November 2022, LTS)
- **Build System**: Traditional Makefile-based build
- **Router**: Single traditional router (`router.lua`)
- **Nginx**: 1.19.3.1 to 1.19.9.1
- **OpenSSL**: Legacy versions with security level 1
- **Plugin Count**: 38 built-in plugins
- **Key Features**:
  - Stable hybrid mode (Control Plane/Data Plane)
  - DB-less mode support
  - Multiple database support (PostgreSQL, Cassandra)
  - Comprehensive plugin ecosystem
  - Enterprise-ready clustering

### Kong 3.9.1 (Modern Architecture)
- **Version**: 3.9.1 (Latest stable)
- **Build System**: Bazel-based with MODULE.bazel
- **Router**: Multi-flavor router system (traditional, expressions, ATC)
- **Nginx**: 1.25.3.2 (significantly newer)
- **OpenSSL**: 3.2.3 with security level 2
- **Plugin Count**: 46+ built-in plugins (including AI suite)
- **Revolutionary Features**:
  - **AI Gateway**: Complete LLM integration (OpenAI, Anthropic, AWS Bedrock, etc.)
  - **WebAssembly Filters**: Native Wasm extension support
  - **Expression Router**: Advanced DSL-based routing with 2x performance
  - **Enhanced Observability**: OpenTelemetry, advanced tracing
  - **Modern Security**: Stricter cryptographic requirements

---

## 2. Admin API Breaking Changes

### New Endpoints in Kong 3.9.1

#### Debug and Monitoring
- **`/debug/node/log-level`** - Dynamic log level management
- **`/debug/cluster/log-level/:log_level`** - Cluster-wide log control
- **`/status/dns`** - DNS client statistics

#### WebAssembly Management
- **`/filter-chains`** - Wasm filter chain CRUD operations
- **`/routes/:routes/filter-chains`** - Route-specific filter management
- **`/services/:services/filter-chains`** - Service-specific filter management
- **`/routes/:routes/filters/enabled|disabled|all`** - Filter status management

#### Enhanced Security
- **`/keys`** - Cryptographic key management
- **`/key-sets`** - Key set management for advanced authentication

### Modified Existing Endpoints

#### Critical Breaking Changes
1. **Vaults API**: `/vaults-beta` → `/vaults` (entity name change)
2. **Plugin Endpoint Keys**: Now uses `instance_name` instead of default `id/name`
3. **Services TLS Validation**: Expanded to cover both HTTPS and TLS protocols
4. **Routes Schema**: Completely rewritten for expressions support

#### Enhanced Features
- **CORS Support**: Built-in CORS handling for Admin API
- **Error Handling**: Improved error codes and responses
- **Schema Validation**: Enhanced validation with better documentation

---

## 3. Plugin Ecosystem Analysis

### Tardis Stargate Kong Custom Plugins

Kong 3.9.1 migration presents significant challenges for all four Tardis custom plugins:

#### 3.1 JWT-Keycloak Plugin
- **Status**: ❌ **CRITICAL** - Implementation missing from repository
- **Functionality**: Keycloak integration with role-based authorization
- **Migration Complexity**: **High** (3-4 weeks estimated)
- **Issues**:
  - Empty plugin directory - source code unavailable
  - Kong 3.9.1 JWT plugin has enhanced security features
  - Schema validation patterns changed
  - PDK API compatibility unknown

#### 3.2 Prometheus Plugin
- **Status**: ⚠️ **MEDIUM IMPACT** - Significant customizations
- **Current Customizations**:
  - Telekom-specific latency buckets for memory optimization
  - Special Pubsub-Horizon consumer handling
  - Enhanced consumer labeling with anonymous fallback
- **Migration Complexity**: **Medium** (1-2 weeks estimated)
- **Kong 3.9.1 Changes**:
  - Built-in prometheus plugin has new `configure()` method
  - Enhanced metric collection capabilities
  - New performance optimizations
- **Recommendation**: Extend Kong 3.9.1 plugin with custom features

#### 3.3 Rate-Limiting-Merged Plugin
- **Status**: ⚠️ **HIGH IMPACT** - Complex business logic
- **Current Features**:
  - Multi-dimensional rate limiting (service + consumer)
  - Header merging from multiple gateways
  - Consumer omission capabilities
  - Period-based limit validation
- **Migration Complexity**: **High** (2-3 weeks estimated)
- **Kong 3.9.1 Challenges**:
  - New PDK private APIs (`pdk.private.rate_limiting`)
  - Enhanced rate limiting architecture
  - Different sync mechanisms
  - Policy API changes

#### 3.4 Zipkin Plugin
- **Status**: ⚠️ **HIGH IMPACT** - Extensive Telekom customizations
- **Current Customizations**:
  - Tardis-specific trace ID generation
  - Business context header support
  - Environment detection from service tags
  - Admin API path filtering
  - Enhanced balancer tracking
- **Migration Complexity**: **High** (2-3 weeks estimated)
- **Kong 3.9.1 Changes**:
  - New observability framework (`kong.observability.tracing`)
  - Different reporter initialization
  - Refactored propagation logic
  - Updated span handling

### Standard Plugin Changes

#### 3.5 Request Transformer Plugin
- **Status**: ✅ **FULLY COMPATIBLE**
- **Changes**: Minor internal improvements, no breaking changes
- **Migration**: No action required

#### 3.6 ACL Plugin  
- **Status**: ✅ **MOSTLY COMPATIBLE**
- **Changes**: 
  - New `always_use_authenticated_groups` option
  - `blacklist`/`whitelist` → `deny`/`allow` (deprecated fields removed)
- **Migration**: Simple configuration field rename required

#### 3.7 IP Restriction Plugin
- **Status**: ✅ **COMPATIBLE WITH ENHANCEMENTS**
- **Changes**:
  - LRU cache for IP matchers (512 entries, 3600s TTL)
  - TCP/TLS protocol support via `preread` phase
  - `blacklist`/`whitelist` → `deny`/`allow`
- **Migration**: Configuration field rename + automatic performance improvement

---

## 4. Database Schema and Migration Requirements

### Migration Prerequisites
- **Minimum Version**: Must be on Kong 2.8.x before upgrading to 3.x
- **Database Requirements**: PostgreSQL 12+ recommended
- **Cassandra**: Deprecated - removal planned for Kong 4.0

### Schema Changes
```sql
-- New tables in Kong 3.9.1
CREATE TABLE filter_chains (...);  -- WebAssembly filter chains
CREATE TABLE keys (...);           -- Enhanced key management
CREATE TABLE key_sets (...);       -- Key set management

-- Enhanced existing tables
ALTER TABLE plugins ADD COLUMN instance_name TEXT;
ALTER TABLE plugins ADD COLUMN updated_at TIMESTAMP;
-- Multiple other enhancements...
```

### Migration Process
```bash
# 1. Complete backup
pg_dump kong > kong_2.8.3_backup.sql

# 2. Install Kong 3.9.1 
sudo dpkg -i kong-3.9.1.deb

# 3. Run migrations (DO NOT START KONG YET)
kong migrations up

# 4. Start Kong 3.9.1
kong start

# 5. Complete migration (after validation)
kong migrations finish
```

---

## 5. Configuration Breaking Changes

### New Configuration Options (Kong 3.9.1)
```yaml
# Router configuration
router_flavor: traditional_compatible  # traditional, expressions, traditional_compatible

# WebAssembly support
wasm: off                              # Enable Wasm filters
wasm_filters_path: /usr/local/kong/    # Wasm modules directory
wasm_filters: bundled,user             # Available filter types

# Enhanced security
ssl_session_cache_size: 10m            # Session cache optimization

# Observability
tracing_instrumentations: off          # Replaces opentelemetry_tracing
```

### Deprecated/Changed Options
- `node_id` → Deprecated in Kong 3.9.0
- `opentelemetry_tracing` → Use `tracing_instrumentations`  
- `vaults: off` → Default changed to `bundled`

### Security Configuration Changes
- **OpenSSL Security Level**: Increased from 1 to 2
  - RSA/DSA/DH keys must be ≥ 2048 bits
  - ECC keys must be ≥ 224 bits
  - RC4 cipher suites prohibited
  - SSL version 3 disabled

---

## 6. Migration Strategy and Timeline

### Recommended Migration Phases

#### Phase 1: Preparation (3-4 weeks)
- [ ] **Certificate Audit**: Ensure all certificates meet OpenSSL 3.2 security level 2
- [ ] **Build System Migration**: Adopt Bazel toolchain for CI/CD
- [ ] **Plugin Assessment**: Evaluate all four Tardis custom plugins
- [ ] **Environment Setup**: Configure Kong 3.9.1 in isolated test environment
- [ ] **Performance Baseline**: Document current Kong 2.8.3 performance metrics

#### Phase 2: Plugin Migration (4-6 weeks - parallel with Phase 1)
- [ ] **JWT-Keycloak**: Implement missing plugin or find external source
- [ ] **Prometheus**: Extend Kong 3.9.1 plugin with Telekom customizations
- [ ] **Rate-Limiting-Merged**: Refactor for new PDK APIs
- [ ] **Zipkin**: Migrate to new observability framework
- [ ] **Testing**: Comprehensive plugin integration testing

#### Phase 3: Staging Migration (2 weeks)
- [ ] **Staging Deployment**: Full Kong 3.9.1 deployment in staging
- [ ] **Integration Testing**: End-to-end service validation
- [ ] **Performance Testing**: Load testing with production-like traffic
- [ ] **Rollback Testing**: Validate rollback procedures

#### Phase 4: Production Migration (1-2 weeks)
- [ ] **Blue-Green Deployment**: Parallel Kong 3.9.1 infrastructure
- [ ] **Gradual Traffic Migration**: Incremental traffic shift
- [ ] **Monitoring**: Intensive monitoring for 48+ hours
- [ ] **Validation**: Complete functional and performance validation

### Effort Estimation

| Component | Complexity | Estimated Effort | Risk Level |
|-----------|------------|------------------|------------|
| JWT-Keycloak Plugin | High | 3-4 weeks | High |
| Prometheus Plugin | Medium | 1-2 weeks | Medium |
| Rate-Limiting Plugin | High | 2-3 weeks | High |
| Zipkin Plugin | High | 2-3 weeks | High |
| Infrastructure Migration | Medium | 2-3 weeks | Medium |
| Testing & Validation | High | 2-3 weeks | Medium |

**Total Estimated Effort**: 12-18 weeks for complete migration

---

## 7. Risk Assessment and Mitigation

### High-Risk Areas

#### 1. Tardis Custom Plugins
- **Risk**: Four plugins require significant updates
- **Impact**: Core Telekom functionality affected
- **Mitigation**: 
  - Start plugin migration immediately
  - Consider phased approach per plugin
  - Maintain Kong 2.8.3 compatibility during transition

#### 2. Security Configuration Changes
- **Risk**: OpenSSL 3.2 security level 2 requirements
- **Impact**: Weak certificates/configs will fail
- **Mitigation**:
  - Complete certificate audit before migration
  - Test all SSL/TLS configurations
  - Prepare certificate upgrade plan

#### 3. Router Behavior Changes
- **Risk**: Expression router may handle edge cases differently
- **Impact**: Traffic routing disruption
- **Mitigation**:
  - Use `traditional_compatible` mode initially
  - Comprehensive route testing
  - Gradual migration to expressions router

### Medium-Risk Areas

#### 1. Performance Changes
- **Risk**: New features may impact performance
- **Impact**: Latency increases, resource consumption
- **Mitigation**:
  - Establish performance baselines
  - Load testing in staging
  - Resource planning for new features

#### 2. Admin API Changes
- **Risk**: API client compatibility issues
- **Impact**: Management tool disruption
- **Mitigation**:
  - Update all API clients
  - Test automation tools
  - API versioning strategy

### Low-Risk Areas

#### 1. Standard Plugin Migration
- **Risk**: Minor configuration changes needed
- **Impact**: Limited functionality disruption
- **Mitigation**: Simple configuration updates

---

## 8. Testing Strategy

### Comprehensive Testing Framework

#### Unit Testing
- [ ] All custom plugin functionality
- [ ] Configuration parsing and validation
- [ ] Database operations and migrations
- [ ] SSL/TLS certificate validation

#### Integration Testing
- [ ] End-to-end request flows
- [ ] Authentication and authorization chains
- [ ] Plugin interaction and execution order
- [ ] Admin API operations

#### Performance Testing
- [ ] Baseline performance comparison
- [ ] Load testing with production patterns
- [ ] Memory usage and garbage collection
- [ ] Database connection efficiency

#### Security Testing
- [ ] Certificate validation with security level 2
- [ ] Plugin security boundaries
- [ ] Admin API access controls
- [ ] Vault integration security

### Testing Checklist
```bash
# Configuration validation
kong check kong.conf
kong start --dry-run

# Basic connectivity
curl -i http://kong:8000/health
curl -i https://kong:8443/health

# Admin API
curl -i http://kong:8001/status
curl -i http://kong:8001/plugins

# Custom plugin testing
curl -i http://kong:8000/test-endpoint \
  -H "Authorization: Bearer <jwt-token>"

# Performance baseline
ab -n 1000 -c 10 http://kong:8000/endpoint
```

---

## 9. Rollback Strategy

### Emergency Rollback Procedure
```bash
# 1. Stop Kong 3.9.1 cluster
kong stop

# 2. Restore Kong 2.8.3 infrastructure (must be ready)
# 3. Database rollback (if needed)
psql kong < kong_2.8.3_backup.sql

# 4. Start Kong 2.8.3
kong start -c kong_2.8.3.conf

# 5. Validate functionality
curl -i http://kong-2-8-3:8001/status
```

### Rollback Considerations
- Database migrations may not be reversible
- Maintain Kong 2.8.3 infrastructure during migration period
- Monitor for 48+ hours before decommissioning old version
- Document all configuration changes for quick reference

---

## 10. Recommendations and Next Steps

### Immediate Actions (Week 1-2)
1. **Certificate Audit**: Inventory and validate all certificates against OpenSSL 3.2 requirements
2. **Plugin Source Recovery**: Locate jwt-keycloak plugin source code or external implementation
3. **Environment Setup**: Establish Kong 3.9.1 development/test environment
4. **Team Training**: Begin Bazel build system training for development teams

### Short-term Actions (Month 1)
1. **Plugin Migration Start**: Begin updating Tardis custom plugins
2. **CI/CD Updates**: Migrate build pipelines to Bazel
3. **Documentation**: Create migration-specific documentation and runbooks
4. **Testing Framework**: Establish comprehensive testing infrastructure

### Medium-term Actions (Month 2-3)
1. **Staging Migration**: Complete staging environment migration
2. **Integration Testing**: Execute full integration test suite
3. **Performance Validation**: Complete performance testing and optimization
4. **Production Planning**: Finalize production migration strategy

### Long-term Considerations
1. **AI Integration**: Explore Kong 3.9.1 AI gateway capabilities for future enhancements
2. **WebAssembly Adoption**: Consider custom Wasm filters for specialized functionality
3. **Observability Enhancement**: Leverage OpenTelemetry for improved monitoring
4. **Cassandra Migration**: Plan for Cassandra deprecation in Kong 4.0

---

## Conclusion

The migration from Kong 2.8.3 to 3.9.1 represents a significant architectural evolution that brings substantial benefits in AI integration, WebAssembly extensibility, routing performance, and observability. However, the migration requires careful planning due to:

1. **Four custom Tardis plugins** requiring substantial updates
2. **Security configuration changes** from OpenSSL 3.2
3. **Build system modernization** to Bazel
4. **Admin API evolution** with new endpoints and schemas

**Success factors:**
- Methodical preparation and testing
- Early plugin migration start
- Comprehensive rollback planning  
- Gradual production migration
- Intensive monitoring during transition

**Estimated timeline**: 12-18 weeks for complete migration including thorough testing

The investment in migration will provide Deutsche Telekom with a modern, AI-ready API gateway platform positioned for future growth and enhanced functionality.