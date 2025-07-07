# Kong 3.9.1 Migration Testing Suite

## Overview

This document describes the comprehensive testing suite for the Kong 3.9.1 migration with Deutsche Telekom customizations. All tests use local services and have no external dependencies.

## Test Architecture

### Test Environment
- **Kong 3.9.1**: Latest Kong gateway with custom plugins
- **Local Keycloak (iris)**: Both HTTP and HTTPS endpoints for JWT authentication
- **Internal httpbin**: Go-based HTTP testing service
- **Jaeger**: Distributed tracing collection and UI
- **PostgreSQL**: Kong database backend

### Docker Test Infrastructure
```bash
# Run all tests
docker-compose run --rm tests

# Run tests with profile
docker-compose --profile testing up
```

## Test Scripts Structure

### Core Test Files
```
tests/
├── run_tests.sh              # Main test orchestrator
├── _env.sh                   # Environment setup and utilities
├── enabled_plugins.sh        # Plugin availability verification
└── quick_integration_test.sh # Comprehensive integration tests
```

### Certificate Management
Certificates are automatically generated using a multi-stage Docker build in `Dockerfile.iris`. No external certificate generation scripts are needed.

## Test Coverage

### Phase 1: Plugin Availability Tests
**Location**: `tests/enabled_plugins.sh`

**Tests**:
- ✅ `jwt-keycloak` plugin loaded and available
- ✅ `prometheus` plugin loaded and available  
- ✅ `rate-limiting-merged` plugin loaded and available
- ✅ `zipkin` plugin loaded and available

**Purpose**: Validates that all custom plugins compile and load correctly in Kong 3.9.1

### Phase 2: Integration Tests
**Location**: `tests/quick_integration_test.sh`

#### Test 1: Unauthorized Request Blocking
- **Purpose**: Verify JWT authentication is enforced
- **Test**: Request without Authorization header → HTTP 401
- **Validates**: JWT-Keycloak plugin authentication enforcement

#### Test 2: JWT Authentication Flow
- **Purpose**: End-to-end JWT authentication with local Keycloak
- **Test**: 
  1. Obtain JWT token from `iris:8080/auth/realms/master`
  2. Make authenticated request → HTTP 200
  3. Verify consumer matching via `azp` claim
- **Validates**: 
  - JWT token acquisition from local Keycloak
  - Consumer identification (`admin-cli` consumer)
  - Authentication flow with Kong 3.9.1 PDK

#### Test 3: Request Transformation
- **Purpose**: Verify custom header injection
- **Test**: Check for `X-Test-Plugin` header in response
- **Validates**: Request transformer plugin functionality

#### Test 4: Rate Limiting Functionality
- **Purpose**: Verify Deutsche Telekom rate limiting customizations
- **Test**: Check for rate limiting headers in responses
- **Validates**:
  - Rate-limiting-merged plugin execution
  - Header generation with limits and remaining counts
  - Multi-dimensional rate limiting (service + consumer)

#### Test 5: Prometheus Metrics Collection
- **Purpose**: Verify enhanced metrics with Deutsche Telekom customizations
- **Test**: Query `/metrics` endpoint for Kong metrics
- **Validates**:
  - Basic Kong metrics collection
  - Consumer tracking in metrics (per_consumer=true)
  - O28M latency buckets (50ms, 100ms, 500ms)
  - Enhanced consumer labeling for all metrics

#### Test 6: Multiple Request Processing
- **Purpose**: Test plugin stability under load
- **Test**: Send multiple authenticated requests rapidly
- **Validates**:
  - Plugin chain stability
  - Consumer metrics accumulation
  - Rate limiting accuracy

#### Test 7: Distributed Tracing
- **Purpose**: Verify Tardis tracing customizations
- **Test**: 
  1. Make request with custom headers
  2. Check for Tardis trace ID in response
  3. Verify trace delivery to Jaeger
- **Validates**:
  - Tardis trace ID generation (`worker_id + "#" + counter`)
  - Custom business context headers
  - Jaeger integration with "kong-gateway" service name

## Deutsche Telekom Customizations Tested

