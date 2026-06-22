-- SPDX-FileCopyrightText: 2025 Deutsche Telekom AG
--
-- SPDX-License-Identifier: Apache-2.0

-- Deutsche Telekom enhancements for the OpenTelemetry plugin.
--
-- This module concentrates the Open Telekom Integration Platform (Tardis)
-- specific span enrichment so that the patched Kong `opentelemetry` plugin
-- produces the same custom attributes that the enhanced `zipkin` plugin emits
-- today:
--   * Tardis trace id generation (worker_id + "#" + counter) and the
--     x-tardis-traceid request / X-Tardis-Traceid response headers
--   * x-tardis-consumer-side marker on consumer-originated traces
--   * business context headers (x-request-id, x-business-context,
--     x-correlation-id)
--   * Horizon PubSub headers (publisher / subscriber)
--   * lc (local service name) and zone tags
--
-- It operates on the native Kong tracing PDK spans (ngx.ctx.KONG_SPANS[1] is the
-- request root span), so no manual span construction is required. The logic
-- mirrors plugins/zipkin/handler.lua to keep both exporters in parity.

local rand_bytes = require("kong.tools.rand").get_rand_bytes
local to_hex = require "resty.string".to_hex

local _M = {}

-- Per-worker state for Tardis id generation (mirrors zipkin/handler.lua).
local worker_id
local worker_counter

local function from_hex(str)
  if str ~= nil then
    str = str:gsub("%x%x", function(c)
      return string.char(tonumber(c, 16))
    end)
  end
  return str
end

-- Initialize per-worker Tardis state. Call from the plugin handler's
-- init_worker phase.
function _M.init_worker()
  worker_id = from_hex(rand_bytes(10))
  worker_counter = 0
end

local function get_tardis_id()
  worker_counter = (worker_counter or 0) + 1
  return worker_id .. "#" .. worker_counter
end

-- Parse the Tardis trace id from incoming headers (hex string), if present.
local function parse_tardis_header(headers)
  local tardis_id = headers["x-tardis-traceid"]
  if tardis_id == nil then
    return nil
  end
  if type(tardis_id) == "string" and tardis_id:match("%X") then
    kong.log.warn("tardis_id header invalid; ignoring")
    return nil
  end
  return tardis_id
end

-- Resolve the Tardis trace id for this request: reuse the incoming one or
-- generate a new hex id. Cached on kong.ctx.plugin so access() and the
-- span-enrichment in log() agree on the same value.
function _M.resolve_tardis_id(headers)
  local ctx = kong.ctx.plugin
  if ctx.tardis_id ~= nil then
    return ctx.tardis_id, ctx.tardis_consumer_side
  end

  local tardis_id = parse_tardis_header(headers)
  local consumer_side = false
  if tardis_id == nil then
    tardis_id = to_hex(get_tardis_id())
    consumer_side = true
  end

  ctx.tardis_id = tardis_id
  ctx.tardis_consumer_side = consumer_side
  return tardis_id, consumer_side
end

-- Propagate the Tardis trace id to the upstream request, like the zipkin
-- plugin's tracing_headers.set_tardis_id.
function _M.set_tardis_request_header(tardis_id)
  if tardis_id then
    kong.service.request.set_header("x-tardis-traceid", tardis_id)
  end
end

-- Always expose the Tardis trace id on the response (zipkin parity).
function _M.set_tardis_response_header(tardis_id)
  if tardis_id then
    kong.response.add_header("X-Tardis-Traceid", tardis_id)
  end
end

local function set_attr(span, key, value)
  if value ~= nil and value ~= "" then
    span:set_attribute(key, value)
  end
end

-- Set the `environment` and `kong.service` attributes from the matched Kong
-- service, mirroring the enhanced zipkin plugin's tag_with_service(). Returns
-- the service name (or nil) so the caller can reuse it for peer.service.
--   * environment: an explicit conf.environment (non-"qa") wins; otherwise it
--     is parsed from the Tardis service tag "ei__telekom__de--environment---<env>".
--   * kong.service: the matched service name.
local function set_service_attrs(span, conf)
  local service = kong.router.get_service()
  if not service then
    return nil
  end

  local environment = ""
  local conf_environment = conf.environment
  if conf_environment and conf_environment ~= "qa" then
    environment = conf_environment
  elseif service.tags then
    for _, v in pairs(service.tags) do
      if string.find(v, "environment") then
        environment = string.gsub(v, "ei__telekom__de%-%-environment%-%-%-", "")
      end
    end
  end
  set_attr(span, "environment", environment)

  local name = service.name
  if type(name) == "string" then
    set_attr(span, "kong.service", name)
    return name
  end
  return nil
end

