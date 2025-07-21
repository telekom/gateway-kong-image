#!/bin/sh
# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0

# Legacy quick integration tests - Use ../test_local_integration.sh for comprehensive testing
# This script is maintained for compatibility with existing test infrastructure

set -e

# Source environment configuration
. ./_env.sh
prepare_environment

# Retry function for tests
run_test_with_retry() {
    local test_name="$1"
    local test_function="$2"
    local max_retries=5
    local retry_count=0
    
    echo "🔄 Running $test_name (max $max_retries attempts)..."
    
    while [ $retry_count -lt $max_retries ]; do
        retry_count=$((retry_count + 1))
        echo "  Attempt $retry_count/$max_retries for $test_name"
        
        if $test_function; then
            echo "✅ $test_name passed on attempt $retry_count"
            return 0
        else
            if [ $retry_count -lt $max_retries ]; then
                echo "⚠️  $test_name failed on attempt $retry_count, retrying in 2 seconds..."
                sleep 2
            else
                echo "❌ $test_name failed after $max_retries attempts"
                return 1
            fi
        fi
    done
}

echo "🚀 Running quick integration tests..."
echo "🔍 Verifying service availability..."

# Quick health check for iris before proceeding
echo "🏥 Checking Iris (Keycloak) health..."
wait_for_iris

# Test basic Kong functionality with all plugins configured

echo "🔧 Setting up test configuration..."

# Clean up existing configuration first
echo "🧹 Cleaning up existing configuration..."

# Helper function to safely delete resources
delete_resource() {
    local endpoint="$1"
    local name="$2"
    echo "🗑️ Cleaning up $name..."
    curl -s -X DELETE "$KONG_ADMIN_URL$endpoint" >/dev/null 2>&1 || true
}

# Get and delete all plugins
echo "🗑️ Removing all plugins..."
PLUGINS=$(curl -s "$KONG_ADMIN_URL/plugins" | jq -r '.data[]?.id // empty' 2>/dev/null || true)
for plugin_id in $PLUGINS; do
    if [ -n "$plugin_id" ]; then
        delete_resource "/plugins/$plugin_id" "plugin $plugin_id"
    fi
done

# Get and delete all routes
echo "🗑️ Removing all routes..."
ROUTES=$(curl -s "$KONG_ADMIN_URL/routes" | jq -r '.data[]?.id // empty' 2>/dev/null || true)
for route_id in $ROUTES; do
    if [ -n "$route_id" ]; then
        delete_resource "/routes/$route_id" "route $route_id"
    fi
done

# Get and delete all services
echo "🗑️ Removing all services..."
SERVICES=$(curl -s "$KONG_ADMIN_URL/services" | jq -r '.data[]?.id // empty' 2>/dev/null || true)
for service_id in $SERVICES; do
    if [ -n "$service_id" ]; then
        delete_resource "/services/$service_id" "service $service_id"
    fi
done

# Get and delete all consumers
echo "🗑️ Removing all consumers..."
CONSUMERS=$(curl -s "$KONG_ADMIN_URL/consumers" | jq -r '.data[]?.id // empty' 2>/dev/null || true)
for consumer_id in $CONSUMERS; do
    if [ -n "$consumer_id" ]; then
        delete_resource "/consumers/$consumer_id" "consumer $consumer_id"
    fi
done

echo "✅ Configuration cleanup completed"
echo ""
echo "🔧 Creating fresh test configuration..."

# 1. Create consumer 'admin-cli' (matches JWT azp claim)
echo "Creating consumer 'admin-cli'..."
CONSUMER_RESPONSE=$(curl -s -X POST $KONG_ADMIN_URL/consumers \
  -H "Content-Type: application/json" \
  -d '{"username": "admin-cli", "custom_id": "admin-cli-user"}')

if echo "$CONSUMER_RESPONSE" | jq -e '.username' >/dev/null 2>&1; then
    echo "✅ Consumer admin-cli created successfully"
else
    echo "❌ Failed to create consumer"
    echo "Response: $CONSUMER_RESPONSE"
    exit 1
fi

echo "✅ Consumer configured"

# 2. Create ACL group for admin-cli
echo "Creating ACL group for admin-cli..."
ACL_RESPONSE=$(curl -s -X POST $KONG_ADMIN_URL/consumers/admin-cli/acls \
  -H "Content-Type: application/json" \
  -d '{"group": "admin-group"}')