### Prometheus Plugin Customizations
- **O28M_ENI_LATENCY_BUCKETS**: Memory-optimized sub-1000ms buckets
- **HORIZON_CONSUMER**: Special Pubsub-Horizon consumer handling
- **Enhanced Consumer Tracking**: Consumer labels on all latency metrics
- **Yield Mechanisms**: Non-blocking metrics collection

### Rate-Limiting-Merged Plugin Customizations  
- **Multi-dimensional Limiting**: Separate service and consumer limits
- **Header Merging Logic**: Distributed gateway rate limit coordination
- **Consumer Omission**: Configurable consumer exclusion from limits
- **Minimum Logic**: Enhanced usage calculation for merged limits

### Zipkin Plugin Customizations
- **Tardis Trace ID**: Custom format with worker ID and counter
- **Business Context Headers**: x-request-id, x-business-context, x-correlation-id
- **Environment Detection**: From service tags pattern
- **Admin API Filtering**: Exclude /admin-api paths from tracing
- **Enhanced Balancer Tracking**: Per-try error analysis

### JWT-Keycloak Plugin
- **Consumer Matching**: `azp` claim to consumer mapping
- **Flexible Issuer Support**: Multiple allowed issuers
- **Claims Verification**: Configurable claim validation

## Running Tests

### Docker-based Tests (Recommended)
```bash
# Start all services
docker-compose up -d

# Run test suite
docker-compose run --rm tests

# View test results in real-time
docker-compose logs -f tests
```

### Manual Testing
```bash
# Start services (certificates auto-generated)
docker-compose up -d

# Access services directly
curl -k https://localhost:8443/auth/realms/master/.well-known/openid-configuration
curl http://localhost:8001/status
curl http://localhost:16686  # Jaeger UI
```

## Test Results Interpretation

### Success Indicators
- ✅ All plugins load without errors
- ✅ JWT authentication flow completes successfully
- ✅ Consumer matching works (`admin-cli` consumer identified)
- ✅ Rate limiting headers appear in responses
- ✅ Prometheus metrics include consumer labels
- ✅ Zipkin traces contain Tardis trace IDs
- ✅ Request transformation adds custom headers

### Common Issues and Solutions

#### JWT Token Issues
- **Issue**: Token acquisition fails
- **Solution**: Verify Keycloak is running and accessible at `iris:8080`
- **Check**: `curl http://iris:8080/auth/realms/master/.well-known/openid-configuration`

#### Rate Limiting Headers Missing
- **Issue**: No X-RateLimit headers in response
- **Solution**: Ensure rate-limiting-merged plugin is configured on route/service
- **Check**: Plugin execution order (rate limiting runs before authentication)

#### Consumer Tracking Missing
- **Issue**: Consumer metrics not visible in Prometheus
- **Solution**: Make authenticated requests to populate consumer data
- **Check**: Consumer matching is working properly

#### Zipkin Traces Missing
- **Issue**: No traces in Jaeger
- **Solution**: Verify Jaeger endpoint configuration and wait for trace propagation
- **Check**: Jaeger is accessible at `jaeger:14268` from Kong

## Test Maintenance

### Adding New Tests
1. Add test function to `quick_integration_test.sh`
2. Follow existing test pattern with clear success/failure indicators
3. Include validation of both functionality and Deutsche Telekom customizations

### Updating Test Configuration
1. Modify service configurations in `_env.sh`
2. Update test expectations in individual test functions
3. Ensure all customizations remain validated

## Performance Testing

While not included in the current suite, performance testing should validate:
- Rate limiting accuracy under high load
- Prometheus metrics collection latency impact  
- Zipkin trace sampling performance
- Consumer matching efficiency

## Security Testing

Security validation includes:
- JWT signature verification with Keycloak public keys
- ACL authorization enforcement
- Header sanitization in plugins
- Consumer isolation in rate limiting

---

**Test Suite Status**: ✅ Production Ready  
**Kong Version**: 3.9.1  
**Migration Status**: Complete with all Deutsche Telekom customizations preserved  
**Last Updated**: July 2025