-- Enrich the request root span with the Deutsche Telekom custom attributes.
-- Intended to be called from the plugin handler's log phase, before the native
-- plugin exports spans. Mirrors the tag set in plugins/zipkin/handler.lua to
-- keep both exporters in parity.
function _M.enrich_root_span(conf)
  local span = ngx.ctx.KONG_SPANS and ngx.ctx.KONG_SPANS[1]
  if not span then
    return
  end

  -- TEMPORARY DIAGNOSTIC (remove after debugging): confirms the enrichment is
  -- actually invoked on the deployed image and that a root span is present.
  kong.log.warn("[eni] enrich_root_span: invoked; root span present")

  -- Rename the native root span ("kong") to the HTTP method, matching the
  -- enhanced zipkin plugin whose SERVER request span was named "<method>"
  -- (e.g. "GET"). The tracing UI shows "<service.name> <span.name>", so this
  -- restores "stargate-integration GET" instead of "stargate-integration kong".
  local method = kong.request.get_method()
  if method then
    span.name = method
  end

  local headers = kong.request.get_headers()
  local tardis_id, consumer_side = _M.resolve_tardis_id(headers)

  -- Tardis trace id and consumer-side marker
  set_attr(span, "x-tardis-traceid", tardis_id)
  if consumer_side then
    set_attr(span, "x-tardis-consumer-side", "true")
  end

  -- local service name marker (zipkin uses the `lc` tag)
  set_attr(span, "lc", conf.local_service_name or "kong")

  -- business context headers
  set_attr(span, "x-request-id", headers["x-request-id"])
  set_attr(span, "x-business-context", headers["x-business-context"])
  set_attr(span, "x-correlation-id", headers["x-correlation-id"])

  -- Horizon PubSub headers
  local publisher = headers["x-pubsub-publisher-id"]
  if publisher then
    set_attr(span, "publisher", publisher)
    set_attr(span, "subscriber", headers["x-pubsub-subscriber-id"])
  end

  -- HTTP request attributes (zipkin parity: http.path / http.protocol)
  set_attr(span, "http.path", kong.request.get_path())
  local http_version = kong.request.get_http_version()
  if http_version then
    set_attr(span, "http.protocol", "HTTP/" .. http_version)
  end

  -- Kong runtime attributes (zipkin parity: kong.consumer / kong.pod)
  local consumer = ngx.ctx.authenticated_consumer
  if consumer and consumer.custom_id then
    set_attr(span, "kong.consumer", consumer.custom_id)
  end
  set_attr(span, "kong.pod", kong.node.get_hostname())

  -- environment + kong.service from the matched service (zipkin parity)
  local service_name = set_service_attrs(span, conf)

  -- peer.service / net.peer.port on the root span (zipkin parity). The enhanced
  -- zipkin plugin populated the request span's remoteEndpoint with
  -- serviceName = service.name (falling back to default_service_name) and
  -- port = the forwarded client port; the collector mapped these to
  -- peer.service / net.peer.port. net.peer.ip is already set natively by Kong,
  -- so only these two need to be restored here.
  set_attr(span, "peer.service", service_name or conf.local_service_name)
  set_attr(span, "net.peer.port", kong.client.get_forwarded_port())

  -- zone
  set_attr(span, "zone", conf.zone)
end

-- Enrich the native Kong balancer span for zipkin parity:
--   * rename "kong.balancer" to "<method> (proxy)" (e.g. "GET (proxy)"), the
--     name the enhanced zipkin plugin gave its CLIENT proxy span;
--   * peer.hostname: the upstream hostname (zipkin set this as an explicit tag
--     from balancer_data.hostname);
--   * net.peer.port: the upstream port, which the collector previously derived
--     from the zipkin proxy span's remoteEndpoint.port (balancer_data.port);
--   * peer.service: which the collector derived from the proxy span's
--     remoteEndpoint.serviceName. That field was never assigned on the proxy
--     span, so zipkin fell back to default_service_name (helm defaultServiceName).
--     The OTLP equivalent is conf.local_service_name (same helm value), so we use
--     that to preserve the historical value rather than the Kong service name.
-- Operates on the native PDK spans in ngx.ctx.KONG_SPANS, so it requires the
-- "balancer" instrumentation to be enabled (KONG_TRACING_INSTRUMENTATIONS must
-- include "balancer" or "all"). Intended to be called from the plugin handler's
-- log phase, before the native plugin serializes and exports the spans.
function _M.enrich_proxy_span(conf)
  local spans = ngx.ctx.KONG_SPANS
  if not spans then
    return
  end

  local method = kong.request.get_method()
  local proxy_name = method and (method .. " (proxy)") or nil

  -- Upstream peer info, mirroring the zipkin proxy span's remoteEndpoint /
  -- peer.hostname tag.
  local balancer_data = ngx.ctx.balancer_data
  local peer_port = balancer_data and balancer_data.port
  local peer_hostname = balancer_data and balancer_data.hostname
  local peer_service = conf and conf.local_service_name

  -- Iterate with ipairs (not "#spans"): Kong's span storage is a pooled,
  -- pre-sized table that tracks its length at index 0, so the Lua length
  -- operator is unreliable here. ipairs stops at the first nil, matching
  -- kong.tracing.process_span's own traversal.
  for _, span in ipairs(spans) do
    if span.name == "kong.balancer" then
      if proxy_name then
        span.name = proxy_name
      end
      set_attr(span, "net.peer.port", peer_port)
      set_attr(span, "peer.hostname", peer_hostname)
      set_attr(span, "peer.service", peer_service)
      return
    end
  end

  -- TEMPORARY DIAGNOSTIC (remove after debugging): reaching here means no
  -- "kong.balancer" span was found. Dump the span names so we can tell whether
  -- the balancer instrumentation produced a span at all and how it is named.
  local names = {}
  for _, span in ipairs(spans) do
    names[#names + 1] = tostring(span.name)
  end
  kong.log.warn("[eni] enrich_proxy_span: no 'kong.balancer' span; ipairs=",
                #names, " spans[0]=", tostring(spans[0]),
                " names=[", table.concat(names, ", "), "]")
end

-- Decide whether this request must be excluded from sampling (admin-api), the
-- same rule the zipkin plugin applies. Returns true when sampling should be
-- forced off.
function _M.should_disable_sampling()
  local path = kong.request.get_path()
  return path:sub(1, #"/admin-api") == "/admin-api"
end

return _M
