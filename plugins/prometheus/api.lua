-- SPDX-FileCopyrightText: 2025 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/3.9.1/kong/plugins/prometheus/api.lua

local buffer = require("string.buffer")
local exporter = require "kong.plugins.prometheus.exporter"


local printable_metric_data = function(_)
  local buf = buffer.new(4096)
  -- override write_fn, since stream_api expect response to returned
  -- instead of ngx.print'ed
  exporter.metric_data(function(new_metric_data)
    buf:put(new_metric_data)
  end)

  local str = buf:get()

  buf:free()

  return str
end


return {
  ["/metrics"] = {
    GET = function()
      exporter.collect()
    end,
  },

  _stream = ngx.config.subsystem == "stream" and printable_metric_data or nil,
}
