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
      "http_endpoint": "http://jaeger:9411/api/v2/spans",
      "sample_ratio": 1.0,
      "include_credential": true,
      "traceid_byte_count": 16,
      "local_service_name": "kong-gateway"
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
  -d '{"name": "httpbin-service", "url": "http://httpbin:8080"}' || echo "Service may already exist"

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
      "allowed_iss": ["https://iris:8443/auth/realms/master"],
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

# Test 1: Test unauthorized request (should be blocked by JWT)
echo "Test 1: Unauthorized request test..."
for i in $(seq 1 10); do
  echo "Attempt $i: Testing unauthorized request..."
  # Make an unauthorized request to httpbin
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $KONG_PROXY_URL/httpbin/headers)
  if [ "$HTTP_CODE" = "401" ]; then
    echo "✅ Unauthorized request blocked (HTTP $HTTP_CODE)"
    break
  else
    echo "❌ Unauthorized request failed: Expected 401, got $HTTP_CODE"
    if [ $i -eq 10 ]; then
      echo "❌ Test 1 failed: Unauthorized request did not return 401 after 10 attempts"
      exit 1
    fi
    sleep 1
  fi
done

# Test 2: Get JWT token from Keycloak and test authorized request
echo "Test 2: JWT authentication test..."
echo "Getting JWT token from Keycloak..."
TOKEN_RESPONSE=$(curl -s -k -X POST "$IRIS_HTTPS_URL/auth/realms/master/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password&client_id=admin-cli&username=admin&password=admin")

if echo "$TOKEN_RESPONSE" | jq -e '.access_token' > /dev/null 2>&1; then
  echo "✅ JWT token obtained from Keycloak"
  TOKEN=$(echo "$TOKEN_RESPONSE" | jq -r '.access_token')
  
  # Test authorized request with JWT token
  echo "Testing authorized request with JWT token..."
  AUTH_HTTP_CODE=$(curl -s -o /tmp/auth_response -w "%{http_code}" $KONG_PROXY_URL/httpbin/headers \
    -H "Authorization: Bearer $TOKEN")
  
  if [ "$AUTH_HTTP_CODE" = "200" ]; then
    echo "✅ Test 2 passed: Authorized request successful (HTTP $AUTH_HTTP_CODE)"
  else
    echo "❌ Test 2 failed: Expected 200, got $AUTH_HTTP_CODE"
    echo "Response: $(cat /tmp/auth_response 2>/dev/null || echo 'No response content')"
    exit 1
  fi
else
  echo "❌ Test 2 failed: Could not obtain JWT token from Keycloak"
  echo "Response: $TOKEN_RESPONSE"
  exit 1
fi