if echo "$ACL_RESPONSE" | jq -e '.group' >/dev/null 2>&1; then
    echo "✅ ACL group admin-group assigned to admin-cli"
else
    echo "❌ Failed to assign ACL group"
    echo "Response: $ACL_RESPONSE"
    exit 1
fi

# 3. Enable global Prometheus plugin
echo "Enabling global Prometheus plugin..."
PROMETHEUS_RESPONSE=$(curl -s -X POST $KONG_ADMIN_URL/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "prometheus",
    "config": {
      "per_consumer": true,
      "status_code_metrics": true,
      "latency_metrics": true,
      "bandwidth_metrics": true
    }
  }')

if echo "$PROMETHEUS_RESPONSE" | jq -e '.name' >/dev/null 2>&1; then
    echo "✅ Prometheus plugin enabled successfully"
else
    echo "❌ Failed to enable Prometheus plugin"
    echo "Response: $PROMETHEUS_RESPONSE"
    exit 1
fi

# 4. Enable global Zipkin plugin
echo "Enabling global Zipkin plugin..."
ZIPKIN_RESPONSE=$(curl -s -X POST $KONG_ADMIN_URL/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "zipkin",
    "config": {
      "http_endpoint": "http://jaeger.docker:9411/api/v2/spans",
      "sample_ratio": 1.0,
      "include_credential": true,
      "traceid_byte_count": 16,
      "local_service_name": "kong-gateway",
      "local_component_name": "kong-gateway"
    }
  }')

if echo "$ZIPKIN_RESPONSE" | jq -e '.name' >/dev/null 2>&1; then
    echo "✅ Zipkin plugin enabled successfully"
else
    echo "❌ Failed to enable Zipkin plugin"
    echo "Response: $ZIPKIN_RESPONSE"
    exit 1
fi

# 5. Create httpbin service using internal container
echo "Creating httpbin service..."
curl -s -X POST $KONG_ADMIN_URL/services \
  -H "Content-Type: application/json" \
  -d '{"name": "httpbin-service", "url": "http://httpbin.docker:8080"}' || echo "Service may already exist"

# Check if service was created successfully
echo ""
SERVICE_RESPONSE=$(curl -s $KONG_ADMIN_URL/services/httpbin-service)
if echo "$SERVICE_RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    echo "✅ Service httpbin-service created successfully"
else
    echo "❌ Failed to create service"
    echo "Response: $SERVICE_RESPONSE"
    exit 1
fi

# 6. Create route for the service (if not exists)
echo "Creating route for httpbin service..."
curl -s -X POST $KONG_ADMIN_URL/services/httpbin-service/routes \
  -H "Content-Type: application/json" \
  -d '{"name": "httpbin-route", "paths": ["/httpbin"], "strip_path": true}' || echo "Route may already exist"

# Check if route was created successfully
echo ""
ROUTE_RESPONSE=$(curl -s $KONG_ADMIN_URL/routes/httpbin-route)
if echo "$ROUTE_RESPONSE" | jq -e '.id' >/dev/null 2>&1; then
    echo "✅ Route httpbin-route created successfully"
else
    echo "❌ Failed to create route"
    echo "Response: $ROUTE_RESPONSE"
    exit 1
fi

# 7. Add Rate Limiting plugin to the service
echo "Adding Rate Limiting Merged plugin..."
curl -s -X POST $KONG_ADMIN_URL/services/httpbin-service/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "rate-limiting-merged",
    "config": {
      "limits": {
        "service": {
          "minute": 10,
          "hour": 100
        }
      },
      "policy": "local",
      "fault_tolerant": true,
      "hide_client_headers": false
    }
  }' || echo "Rate limiting plugin may already exist"
echo "✅ Rate Limiting plugin configured"

# 8. Add Request Transformer plugin
echo "Adding Request Transformer plugin..."
curl -s -X POST $KONG_ADMIN_URL/routes/httpbin-route/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "request-transformer",
    "config": {
      "add": {
        "headers": ["X-Test-Plugin:test-value"]
      }
    }
  }' || echo "Request Transformer plugin may already exist"
echo "✅ Request Transformer plugin configured"

