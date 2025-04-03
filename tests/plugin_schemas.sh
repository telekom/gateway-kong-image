#!/bin/sh
# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0

check_plugin_schema() {
  PLUGIN_NAME=$1
  EXPECTED_SCHEMA_FILE=$2
  RESPONSE=$(curl -s ${KONG_ADMIN_URL}/plugins/schema/${PLUGIN_NAME})
  if [ $? -ne 0 ]; then
    echo "❌  Failed to fetch schema for plugin $PLUGIN_NAME."
    exit 1
  fi
  EXPECTED_SCHEMA=$(cat $EXPECTED_SCHEMA_FILE)
  if echo "$RESPONSE" | jq --argjson expected "$EXPECTED_SCHEMA" 'if . == $expected then true else false end' | grep -q true; then
    echo "✅  Schema for plugin $PLUGIN_NAME matches."
  else
    echo "❌  Schema for plugin $PLUGIN_NAME does not match."
    exit 1
  fi
}

check_plugin_schemas() {
  check_plugin_schema "jwt-keycloak" "schemas/jwt-keycloak.json"
  check_plugin_schema "prometheus" "schemas/prometheus.json"
  check_plugin_schema "rate-limiting-merged" "schemas/rate-limiting-merged.json"
  check_plugin_schema "zipkin" "schemas/zipkin.json"
}