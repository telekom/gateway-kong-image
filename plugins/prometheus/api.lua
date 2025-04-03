-- SPDX-FileCopyrightText: 2021 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/tree/2.8.3/kong/plugins/prometheus/api.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local exporter = require "kong.plugins.prometheus.exporter"
-- SPDX-SnippetEnd

local printable_metric_data = function()
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  -- override write_fn, since stream_api expect response to returned
  -- instead of ngx.print'ed
  local buffer = {}

  exporter.metric_data(function(data)
    table.insert(buffer, table.concat(data, ""))
  end)

  return table.concat(buffer, "")
  -- SPDX-SnippetEnd
end

return {
  ["/metrics"] = {
    GET = function()
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  -- Changed variable name from prometheus to exporter
      exporter.collect()
  -- SPDX-SnippetEnd
    end,
  },

  _stream = ngx.config.subsystem == "stream" and printable_metric_data or nil,
}