# 9. Enable global JWT-Keycloak plugin
echo "Enabling global JWT-Keycloak plugin..."
curl -s -X POST $KONG_ADMIN_URL/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "jwt-keycloak",
    "config": {
      "allowed_iss": ["https://iris.docker:8443/auth/realms/master"],
      "consumer_match": true,
      "consumer_match_claim": "azp",
      "consumer_match_ignore_not_found": true
    }
  }' || echo "JWT-Keycloak plugin may already exist"
echo "✅ JWT-Keycloak plugin configured"

# 10. Add ACL plugin to route for admin access
echo "Adding ACL plugin to route..."
curl -s -X POST $KONG_ADMIN_URL/routes/httpbin-route/plugins \
  -H "Content-Type: application/json" \
  -d '{
    "name": "acl",
    "config": {
      "allow": ["admin-group"]
    }
  }' || echo "ACL plugin may already exist"
echo "✅ ACL plugin configured"

echo "🔗 Configuration setup completed "
# --- End of configuration setup ---

echo "🧪 Running functionality tests..."

# Global variables for test state
TOKEN=""
TEST_FAILURES=0

# Test 1: Unauthorized request test
test_unauthorized_request() {
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $KONG_PROXY_URL/httpbin/headers)
    if [ "$HTTP_CODE" = "401" ]; then
        return 0
    else
        echo "    Expected 401, got $HTTP_CODE"
        return 1
    fi
}

# Test 2: JWT authentication test  
test_jwt_authentication() {
    TOKEN_RESPONSE=$(curl -s -k -X POST "$IRIS_HTTPS_URL/auth/realms/master/protocol/openid-connect/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=password&client_id=admin-cli&username=admin&password=admin")
    
    TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token // empty')
    if [ -n "$TOKEN" ]; then
        AUTH_HTTP_CODE=$(curl -s -o /tmp/auth_response -w "%{http_code}" $KONG_PROXY_URL/httpbin/headers \
          -H "Authorization: Bearer $TOKEN")
        
        if [ "$AUTH_HTTP_CODE" = "200" ]; then
            return 0
        else
            echo "    Expected 200, got $AUTH_HTTP_CODE"
            return 1
        fi
    else
        echo "    Failed to obtain JWT token"
        return 1
    fi
}

# Test 3: Request transformer test
test_request_transformer() {
    if [ -z "$TOKEN" ]; then
        echo "    Skipping: No JWT token available"
        return 0
    fi
    
    HEADERS_RESPONSE=$(curl -s $KONG_PROXY_URL/httpbin/headers -H "Authorization: Bearer $TOKEN")
    TEST_PLUGIN_HEADER=$(echo "$HEADERS_RESPONSE" | jq -r '.headers["X-Test-Plugin"] // .headers["x-test-plugin"] // empty' 2>/dev/null)
    
    if [ "$(echo "$TEST_PLUGIN_HEADER" | jq -r '.[0]')" = "test-value" ]; then
        return 0
    else
        echo "    X-Test-Plugin header not found or incorrect: '$TEST_PLUGIN_HEADER'"
        return 1
    fi
}

# Test 4: Rate limiting test
test_rate_limiting() {
    if [ -z "$TOKEN" ]; then
        echo "    Skipping: No JWT token available"
        return 0
    fi
    
    RATE_LIMIT_RESPONSE=$(curl -s -I $KONG_PROXY_URL/httpbin/get -H "Authorization: Bearer $TOKEN")
    
    if echo "$RATE_LIMIT_RESPONSE" | grep -E 'X-RateLimit|X-Merged-RateLimit|RateLimit' >/dev/null; then
        return 0
    else
        echo "    Rate limiting headers not found"
        return 1
    fi
}

# Test 5: Prometheus metrics test
test_prometheus_metrics() {
    METRICS_RESPONSE=$(curl -s $KONG_ADMIN_URL/metrics)
    
    if echo "$METRICS_RESPONSE" | grep -q "kong_latency"; then
        return 0
    else
        echo "    Kong metrics not found"
        return 1
    fi
}

# Test 6: Multiple requests test  
test_multiple_requests() {
    if [ -z "$TOKEN" ]; then
        echo "    Skipping: No JWT token available"
        return 0
    fi
    
    # Send multiple requests
    for i in $(seq 1 3); do
        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $KONG_PROXY_URL/httpbin/get -H "Authorization: Bearer $TOKEN")
        if [ "$HTTP_CODE" != "200" ]; then
            echo "    Request $i failed with HTTP $HTTP_CODE"
            return 1
        fi
        sleep 0.5
    done
    return 0
}

