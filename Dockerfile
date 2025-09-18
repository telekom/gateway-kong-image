# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0

ARG KONG_VERSION=3.9.1

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
COPY ./external-plugins/jwt-keycloak/src /tmp/src
ARG PLUGIN_VERSION=1.5.0-1
RUN luarocks make && luarocks pack kong-plugin-jwt-keycloak ${PLUGIN_VERSION}


## Create Image
FROM kong:${KONG_VERSION}

# Copy jwt-keycloak plugin
COPY --from=jwt-keycloak-builder /tmp/*.rock /tmp/

# Root needed for installing plugins
USER root

# Install jwt-keycloak plugin
ARG PLUGIN_VERSION=1.5.0-1
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

# copy nginx template to bake it into the image
COPY --chown=1000:1000 templates/nginx_kong.lua /usr/local/share/lua/5.1/kong/templates/nginx_kong.lua

# Switch back to kong user
USER kong