# Test 3: Check if headers are added by request transformer (with JWT token)
echo "Test 3: Checking request transformer with JWT..."
if [ -n "$TOKEN" ]; then
  HEADERS_RESPONSE=$(curl -s $KONG_PROXY_URL/httpbin/headers -H "Authorization: Bearer $TOKEN")
  
  # Handle both string and array responses from go-httpbin
  TEST_PLUGIN_HEADER=$(echo "$HEADERS_RESPONSE" | jq -r '
      if .headers."X-Test-Plugin" | type == "array" then 
          .headers."X-Test-Plugin"[0] 
      else 
          .headers."X-Test-Plugin" // "not-found"
      end' 2>/dev/null || echo "not-found")
  
  if [ "$TEST_PLUGIN_HEADER" = "test-value" ]; then
    echo "✅ Test 3 passed: Request transformer working (X-Test-Plugin: $TEST_PLUGIN_HEADER)"
  else
    echo "❌ Test 3 failed: X-Test-Plugin header = $TEST_PLUGIN_HEADER (expected: test-value)"
    exit 1
  fi
else
  echo "⏭️ Test 3 skipped: No JWT token available"
fi

# Test 4: Check rate limiting headers (with JWT token)
echo "Test 4: Checking rate limiting with JWT..."
if [ -n "$TOKEN" ]; then
  RATE_LIMIT_RESPONSE=$(curl -s -I $KONG_PROXY_URL/httpbin/get -H "Authorization: Bearer $TOKEN")
  
  # Check for various rate limit header formats
  if echo "$RATE_LIMIT_RESPONSE" | grep -qi "X-RateLimit\|X-Merged-RateLimit\|RateLimit-"; then
    echo "✅ Test 4 passed: Rate limiting headers present"
    
    # Extract specific headers if present
    LIMIT_MINUTE=$(echo "$RATE_LIMIT_RESPONSE" | grep -i "X-RateLimit-Limit-Minute" | cut -d: -f2 | tr -d ' \r' || echo "not-found")
    REMAINING_MINUTE=$(echo "$RATE_LIMIT_RESPONSE" | grep -i "X-RateLimit-Remaining-Minute" | cut -d: -f2 | tr -d ' \r' || echo "not-found")
    
    if [ "$LIMIT_MINUTE" != "not-found" ] && [ "$REMAINING_MINUTE" != "not-found" ]; then
      echo "✅ Rate limit details: Limit=$LIMIT_MINUTE/min, Remaining=$REMAINING_MINUTE"
    fi
  else
    echo "❌ Test 4 failed: Rate limiting headers not found"
    echo "Available headers: $(echo "$RATE_LIMIT_RESPONSE" | grep -E 'HTTP|X-|Rate' || echo 'none')"
    exit 1
  fi
else
  echo "⏭️ Test 4 skipped: No JWT token available"
fi

# Test 5: Check Prometheus metrics
echo "Test 5: Checking Prometheus metrics..."
METRICS_RESPONSE=$(curl -s $KONG_ADMIN_URL/metrics)
if echo "$METRICS_RESPONSE" | grep -q "kong_http_requests_total\|kong_http_requests\|# HELP kong"; then
  echo "✅ Test 5 passed: Prometheus metrics available"
else
  echo "❌ Test 5 warning: Prometheus metrics not found at /metrics"
  # Try alternative endpoint
  ALT_METRICS=$(curl -s $KONG_ADMIN_URL/status 2>/dev/null || echo "")
  if [ -n "$ALT_METRICS" ]; then
    echo "Kong status endpoint available, metrics may need separate configuration"
  fi
  exit 1
fi

# Test 6: Test multiple authenticated requests for rate limiting
echo "Test 6: Testing rate limiting with multiple authenticated requests..."
if [ -n "$TOKEN" ]; then
  for i in $(seq 1 3); do
    curl -s $KONG_PROXY_URL/httpbin/get -H "Authorization: Bearer $TOKEN" > /dev/null
    sleep 1
  done
  echo "✅ Test 6 completed: Multiple authenticated requests sent for rate limiting test"
else
  echo "⏭️ Test 6 skipped: No JWT token available"
fi

# Test 7: Test Zipkin tracing (check if traces are being sent)
echo "Test 7: Testing Zipkin tracing..."
if [ -n "$TOKEN" ]; then
  # Make a request that should generate trace
  curl -s $KONG_PROXY_URL/httpbin/headers \
    -H "Authorization: Bearer $TOKEN" \
    -H "X-Request-ID: test-trace-$(date +%s)" > /dev/null
  
  # Wait a moment for trace to be processed
  sleep 2
  
  # Check if Jaeger is receiving traces (simplified check)
  JAEGER_RESPONSE=$(curl -s "http://jaeger:16686/api/services" 2>/dev/null || echo "jaeger_unavailable")
  if echo "$JAEGER_RESPONSE" | grep -q "kong-gateway" 2>/dev/null; then
    echo "✅ Test 7 passed: Zipkin tracing working - kong-gateway service found in Jaeger"
  elif [ "$JAEGER_RESPONSE" = "jaeger_unavailable" ]; then
    echo "⚠️ Test 7 warning: Jaeger API not accessible, but trace should be sent"
  else
    echo "❌ Test 7 failed: kong-gateway service not found in Jaeger traces"
    exit 1
  fi
else
  echo "⏭️ Test 7 skipped: No JWT token available"
fi

echo "🎉 Quick integration tests completed!"
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
echo "   Issuer: https://iris:8443/auth/realms/master"
echo "   Consumer: admin-cli (with admin-group ACL)"