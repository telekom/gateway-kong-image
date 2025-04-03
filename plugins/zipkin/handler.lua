-- SPDX-FileCopyrightText: 2021 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/2.8.3/kong/plugins/zipkin/handler.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

local new_zipkin_reporter = require "kong.plugins.zipkin.reporter".new
local new_span = require "kong.plugins.zipkin.span".new
local utils = require "kong.tools.utils"
local tracing_headers = require "kong.plugins.zipkin.tracing_headers"
local request_tags = require "kong.plugins.zipkin.request_tags"
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local to_hex = require "resty.string".to_hex
-- SPDX-SnippetEnd


local subsystem = ngx.config.subsystem
local fmt = string.format
local rand_bytes = utils.get_rand_bytes
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local worker_id
local worker_counter
-- SPDX-SnippetEnd

local ZipkinLogHandler = {
  VERSION = "1.5.0",
  -- We want to run first so that timestamps taken are at start of the phase
  -- also so that other plugins might be able to use our structures
  PRIORITY = 100000,
}

local reporter_cache = setmetatable({}, { __mode = "k" })

local math_random        = math.random
local ngx_req_start_time = ngx.req.start_time
local ngx_now            = ngx.now


-- ngx.now in microseconds
local function ngx_now_mu()
  return ngx_now() * 1000000
end


-- ngx.req.start_time in microseconds
local function ngx_req_start_time_mu()
  return ngx_req_start_time() * 1000000
end

local function get_reporter(conf)
  if reporter_cache[conf] == nil then
    reporter_cache[conf] = new_zipkin_reporter(conf.http_endpoint,
                                               -- SPDX-SnippetBegin
                                               -- SPDX-License-Identifier: Apache-2.0
                                               -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
                                               conf.local_component_name,
                                               -- SPDX-SnippetEnd
                                               conf.default_service_name,
                                               conf.local_service_name)
  end
  return reporter_cache[conf]
end

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local function tag_with_service(span, conf_environment)
  local service = kong.router.get_service()
  if service then

    local environment = ""

    if conf_environment and conf_environment ~= "qa" then
      environment = conf_environment
    else
      local tags = service.tags
      if tags then
        for k, v in pairs(tags) do
          if string.find(v, "environment") then
            environment = string.gsub(v, "ei__telekom__de%-%-environment%-%-%-", "")
          end
        end
      end
    end

    if environment then
      span:set_tag("environment", environment)
    end

    if type(service.name) == "string" then
      span.service_name = service.name
      span:set_tag("kong.service", service.name)
    end
  end
end
-- SPDX-SnippetEnd

-- adds the proxy span to the zipkin context, unless it already exists
local function get_or_add_proxy_span(zipkin, timestamp)
  if not zipkin.proxy_span then
    local request_span = zipkin.request_span
    zipkin.proxy_span = request_span:new_child(
      "CLIENT",
      request_span.name .. " (proxy)",
      timestamp
    )
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    zipkin.proxy_span:set_tag("x-tardis-traceid", request_span:get_tag("x-tardis-traceid"))
    -- SPDX-SnippetEnd
  end
  return zipkin.proxy_span
end


local function timer_log(premature, reporter)
  if premature then
    return
  end

  local ok, err = reporter:flush()
  if not ok then
    kong.log.err("reporter flush ", err)
    return
  end
end



local initialize_request


local function get_context(conf, ctx)
  local zipkin = ctx.zipkin
  if not zipkin then
    initialize_request(conf, ctx)
    zipkin = ctx.zipkin
  end
  return zipkin
