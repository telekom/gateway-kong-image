# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0

ARG KONG_VERSION=2.8.3

FROM kong:${KONG_VERSION} AS jwt-keycloak-builder

# Root needed for installing plugin
USER root

# Build jwt-keycloak plugin
ARG DISTO_ADDONS="zip"
RUN if [ -x "$(command -v apk)" ]; then apk add --no-cache $DISTO_ADDONS; \
    elif [ -x "$(command -v apt-get)" ]; then apt-get update && apt-get install $DISTO_ADDONS; \
    fi
WORKDIR /tmp

COPY ./external-plugins/jwt-keycloak/*.rockspec /tmp
COPY ./external-plugins/jwt-keycloak/LICENSES/Apache-2.0.txt /tmp/LICENSE
COPY ./external-plugins/jwt-keycloak/src /tmp/src
ARG PLUGIN_VERSION=1.3.0-1
RUN luarocks make && luarocks pack kong-plugin-jwt-keycloak ${PLUGIN_VERSION}


## Create Image
FROM kong:${KONG_VERSION}

# Copy jwt-keycloak plugin
COPY --from=jwt-keycloak-builder /tmp/*.rock /tmp/

# Root needed for installing plugins
USER root

# Install jwt-keycloak plugin
ARG PLUGIN_VERSION=1.3.0-1
RUN luarocks install /tmp/kong-plugin-jwt-keycloak-${PLUGIN_VERSION}.all.rock

# copy other plugins from repo to image
COPY plugins/ /opt/plugins

# upsert the plugins into kong's built-in plugins
RUN for plugin in /opt/plugins/*; do \
    plugin_name=$(basename $plugin); \
    rm -rf /usr/local/share/lua/5.1/kong/plugins/$plugin_name; \
    cp -r $plugin /usr/local/share/lua/5.1/kong/plugins/$plugin_name; \
    chown -R 1000:1000 /usr/local/share/lua/5.1/kong/plugins/$plugin_name; \
    done

RUN rm -rf /opt/plugins

# Registering additional plugins which are not just a patch of existing ones
ENV KONG_PLUGINS="bundled,jwt-keycloak,rate-limiting-merged"

## PostgreSQL v14+ fix: install luaossl
ARG FIX_DEPENDENCIES="gcc musl-dev"
RUN if [ -x "$(command -v apk)" ]; then apk add --no-cache $FIX_DEPENDENCIES; \
    elif [ -x "$(command -v apt-get)" ]; then apt-get update && apt-get install $FIX_DEPENDENCIES; \
    fi; \
    # --only-server fix based on https://support.konghq.com/support/s/article/LuaRocks-Error-main-function-has-more-than-65536-constants
    luarocks --only-server https://raw.githubusercontent.com/rocks-moonscript-org/moonrocks-mirror/daab2726276e3282dc347b89a42a5107c3500567 \
      install luaossl OPENSSL_DIR=/usr/local/kong CRYPTO_DIR=/usr/local/kong; \
    if [ -x "$(command -v apk)" ]; then apk del $FIX_DEPENDENCIES; \
    elif [ -x "$(command -v apt-get)" ]; then apt-get remove --purge -y $FIX_DEPENDENCIES; \
    fi

# Switch back to kong user
USER kong
