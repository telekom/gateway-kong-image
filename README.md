<!--
SPDX-FileCopyrightText: 2025 Deutsche Telekom AG

SPDX-License-Identifier: CC0-1.0    
-->

# Gateway Kong Image

## Overview

This repository contains instructions on how to build one of the API Gateway's images of the Open Telekom Integration
Platform (O28M). The API Gateway is based on Kong OSS.

The plugins within this repository are partially based on the official Kong plugins and have been modified to meet the
requirements of the O28M project.

## Plugins

### jwt-keycloak

The `jwt-keycloak` plugin is used for integrating Kong with Keycloak for JWT authentication.
It is integrated as a Git submodule and references https://github.com/telekom/kong-plugin-jwt-keycloak.

### prometheus

The `prometheus` plugin is used for monitoring Kong with Prometheus. It is an adjusted version of the official Kong
plugin.

### rate-limiting-merged

The `rate-limiting-merged` plugin is self-developed and provides enhanced rate-limiting capabilities compatible with
O28M's gateway mesh capabilities.

### zipkin

The `zipkin` plugin is used for tracing requests with Zipkin. It is an adjusted version of the official Kong plugin.

## Local Testing Requirements

- Docker
- Docker Compose
- PostgreSQL

## Setup

1. **Clone the repository:**

    ```sh
    git clone <repository-url>
    cd <repository-directory>
    ```

2. **Build and start the services:**

    ```sh
    docker-compose up --build -d kong
    ```

3. **Run the tests:**

    ```sh
    docker-compose run tests
    ```

## Docker Compose Services

- **kong_init:** Initializes the Kong database with migrations.
- **kong:** Runs the Kong API Gateway.
- **postgres:** PostgreSQL database for Kong.
- **tests:** Runs the test suite.

## Dockerfile

The `Dockerfile` is used to build a custom Kong OSS image with the `jwt-keycloak` and `rate-limiting-merged` plugins as
well as patched versions of `prometheus` and `zipkin`.

The Dockerfile is based on the official Kong OSS image and includes the following steps:

- Build and install the external plugin `jwt-keycloak` via `luarocks`.
- Add the `rate-limiting-merged` plugin.
- Patch the existing `prometheus` and `zipkin` plugins.

**Suggested Kong OSS version:** 2.8.3 (LTS)

## Code of Conduct

This project has adopted the [Contributor Covenant](https://www.contributor-covenant.org/) in version 2.1 as our code of
conduct. Please see the details in our [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). All contributors must abide by the code
of conduct.

By participating in this project, you agree to abide by its [Code of Conduct](./CODE_OF_CONDUCT.md) at all times.

## Licensing

This project follows the [REUSE standard for software licensing](https://reuse.software/).
Each file contains copyright and license information, and license texts can be found in the [./LICENSES](./LICENSES)
folder. For more information visit https://reuse.software/.