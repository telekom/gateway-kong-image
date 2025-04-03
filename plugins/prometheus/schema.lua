-- SPDX-FileCopyrightText: 2021 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/tree/2.8.3/kong/plugins/prometheus/schema.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

local typedefs = require "kong.db.schema.typedefs"

local function validate_shared_dict()
  if not ngx.shared.prometheus_metrics then
    return nil,
           "ngx shared dict 'prometheus_metrics' not found"
  end
  return true
end


return {
  name = "prometheus",
  fields = {
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    { protocols = typedefs.protocols },
    -- SPDX-SnippetEnd
    { config = {
        type = "record",
        fields = {
          { per_consumer = { type = "boolean", default = false }, },
          -- SPDX-SnippetBegin
          -- SPDX-License-Identifier: Apache-2.0
          -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
          { status_code_metrics = { type = "boolean", default = false }, },
          { latency_metrics = { type = "boolean", default = false }, },
          { bandwidth_metrics = { type = "boolean", default = false }, },
          { upstream_health_metrics = { type = "boolean", default = false }, },
          -- SPDX-SnippetEnd
        },
        custom_validator = validate_shared_dict,
    }, },
  },
}
