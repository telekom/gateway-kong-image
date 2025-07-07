-- SPDX-FileCopyrightText: 2025 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/3.9.1/kong/plugins/prometheus/status_api.lua

local prometheus = require "kong.plugins.prometheus.exporter"


return {
  ["/metrics"] = {
    GET = function()
      prometheus.collect()
    end,
  },
}
