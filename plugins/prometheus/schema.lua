-- SPDX-FileCopyrightText: 2025 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/3.9.1/kong/plugins/prometheus/schema.lua
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
          { per_consumer = { description = "A boolean value that determines if per-consumer metrics should be collected. If enabled, the `kong_http_requests_total` and `kong_bandwidth_bytes` metrics fill in the consumer label when available.", type = "boolean", default = false }, },
          { status_code_metrics = { description = "A boolean value that determines if status code metrics should be collected. If enabled, `http_requests_total`, `stream_sessions_total` metrics will be exported.", type = "boolean", default = false }, },
          { ai_metrics = { description = "A boolean value that determines if ai metrics should be collected. If enabled, the `ai_llm_requests_total`, `ai_llm_cost_total` and `ai_llm_tokens_total` metrics will be exported.", type = "boolean", default = false }, },
          { latency_metrics = { description = "A boolean value that determines if latency metrics should be collected. If enabled, `kong_latency_ms`, `upstream_latency_ms` and `request_latency_ms` metrics will be exported.", type = "boolean", default = false }, },
          { bandwidth_metrics = { description = "A boolean value that determines if bandwidth metrics should be collected. If enabled, `bandwidth_bytes` and `stream_sessions_total` metrics will be exported.", type = "boolean", default = false }, },
          { upstream_health_metrics = { description = "A boolean value that determines if upstream metrics should be collected. If enabled, `upstream_target_health` metric will be exported.", type = "boolean", default = false }, },
        },
        custom_validator = validate_shared_dict,
    }, },
  },
}