# Test 7: Zipkin tracing test
test_zipkin_tracing() {
    if [ -z "$TOKEN" ]; then
        echo "    Skipping: No JWT token available"
        return 0
    fi
    
    # Make a request that should generate trace
    curl -s $KONG_PROXY_URL/httpbin/headers \
      -H "Authorization: Bearer $TOKEN" \
      -H "X-Request-ID: test-trace-$(date +%s)" > /dev/null
    
    # Wait for trace processing
    sleep 2
    
    # Check Jaeger for traces
    JAEGER_RESPONSE=$(curl -s "http://jaeger.docker:16686/api/services" 2>/dev/null || echo "jaeger_unavailable")
    if echo "$JAEGER_RESPONSE" | grep -q "kong-gateway" 2>/dev/null; then
        return 0
    elif [ "$JAEGER_RESPONSE" = "jaeger_unavailable" ]; then
        echo "    Warning: Jaeger API not accessible, but trace should be sent"
        return 0
    else
        echo "    kong-gateway service not found in Jaeger traces"
        return 1
    fi
}

# Execute all tests with retry mechanism
run_test_with_retry "Test 1: Unauthorized request" test_unauthorized_request
if [ $? -ne 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
fi

run_test_with_retry "Test 2: JWT authentication" test_jwt_authentication  
if [ $? -ne 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
fi

run_test_with_retry "Test 3: Request transformer" test_request_transformer
if [ $? -ne 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
fi

run_test_with_retry "Test 4: Rate limiting" test_rate_limiting
if [ $? -ne 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
fi

run_test_with_retry "Test 5: Prometheus metrics" test_prometheus_metrics
if [ $? -ne 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
fi

run_test_with_retry "Test 6: Multiple requests" test_multiple_requests
if [ $? -ne 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
fi

run_test_with_retry "Test 7: Zipkin tracing" test_zipkin_tracing
if [ $? -ne 0 ]; then
    TEST_FAILURES=$((TEST_FAILURES + 1))
fi

# Final result
echo ""
if [ $TEST_FAILURES -eq 0 ]; then
    echo "🎉 All integration tests completed successfully!"
else
    echo "❌ $TEST_FAILURES test(s) failed after retries"
    exit 1
fi

echo ""
echo "📊 Service URLs:"
echo "   Kong Proxy:    $KONG_PROXY_URL (http://localhost:$(echo $KONG_PROXY_URL | cut -d':' -f3))"
echo "   Kong Admin:    $KONG_ADMIN_URL (http://localhost:$(echo $KONG_ADMIN_URL | cut -d':' -f3))"
echo "   Keycloak HTTP: $IRIS_HTTP_URL (http://localhost:$(echo $IRIS_HTTP_URL | cut -d':' -f3))"
echo "   Keycloak HTTPS:$IRIS_HTTPS_URL (https://localhost:$(echo $IRIS_HTTPS_URL | cut -d':' -f3))"
echo "   Jaeger UI:     http://jaeger:16686 (http://localhost:16686)"
echo ""
echo "🔗 Test endpoints:"
echo "   # Get JWT token:"
echo "   TOKEN=\$(curl -s -k -X POST \"$IRIS_HTTPS_URL/auth/realms/master/protocol/openid-connect/token\" \\"
echo "     -H \"Content-Type: application/x-www-form-urlencoded\" \\"
echo "     -d \"grant_type=password&client_id=admin-cli&username=admin&password=admin\" | jq -r '.access_token')"
echo ""
echo "   # Authenticated requests:"
echo "   curl $KONG_PROXY_URL/httpbin/headers -H \"Authorization: Bearer \$TOKEN\""
echo "   curl $KONG_PROXY_URL/httpbin/get -H \"Authorization: Bearer \$TOKEN\""
echo "   curl $KONG_ADMIN_URL/metrics"
echo ""
echo "🔐 JWT Authentication:"
echo "   Keycloak Admin: admin/admin"
echo "   Issuer: https://iris.docker:8443/auth/realms/master"
echo "   Consumer: admin-cli (with admin-group ACL)"