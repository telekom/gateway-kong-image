#!/bin/sh
# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0

check_plugin() {
  PLUGIN_NAME=$1
  RESPONSE=$(curl -s -u admin:admin ${KONG_ADMIN_URL}/plugins/enabled)
  if echo "$RESPONSE" | grep -q "\"$PLUGIN_NAME\""; then
    echo "✅  Plugin $PLUGIN_NAME is enabled."
  else
    echo "❌  Plugin $PLUGIN_NAME is not enabled."
    exit 1
  fi
}

enabled_plugins() {
  check_plugin "jwt-keycloak"
  check_plugin "prometheus"
  check_plugin "rate-limiting-merged"
  check_plugin "zipkin"
}
