#!/bin/sh
# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0


# Set the environment variables for the tests
prepare_environment() {
  export KONG_ADMIN_URL=http://kong:8001
  export KONG_PROXY_URL=http://kong:8000
  export IRIS_HTTP_URL=http://iris:8080
  export IRIS_HTTPS_URL=https://iris:8443
}

# wait for kong to be ready or timeout
wait_for_kong() {
  echo "Waiting for Kong to be ready..."
  for i in $(seq 1 30); do
    if curl -s -o /dev/null $KONG_ADMIN_URL; then
      echo "Kong is ready!"
      return 0
    fi
    sleep 1
  done
  echo "Kong is not ready after 30 seconds, exiting..."
  exit 1
}

# wait for iris (Keycloak) to be ready or timeout
wait_for_iris() {
  echo "Waiting for Iris (Keycloak) to be ready..."
  for i in $(seq 1 30); do
    # Try health endpoint on port 9000 first
    if test $(curl -s -o /dev/null -w '%{http_code}' http://iris:8080/auth/realms/master/.well-known/openid-configuration) -eq 200; then
      echo "Iris health endpoint is ready!"
      return 0
    fi
    sleep 1
  done
  echo "Iris is not ready after 30 seconds, exiting..."
  exit 1
}