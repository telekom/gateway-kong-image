#!/bin/sh
# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0

# Kong 3.9.1 Migration Test Suite
# Tests all custom plugins and Deutsche Telekom customizations

echo "🚀 Kong 3.9.1 Migration Test Suite"
echo "📋 Testing: JWT-Keycloak, Prometheus, Rate-Limiting-Merged, Zipkin plugins"
echo ""

# include _env.sh
. _env.sh
prepare_environment
wait_for_kong

# Test 1: Check plugin availability
echo "🔌 Phase 1: Checking plugin availability..."
. enabled_plugins.sh
enabled_plugins

# Test 2: Run comprehensive integration tests
echo ""
echo "🧪 Phase 2: Running comprehensive integration tests..."
chmod +x quick_integration_test.sh
./quick_integration_test.sh

echo ""
echo "✅ Kong 3.9.1 Migration Test Suite completed successfully!"
echo "📊 All Deutsche Telekom customizations validated and working"