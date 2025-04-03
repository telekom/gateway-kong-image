-- SPDX-FileCopyrightText: 2022 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/tree/2.8.3/kong/plugins/prometheus/handler.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local exporter = require "kong.plugins.prometheus.exporter"
local kong = kong
local kong_meta = require "kong.meta"


exporter.init()
-- SPDX-SnippetEnd

local PrometheusHandler = {
  PRIORITY = 13,
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  VERSION  = kong_meta.version,
  -- SPDX-SnippetEnd
}

function PrometheusHandler.init_worker()
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  exporter.init_worker()
  -- SPDX-SnippetEnd
end

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local http_subsystem = ngx.config.subsystem == "http"
-- SPDX-SnippetEnd

function PrometheusHandler.log(self, conf)
  local message = kong.log.serialize()

  local serialized = {}
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  if conf.per_consumer and message.consumer ~= nil then
    serialized.consumer = message.consumer.username
  else
    serialized.consumer = "anonymous"
  end

  if conf.status_code_metrics then
    if http_subsystem and message.response then
      serialized.status_code = message.response.status
    elseif not http_subsystem and message.session then
      serialized.status_code = message.session.status
    end
  end

  if conf.bandwidth_metrics then
    if http_subsystem then
      serialized.egress_size = message.response and tonumber(message.response.size)
      serialized.ingress_size = message.request and tonumber(message.request.size)
    else
      serialized.egress_size = message.response and tonumber(message.session.sent)
      serialized.ingress_size = message.request and tonumber(message.session.received)
    end
  end

  if message.request and message.request.method ~= nil then
    serialized.method = message.request.method
  else
    serialized.method = "default"
  end

  if conf.latency_metrics then
    serialized.latencies = message.latencies
  end

  if conf.upstream_health_metrics then
    exporter.set_export_upstream_health_metrics(true)
  else
    exporter.set_export_upstream_health_metrics(false)
  end

  exporter.log(message, serialized)
  -- SPDX-SnippetEnd
end


return PrometheusHandler
