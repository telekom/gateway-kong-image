#!/bin/sh
# SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
#
# SPDX-License-Identifier: Apache-2.0

# include _env.sh
. _env.sh
prepare_environment
wait_for_kong

# include tests
. enabled_plugins.sh
. plugin_schemas.sh

# run tests
enabled_plugins
check_plugin_schemas