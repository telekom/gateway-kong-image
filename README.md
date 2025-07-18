<!--
SPDX-FileCopyrightText: 2025 Deutsche Telekom AG

SPDX-License-Identifier: CC0-1.0    
-->

# Gateway Kong Image

## Overview

This repository contains a custom Kong distribution for the Open Telekom Integration
Platform (O28M). The API Gateway is based on **Kong OSS 3.9.1** with comprehensive customizations.

The plugins within this repository are based on the official Kong 3.9.1 plugins and have been enhanced with
Deutsche Telekom-specific features including memory optimization, enhanced consumer tracking, latency spike prevention,
and specialized metrics collection.

## Cloning the repository

Since this repository utilizes Git submodules, it is important to clone it with the `--recursive` or
`--recurse-submodules` option. This ensures that all submodules are cloned along with the main repository.

```sh
git clone --recursive https://github.com/telekom/gateway-kong-image
```

If you have already cloned the repository without this option, you can initialize and update the submodules using the
following command:

```sh
git submodule update --init --recursive
```

## Plugins

### jwt-keycloak

The `jwt-keycloak` plugin is used for integrating Kong with Keycloak for JWT authentication.
It is integrated as a Git submodule and references <https://github.com/telekom/kong-plugin-jwt-keycloak>.

### prometheus

The `prometheus` plugin is based on Kong 3.9.1 with Deutsche Telekom enhancements including:

- O28M latency buckets for memory optimization
- Enhanced consumer tracking across all metric types
- Horizon consumer handling for Pubsub-Horizon subscribers
- Latency spike prevention with yield mechanisms

### rate-limiting-merged

The `rate-limiting-merged` plugin is based on Kong 3.9.1 rate-limiting with Deutsche Telekom enhancements:

- Multi-dimensional rate limiting (service + consumer)
- Header merging logic with X-Merged-RateLimit-* headers
- Consumer omission capabilities
- Enhanced period validation and usage calculation

### zipkin

The `zipkin` plugin is based on Kong 3.9.1 with Deutsche Telekom enhancements:

- Tardis trace ID generation (worker_id + "#" + counter)
- Business context headers (x-request-id, x-business-context, x-correlation-id)
- Horizon PubSub headers support
- Environment detection from service tags
- Enhanced balancer tracking with error states

## Documentation

- **[Production Migration Guide](docs/PRODUCTION-MIGRATION.md)**: Comprehensive guide for migrating from Kong 2.8.3 to Kong 3.9.1 in production environments with AWS Aurora PostgreSQL
- **[Testing Guide](docs/TESTING.md)**: Local development and testing procedures
- **[Migration Progress](docs/MIGRATION-PROGRESS.md)**: Detailed progress tracking for the Kong 3.9.1 migration
- **[Kong Migration Comparison](docs/kong-migration-comparison.md)**: Technical comparison between Kong versions

## Local Testing Requirements

- Docker & Docker Compose
- OpenSSL (for generating self-signed certificates)
- curl and jq (for running tests)

## Setup

1. **Clone the repository:**

    ```sh
    git clone --recursive https://github.com/telekom/gateway-kong-image.git
    cd gateway-kong-image
    ```

2. **Build and start all services (certificates auto-generated):**

    ```sh
    docker-compose up --build -d
    ```

3. **Run integration tests:**

    ```sh
    docker-compose run --rm tests
    ```

4. **Access the services:**
   - Kong Proxy: <http://localhost:8000>
   - Kong Admin: <http://localhost:8001>
   - Keycloak: <https://localhost:8443/auth> (HTTPS)
   - Jaeger UI: <http://localhost:16686>

## Docker Compose Services

- **kong_init:** Initializes the Kong database with migrations
- **kong:** Runs the Kong 3.9.1 API Gateway with custom plugins
- **postgres:** PostgreSQL database for Kong
- **iris:** Keycloak identity provider with HTTP/HTTPS support
- **jaeger:** Jaeger tracing collector and UI
- **httpbin:** Internal HTTP testing service (mccutchen/go-httpbin)
- **tests:** Test runner container for validation

## Dockerfile

The `Dockerfile` is used to build a custom Kong OSS image with the `jwt-keycloak` and `rate-limiting-merged` plugins as
well as patched versions of `prometheus` and `zipkin`.

The Dockerfile is based on the official Kong 3.9.1 OSS image and includes:

- Build and install the external plugin `jwt-keycloak` via `luarocks`
- Add the `rate-limiting-merged` plugin with Kong 3.9.1 PDK APIs
- Enhanced `prometheus` plugin with Deutsche Telekom customizations
- Enhanced `zipkin` plugin with Kong 3.9.1 observability framework

**Kong OSS version:** 3.9.1 (Latest with AI Gateway capabilities)

## Deutsche Telekom Customizations

All customizations are marked with SPDX snippet headers and include:

### Memory Optimization

- O28M_ENI_LATENCY_BUCKETS with reduced bucket count
- Sub-1000ms latency coverage (50, 100, 500ms buckets)
- Local storage support for gauge metrics

### Enhanced Consumer Tracking

- Consumer labels on all latency metrics (kong_latency_ms, upstream_latency_ms, request_latency_ms)
- Horizon consumer handling with subscriber ID mapping
- Anonymous consumer fallback logic

### Latency Spike Prevention

- Yield mechanisms in metrics collection loops
- Non-blocking upstream health metrics export
- Phase-aware yielding for long operations

### Tracing Enhancements

- Tardis trace ID generation with worker identification
- Business context header support
- Environment detection from service tags
- Enhanced balancer state tracking

## Code of Conduct

This project has adopted the [Contributor Covenant](https://www.contributor-covenant.org/) in version 2.1 as our code of
conduct. Please see the details in our [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). All contributors must abide by the code
of conduct.

By participating in this project, you agree to abide by its [Code of Conduct](./CODE_OF_CONDUCT.md) at all times.

## Licensing

This project follows the [REUSE standard for software licensing](https://reuse.software/).
Each file contains copyright and license information, and license texts can be found in the [./LICENSES](./LICENSES)
folder. For more information visit <https://reuse.software/>.