end

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local function starts_with(str, start)
  return str:sub(1, #start) == start
end

local function get_tardis_id()
  worker_counter = worker_counter + 1
  return worker_id .. "#" .. worker_counter
end
-- SPDX-SnippetEnd

if subsystem == "http" then
  initialize_request = function(conf, ctx)
    local req = kong.request

    local req_headers = req.get_headers()
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    local req_path = kong.request.get_path()

    local header_type, trace_id, span_id, parent_id, should_sample, tardis_id, baggage =
      tracing_headers.parse(req_headers, conf.header_type)

    local method = req.get_method()

    if conf.force_sample then
      should_sample = conf.force_sample
    end

    if starts_with(req_path, "/admin-api") then
      should_sample = false
    end
    -- SPDX-SnippetEnd

    if should_sample == nil then
      should_sample = math_random() < conf.sample_ratio
    end

    if trace_id == nil then
      trace_id = rand_bytes(conf.traceid_byte_count)
    end

    local request_span = new_span(
      "SERVER",
      method,
      ngx_req_start_time_mu(),
      should_sample,
      trace_id,
      span_id,
      parent_id,
      baggage)

    local http_version = req.get_http_version()
    local protocol = http_version and 'HTTP/'..http_version or nil

    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    if tardis_id == nil then
      tardis_id = to_hex(get_tardis_id())
      request_span:set_tag("x-tardis-consumer-side", "true")
    end

    local request_id, business_context, correlation_id = tracing_headers.parse_business_headers(req_headers)

    if request_id and type(request_id) == "string" then
      request_span:set_tag("x-request-id", request_id)
    end
    if business_context and type(business_context) == "string" then
      request_span:set_tag("x-business-context", business_context)
    end
    if correlation_id and type(correlation_id) == "string" then
      request_span:set_tag("x-correlation-id", correlation_id)
    end

    local publisher, subscriber = tracing_headers.parse_horizon_headers(req_headers)

    if publisher then
      request_span:set_tag("publisher", publisher)

      if subscriber then
        request_span:set_tag("subscriber", subscriber)
      end
    end
    -- SPDX-SnippetEnd

    request_span.ip = kong.client.get_forwarded_ip()
    request_span.port = kong.client.get_forwarded_port()

    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    local lc = conf.local_component_name or "kong"

    request_span:set_tag("x-tardis-traceid", tardis_id)
    request_span:set_tag("lc", lc)
    -- SPDX-SnippetEnd
    request_span:set_tag("http.method", method)
    request_span:set_tag("http.host", req.get_host())
    request_span:set_tag("http.path", req.get_path())
    if protocol then
      request_span:set_tag("http.protocol", protocol)
    end
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    if conf.zone then
      request_span:set_tag("zone", conf.zone)
    end
    -- SPDX-SnippetEnd

    local static_tags = conf.static_tags
    if type(static_tags) == "table" then
      for i = 1, #static_tags do
        local tag = static_tags[i]
        request_span:set_tag(tag.name, tag.value)
      end
    end

    local req_tags, err = request_tags.parse(req_headers[conf.tags_header])
    if err then
      -- log a warning in case there were erroneous request tags. Don't throw the tracing away & rescue with valid tags, if any
      kong.log.warn(err)
    end
    if req_tags then
      for tag_name, tag_value in pairs(req_tags) do
        request_span:set_tag(tag_name, tag_value)
      end
    end

    ctx.zipkin = {
      request_span = request_span,
      header_type = header_type,
      proxy_span = nil,
      header_filter_finished = false,
    }
  end

  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  function ZipkinLogHandler:init_worker()
    worker_id = tracing_headers.from_hex(rand_bytes(10))
    worker_counter = 0
  end
  -- SPDX-SnippetEnd

  function ZipkinLogHandler:rewrite(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx
    -- note: rewrite is logged on the request_span, not on the proxy span
    local rewrite_start_mu =
      ngx_ctx.KONG_REWRITE_START and ngx_ctx.KONG_REWRITE_START * 1000
      or ngx_now_mu()
    zipkin.request_span:annotate("krs", rewrite_start_mu)
  end


  function ZipkinLogHandler:access(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx

    local access_start =
      ngx_ctx.KONG_ACCESS_START and ngx_ctx.KONG_ACCESS_START * 1000
      or ngx_now_mu()
    get_or_add_proxy_span(zipkin, access_start)

    tracing_headers.set(conf.header_type, zipkin.header_type, zipkin.proxy_span, conf.default_header_type)
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    tracing_headers.set_tardis_id(zipkin.request_span:get_tag("x-tardis-traceid"))
    -- SPDX-SnippetEnd
  end


  function ZipkinLogHandler:header_filter(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx
    local header_filter_start_mu =
      ngx_ctx.KONG_HEADER_FILTER_STARTED_AT and ngx_ctx.KONG_HEADER_FILTER_STARTED_AT * 1000
      or ngx_now_mu()

    local proxy_span = get_or_add_proxy_span(zipkin, header_filter_start_mu)
    proxy_span:annotate("khs", header_filter_start_mu)
  end


  function ZipkinLogHandler:body_filter(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)

    -- Finish header filter when body filter starts
    if not zipkin.header_filter_finished then
      local now_mu = ngx_now_mu()

      zipkin.proxy_span:annotate("khf", now_mu)
      zipkin.header_filter_finished = true
      zipkin.proxy_span:annotate("kbs", now_mu)
    end
  end

elseif subsystem == "stream" then

  initialize_request = function(conf, ctx)
    local request_span = new_span(
      "SERVER",
      "stream",
      ngx_req_start_time_mu(),
      math_random() < conf.sample_ratio,
      rand_bytes(conf.traceid_byte_count)
    )
    request_span.ip = kong.client.get_forwarded_ip()
    request_span.port = kong.client.get_forwarded_port()

    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    local lc = conf.local_component_name or "kong"

    request_span:set_tag("lc", lc)
    -- SPDX-SnippetEnd

    local static_tags = conf.static_tags
    if type(static_tags) == "table" then
      for i = 1, #static_tags do
        local tag = static_tags[i]
        request_span:set_tag(tag.name, tag.value)
      end
    end

    ctx.zipkin = {
      request_span = request_span,
      proxy_span = nil,
    }
  end


  function ZipkinLogHandler:preread(conf) -- luacheck: ignore 212
    local zipkin = get_context(conf, kong.ctx.plugin)
    local ngx_ctx = ngx.ctx
    local preread_start_mu =
      ngx_ctx.KONG_PREREAD_START and ngx_ctx.KONG_PREREAD_START * 1000
      or ngx_now_mu()

    local proxy_span = get_or_add_proxy_span(zipkin, preread_start_mu)
    proxy_span:annotate("kps", preread_start_mu)
  end
end


function ZipkinLogHandler:log(conf) -- luacheck: ignore 212
  local now_mu = ngx_now_mu()
  local zipkin = get_context(conf, kong.ctx.plugin)
  local ngx_ctx = ngx.ctx
  local request_span = zipkin.request_span
  local proxy_span = get_or_add_proxy_span(zipkin, now_mu)
  local reporter = get_reporter(conf)

  local proxy_finish_mu =
    ngx_ctx.KONG_BODY_FILTER_ENDED_AT and ngx_ctx.KONG_BODY_FILTER_ENDED_AT * 1000
    or now_mu

  if ngx_ctx.KONG_REWRITE_START and ngx_ctx.KONG_REWRITE_TIME then
    -- note: rewrite is logged on the request span, not on the proxy span
    local rewrite_finish_mu = (ngx_ctx.KONG_REWRITE_START + ngx_ctx.KONG_REWRITE_TIME) * 1000
    zipkin.request_span:annotate("krf", rewrite_finish_mu)
  end

  if subsystem == "http" then
    -- annotate access_start here instead of in the access phase
    -- because the plugin access phase is skipped when dealing with
    -- requests which are not matched by any route
    -- but we still want to know when the access phase "started"
    local access_start_mu =
      ngx_ctx.KONG_ACCESS_START and ngx_ctx.KONG_ACCESS_START * 1000
      or proxy_span.timestamp
    proxy_span:annotate("kas", access_start_mu)

    local access_finish_mu =
      ngx_ctx.KONG_ACCESS_ENDED_AT and ngx_ctx.KONG_ACCESS_ENDED_AT * 1000
      or proxy_finish_mu
    proxy_span:annotate("kaf", access_finish_mu)

    if not zipkin.header_filter_finished then
      proxy_span:annotate("khf", now_mu)
      zipkin.header_filter_finished = true
    end

    proxy_span:annotate("kbf", now_mu)

  else
    local preread_finish_mu =
      ngx_ctx.KONG_PREREAD_ENDED_AT and ngx_ctx.KONG_PREREAD_ENDED_AT * 1000
      or proxy_finish_mu
    proxy_span:annotate("kpf", preread_finish_mu)
  end

  local balancer_data = ngx_ctx.balancer_data
  if balancer_data then
    local balancer_tries = balancer_data.tries
    for i = 1, balancer_data.try_count do
      local try = balancer_tries[i]

      -- SPDX-SnippetBegin
      -- SPDX-License-Identifier: Apache-2.0
      -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
      proxy_span:annotate(fmt("bts.%d", i), try.balancer_start * 1000)

      if i < balancer_data.try_count then
              proxy_span:set_tag("error", true)
              proxy_span:set_tag(fmt("kong.balancer.state.%d", i), try.state)
              proxy_span:set_tag(fmt("http.status_code.%d", i), try.code)
      end

      if try.balancer_latency ~= nil then
        proxy_span:annotate(fmt("btf.%d", i), (try.balancer_start + try.balancer_latency) * 1000)
      else
        proxy_span:annotate(fmt("btf.%d", i), now_mu)
      end
      -- SPDX-SnippetEnd

    end
    proxy_span:set_tag("peer.hostname", balancer_data.hostname) -- could be nil
    proxy_span.ip   = balancer_data.ip
    proxy_span.port = balancer_data.port
  end

  if subsystem == "http" then
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    local status_code = kong.response.get_status()
    request_span:set_tag("http.status_code", status_code)
    if status_code >= 400 then
      request_span:set_tag("error", true)
    end
  end

  if ngx_ctx.authenticated_consumer and ngx_ctx.authenticated_consumer.custom_id then
    request_span:set_tag("kong.consumer", ngx_ctx.authenticated_consumer.custom_id)
  end

  if conf.include_credential and ngx_ctx.authenticated_credential then
    request_span:set_tag("kong.credential", ngx_ctx.authenticated_credential.id)
  end
  --request_span:set_tag("kong.node.id", kong.node.get_id())
  request_span:set_tag("kong.pod", kong.node.get_hostname())
  --tag_with_service_and_route(proxy_span)
  tag_with_service(request_span, conf.environment)
  -- SPDX-SnippetEnd


  proxy_span:finish(proxy_finish_mu)
  reporter:report(proxy_span)
  request_span:finish(now_mu)
  reporter:report(request_span)

  local ok, err = ngx.timer.at(0, timer_log, reporter)
  if not ok then
    kong.log.err("failed to create timer: ", err)
  end
end


return ZipkinLogHandler
