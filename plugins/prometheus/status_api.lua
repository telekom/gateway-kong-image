-- SPDX-FileCopyrightText: 2019 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/tree/2.8.3/kong/plugins/prometheus/status_api.lua

local prometheus = require "kong.plugins.prometheus.exporter"


return {
  ["/metrics"] = {
    GET = function()
      prometheus.collect()
    end,
  },
}
