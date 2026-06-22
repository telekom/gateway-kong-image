-- SPDX-FileCopyrightText: 2025 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/3.9.1/kong/plugins/opentelemetry/handler.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

local otel_traces = require "kong.plugins.opentelemetry.traces"
local otel_logs = require "kong.plugins.opentelemetry.logs"
local dynamic_hook = require "kong.dynamic_hook"
local o11y_logs = require "kong.observability.logs"
local kong_meta = require "kong.meta"

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local eni = require "kong.plugins.opentelemetry.eni_enhancements"
-- SPDX-SnippetEnd


local OpenTelemetryHandler = {
  VERSION = kong_meta.version,
  PRIORITY = 14,
}


function OpenTelemetryHandler:configure(configs)
  if configs then
    for _, config in ipairs(configs) do
      if config.logs_endpoint then
        dynamic_hook.hook("observability_logs", "push", o11y_logs.maybe_push)
        dynamic_hook.enable_by_default("observability_logs")
      end
    end
  end
end


-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
function OpenTelemetryHandler:init_worker()
  eni.init_worker()
end
-- SPDX-SnippetEnd


function OpenTelemetryHandler:access(conf)
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  -- Exclude /admin-api requests from sampling (zipkin plugin parity). Setting
  -- this before otel_traces.access makes both the sampling decision and the
  -- span export honour it (traces.lua checks kong.ctx.plugin.should_sample).
  if conf.traces_endpoint and eni.should_disable_sampling() then
    kong.ctx.plugin.should_sample = false
  end
  -- SPDX-SnippetEnd

  -- Traces
  if conf.traces_endpoint then
    otel_traces.access(conf)
  end

  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  -- Resolve and propagate the Tardis trace id to the upstream request so the
  -- provider side (and downstream Jumper) can correlate on it, mirroring the
  -- zipkin plugin behaviour.
  if conf.traces_endpoint then
    local headers = kong.request.get_headers()
    local tardis_id = eni.resolve_tardis_id(headers)
    eni.set_tardis_request_header(tardis_id)
  end
  -- SPDX-SnippetEnd
end


function OpenTelemetryHandler:header_filter(conf)
  -- Traces
  if conf.traces_endpoint then
    otel_traces.header_filter(conf)

    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    -- Always expose the Tardis trace id on the response.
    local tardis_id = kong.ctx.plugin.tardis_id
    eni.set_tardis_response_header(tardis_id)
    -- SPDX-SnippetEnd
  end
end


function OpenTelemetryHandler:log(conf)
  -- Traces
  if conf.traces_endpoint then
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    -- Enrich the request root span with Deutsche Telekom custom attributes
    -- before the native exporter serializes and enqueues the spans.
    eni.enrich_root_span(conf)
    -- Rename the native "kong.balancer" span to the zipkin-style
    -- "<method> (proxy)" and add peer.service / net.peer.port for parity.
    eni.enrich_proxy_span(conf)
    -- SPDX-SnippetEnd

    otel_traces.log(conf)
  end

  -- Logs
  if conf.logs_endpoint then
    otel_logs.log(conf)
  end
end


return OpenTelemetryHandler
