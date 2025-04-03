-- SPDX-FileCopyrightText: 2022 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/tree/2.8.3/kong/plugins/prometheus/exporter.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

local kong = kong
local ngx = ngx
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local get_phase = ngx.get_phase
-- SPDX-SnippetEnd
local find = string.find
local lower = string.lower
local concat = table.concat
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
-- local select = select
-- SPDX-SnippetEnd
local ngx_timer_pending_count = ngx.timer.pending_count
local ngx_timer_running_count = ngx.timer.running_count
local balancer = require("kong.runloop.balancer")
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local yield = require("kong.tools.utils").yield
-- SPDX-SnippetEnd
local get_all_upstreams = balancer.get_all_upstreams
if not balancer.get_all_upstreams then -- API changed since after Kong 2.5
  get_all_upstreams = require("kong.runloop.balancer.upstreams").get_all_upstreams
end

local CLUSTERING_SYNC_STATUS = require("kong.constants").CLUSTERING_SYNC_STATUS

local stream_available, stream_api = pcall(require, "kong.tools.stream_api")

local role = kong.configuration.role
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
-- Reduced amount of latency buckets to reduce memory usage
local O28M_ENI_LATENCY_BUCKETS = { 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 30000, 60000 }

-- Added Special Handling for Pubsub-Horizon
local HORIZON_CONSUMER = "eventstore"
local LATENCY_OMIT_PATTERN = "-sse-"

local metrics = {}
-- prometheus.lua instance
local prometheus
local node_id = kong.node.get_id()
-- SPDX-SnippetEnd

-- use the same counter library shipped with Kong
package.loaded['prometheus_resty_counter'] = require("resty.counter")


local kong_subsystem = ngx.config.subsystem
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local http_subsystem = kong_subsystem == "http"
-- SPDX-SnippetEnd

local function init()
  local shm = "prometheus_metrics"
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  if not ngx.shared[shm] then
  -- SPDX-SnippetEnd
    kong.log.err("prometheus: ngx shared dict 'prometheus_metrics' not found")
    return
  end

  prometheus = require("kong.plugins.prometheus.prometheus").init(shm, "kong_")

  -- global metrics
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  -- Changed metrics collection
  metrics.connections = prometheus:gauge("nginx_http_current_connections",
    "Number of HTTP connections",
    {"state"},
    prometheus.LOCAL_STORAGE)
  metrics.nginx_requests_total = prometheus:gauge("nginx_requests_total",
      "Number of requests total", {"node_id", "subsystem"},
      prometheus.LOCAL_STORAGE)
  metrics.timers = prometheus:gauge("nginx_timers",
                                    "Number of nginx timers",
                                    {"state"},
                                    prometheus.LOCAL_STORAGE)
  metrics.db_reachable = prometheus:gauge("datastore_reachable",
                                          "Datastore reachable from Kong, " ..
                                          "0 is unreachable",
                                          nil,
                                          prometheus.LOCAL_STORAGE)
  metrics.node_info = prometheus:gauge("node_info",
                                       "Kong Node metadata information",
                                       {"node_id", "version"},
                                       prometheus.LOCAL_STORAGE)
                                       metrics.node_info:set(1, {node_id, kong.version})
  -- only export upstream health metrics in traditional mode and data plane
  if role ~= "control_plane" then
    metrics.upstream_target_health = prometheus:gauge("upstream_target_health",
                                            "Health status of targets of upstream. " ..
                                            "States = healthchecks_off|healthy|unhealthy|dns_error, " ..
                                            "value is 1 when state is populated.",
                                            {"upstream", "target", "address", "state", "subsystem"},
                                            prometheus.LOCAL_STORAGE)
  end
  -- SPDX-SnippetEnd

  local memory_stats = {}
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  -- Adding node_id to memory stats
  memory_stats.worker_vms = prometheus:gauge("memory_workers_lua_vms_bytes",
                                             "Allocated bytes in worker Lua VM",
                                             {"node_id", "pid", "kong_subsystem"},
                                             prometheus.LOCAL_STORAGE)
  memory_stats.shms = prometheus:gauge("memory_lua_shared_dict_bytes",
                                       "Allocated slabs in bytes in a shared_dict",
                                       {"node_id", "shared_dict", "kong_subsystem"},
                                       prometheus.LOCAL_STORAGE)
  memory_stats.shm_capacity = prometheus:gauge("memory_lua_shared_dict_total_bytes",
                                               "Total capacity in bytes of a shared_dict",
                                               {"node_id", "shared_dict", "kong_subsystem"},
                                               prometheus.LOCAL_STORAGE)

  local res = kong.node.get_memory_stats()
  for shm_name, value in pairs(res.lua_shared_dicts) do
    memory_stats.shm_capacity:set(value.capacity, { node_id, shm_name, kong_subsystem })
  end
  -- SPDX-SnippetEnd

  metrics.memory_stats = memory_stats

  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  -- Adding new tags to metrics
  metrics.status = prometheus:counter("http_requests_total",
    "HTTP status codes per consumer/method/route in Kong",
    {"route", "method", "consumer", "source", "code"})

  metrics.latency = prometheus:histogram("request_latency_ms",
    "Total latency incurred during requests " ..
      "for each route in Kong",
    {"route", "method", "consumer"},
          O28M_ENI_LATENCY_BUCKETS)

  metrics.bandwidth = prometheus:counter("bandwidth_bytes",
    "Total bandwidth (ingress/egress) " ..
      "throughput in bytes",
    {"route", "direction", "consumer"})
  -- SPDX-SnippetEnd

  -- Hybrid mode status
  if role == "control_plane" then
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    -- Adding prometheus.LOCAL_STORAGE to gauges
    metrics.data_plane_last_seen = prometheus:gauge("data_plane_last_seen",
                                              "Last time data plane contacted control plane",
                                              {"node_id", "hostname", "ip"},
                                              prometheus.LOCAL_STORAGE)
    metrics.data_plane_config_hash = prometheus:gauge("data_plane_config_hash",
                                              "Config hash numeric value of the data plane",
                                              {"node_id", "hostname", "ip"},
                                              prometheus.LOCAL_STORAGE)

    metrics.data_plane_version_compatible = prometheus:gauge("data_plane_version_compatible",
                                              "Version compatible status of the data plane, 0 is incompatible",
                                              {"node_id", "hostname", "ip", "kong_version"},
                                              prometheus.LOCAL_STORAGE)
  elseif role == "data_plane" then
    local data_plane_cluster_cert_expiry_timestamp = prometheus:gauge(
      "data_plane_cluster_cert_expiry_timestamp",
      "Unix timestamp of Data Plane's cluster_cert expiry time",
      nil,
      prometheus.LOCAL_STORAGE)
    -- SPDX-SnippetEnd

    -- The cluster_cert doesn't change once Kong starts.
    -- We set this metrics just once to avoid file read in each scrape.
    local f = assert(io.open(kong.configuration.cluster_cert))
    local pem = assert(f:read("*a"))
    f:close()
    local x509 = require("resty.openssl.x509")
    local cert = assert(x509.new(pem, "PEM"))
    local not_after = assert(cert:get_not_after())
    data_plane_cluster_cert_expiry_timestamp:set(not_after)
  end
end

local function init_worker()
  prometheus:init_worker()
end

-- Convert the MD5 hex string to its numeric representation
-- Note the following will be represented as a float instead of int64 since luajit
-- don't like int64. Good news is prometheus uses float instead of int64 as well
local function config_hash_to_number(hash_str)
  return tonumber("0x" .. hash_str)
end

-- Since in the prometheus library we create a new table for each diverged label
-- so putting the "more dynamic" label at the end will save us some memory
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local labels_table_bandwidth = {0, 0, 0}
local labels_table_status = {0, 0, 0, 0, 0}
local labels_table_latency = {0, 0, 0}
-- SPDX-SnippetEnd
local upstream_target_addr_health_table = {
  { value = 0, labels = { 0, 0, 0, "healthchecks_off", ngx.config.subsystem } },
  { value = 0, labels = { 0, 0, 0, "healthy", ngx.config.subsystem } },
  { value = 0, labels = { 0, 0, 0, "unhealthy", ngx.config.subsystem } },
  { value = 0, labels = { 0, 0, 0, "dns_error", ngx.config.subsystem } },
}

local function set_healthiness_metrics(table, upstream, target, address, status, metrics_bucket)
  for i = 1, #table do
    table[i]['labels'][1] = upstream
    table[i]['labels'][2] = target
    table[i]['labels'][3] = address
    table[i]['value'] = (status == table[i]['labels'][4]) and 1 or 0
    metrics_bucket:set(table[i]['value'], table[i]['labels'])
  end
end

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local function log(message, serialized)
  if not metrics then
    kong.log.err("prometheus: can not log metrics because of an initialization "
      .. "error, please make sure that you've declared "
      .. "'prometheus_metrics' shared dict in your nginx template")
    return
  end

  local service_name
  if message and message.service then
    service_name = message.service.name or message.service.host
  else
    -- do not record any stats if the service is not present
    return
  end

  local route_name
  if message and message.route then
    route_name = message.route.name or message.route.id
  end

  local consumer = ""
  if http_subsystem then
    if message and serialized.consumer ~= nil then
      consumer = serialized.consumer
      -- Horizon part start
      if consumer == HORIZON_CONSUMER then
        local pubsub_consumer = ngx.var.http_x_pubsub_subscriber_id
        if pubsub_consumer then
          consumer = HORIZON_CONSUMER .. ":" .. pubsub_consumer
        end
      end
      -- Horizon part start
    end
  else
    consumer = nil -- no consumer in stream
  end

  if serialized.status_code then
    labels_table_status[1] = route_name
    labels_table_status[2] = serialized.method
    labels_table_status[3] = consumer

    if kong.response.get_source() == "service" then
      labels_table_status[4] = "service"
    else
      labels_table_status[4] = "kong"
    end

    labels_table_status[5] = serialized.status_code
    metrics.status:inc(1, labels_table_status)
  end

  if serialized.ingress_size or serialized.egress_size then
    labels_table_bandwidth[1] = route_name
    labels_table_bandwidth[3] = consumer

    local ingress_size = serialized.ingress_size
    if ingress_size and ingress_size > 0 then
      labels_table_bandwidth[2] = "ingress"
      metrics.bandwidth:inc(ingress_size, labels_table_bandwidth)
    end

    local egress_size = serialized.egress_size
    if egress_size and egress_size > 0 then
      labels_table_bandwidth[2] = "egress"
      metrics.bandwidth:inc(egress_size, labels_table_bandwidth)
    end
  end

  if serialized.latencies and not find(route_name, LATENCY_OMIT_PATTERN) then
    labels_table_latency[1] = route_name
    labels_table_latency[2] = serialized.method
    labels_table_latency[3] = consumer

    if http_subsystem then
      local request_latency = serialized.latencies.request
      if request_latency and request_latency >= 0 then
        metrics.latency:observe(request_latency, labels_table_latency)
      end
    end
  end
end

-- The upstream health metrics is turned on if at least one of
-- the plugin turns upstream_health_metrics on.
-- Due to the fact that during scrape time we don't want to
-- iterrate over all plugins to find out if upstream_health_metrics
-- is turned on or not, we will need a Kong reload if someone
-- turned on upstream_health_metrics on and off again, to actually
-- stop exporting upstream health metrics
local should_export_upstream_health_metrics = false


local function metric_data(write_fn)
  -- SPDX-SnippetEnd
  if not prometheus or not metrics then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                 " 'prometheus_metrics' shared dict is present in nginx template")
    return kong.response.exit(500, { message = "An unexpected error occurred" })
  end

  if ngx.location then
    local r = ngx.location.capture "/nginx_status"

    if r.status ~= 200 then
      kong.log.warn("prometheus: failed to retrieve /nginx_status ",
        "while processing /metrics endpoint")

    else
      local accepted, handled, total = select(3, find(r.body,
        "accepts handled requests\n (%d*) (%d*) (%d*)"))
      metrics.connections:set(accepted, { "accepted" })
      metrics.connections:set(handled, { "handled" })
      metrics.connections:set(total, { "total" })
    end
  end

  metrics.connections:set(ngx.var.connections_active or 0, { "active" })
  metrics.connections:set(ngx.var.connections_reading or 0, { "reading" })
  metrics.connections:set(ngx.var.connections_writing or 0, { "writing" })
  metrics.connections:set(ngx.var.connections_waiting or 0, { "waiting" })

  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  if http_subsystem then -- only export those metrics once in http as they are shared
    metrics.timers:set(ngx_timer_running_count(), {"running"})
    metrics.timers:set(ngx_timer_pending_count(), {"pending"})

    -- db reachable?
    local ok, err = kong.db.connector:connect()
    if ok then
      metrics.db_reachable:set(1)

    else
      metrics.db_reachable:set(0)
      kong.log.err("prometheus: failed to reach database while processing",
                 "/metrics endpoint: ", err)
    end
  end

  local phase = get_phase()

  -- only export upstream health metrics in traditional mode and data plane
  if role ~= "control_plane" and should_export_upstream_health_metrics then
    -- erase all target/upstream metrics, prevent exposing old metrics
    metrics.upstream_target_health:reset()

    -- upstream targets accessible?
    local upstreams_dict = get_all_upstreams()
    for key, upstream_id in pairs(upstreams_dict) do
      -- long loop maybe spike proxy request latency, so we
      -- need yield to avoid blocking other requests
      -- kong.tools.utils.yield(true)
      yield(true, phase)
      local _, upstream_name = key:match("^([^:]*):(.-)$")
      upstream_name = upstream_name and upstream_name or key
      -- based on logic from kong.db.dao.targets
      local health_info, err = balancer.get_upstream_health(upstream_id)
      -- SPDX-SnippetEnd
      if err then
        kong.log.err("failed getting upstream health: ", err)
      end

      if health_info then
        for target_name, target_info in pairs(health_info) do
          if target_info ~= nil and target_info.addresses ~= nil and
            #target_info.addresses > 0 then
            -- healthchecks_off|healthy|unhealthy
            for _, address in ipairs(target_info.addresses) do
              local address_label = concat({address.ip, ':', address.port})
              local status = lower(address.health)
              set_healthiness_metrics(upstream_target_addr_health_table, upstream_name, target_name, address_label, status, metrics.upstream_target_health)
            end
          else
            -- dns_error
            set_healthiness_metrics(upstream_target_addr_health_table, upstream_name, target_name, '', 'dns_error', metrics.upstream_target_health)
          end
        end
      end
    end
  end

  -- memory stats
  local res = kong.node.get_memory_stats()
  for shm_name, value in pairs(res.lua_shared_dicts) do
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    metrics.memory_stats.shms:set(value.allocated_slabs, { node_id, shm_name, kong_subsystem })
    -- SPDX-SnippetEnd
  end
  for i = 1, #res.workers_lua_vms do
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    metrics.memory_stats.worker_vms:set(res.workers_lua_vms[i].http_allocated_gc,
    { node_id, res.workers_lua_vms[i].pid, kong_subsystem })
    -- SPDX-SnippetEnd
  end

  -- Hybrid mode status
  if role == "control_plane" then
    -- Cleanup old metrics
    metrics.data_plane_last_seen:reset()
    metrics.data_plane_config_hash:reset()
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    metrics.data_plane_version_compatible:reset()
    -- SPDX-SnippetEnd

    for data_plane, err in kong.db.clustering_data_planes:each() do
      if err then
        kong.log.err("failed to list data planes: ", err)
        goto next_data_plane
      end

      local labels = { data_plane.id, data_plane.hostname, data_plane.ip }

      metrics.data_plane_last_seen:set(data_plane.last_seen, labels)
      metrics.data_plane_config_hash:set(config_hash_to_number(data_plane.config_hash), labels)

      labels[4] = data_plane.version
      local compatible = 1

      if data_plane.sync_status == CLUSTERING_SYNC_STATUS.KONG_VERSION_INCOMPATIBLE
        or data_plane.sync_status == CLUSTERING_SYNC_STATUS.PLUGIN_SET_INCOMPATIBLE
        or data_plane.sync_status == CLUSTERING_SYNC_STATUS.PLUGIN_VERSION_INCOMPATIBLE then

        compatible = 0
      end
      metrics.data_plane_version_compatible:set(compatible, labels)

::next_data_plane::
    end
  end

  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  prometheus:metric_data(write_fn)
  -- SPDX-SnippetEnd
end

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local function collect()
  ngx.header["Content-Type"] = "text/plain; charset=UTF-8"

  metric_data()

  -- only gather stream metrics if stream_api module is available
  -- and user has configured at least one stream listeners
  -- SPDX-SnippetEnd
  if stream_available and #kong.configuration.stream_listeners > 0 then
    local res, err = stream_api.request("prometheus", "")
    if err then
      kong.log.err("failed to collect stream metrics: ", err)
    else
      ngx.print(res)
    end
  end
end

local function get_prometheus()
  if not prometheus then
    kong.log.err("prometheus: plugin is not initialized, please make sure ",
                     " 'prometheus_metrics' shared dict is present in nginx template")
  end
  return prometheus
end

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local function set_export_upstream_health_metrics(set_or_not)
  should_export_upstream_health_metrics = set_or_not
end
-- SPDX-SnippetEnd

return {
  init        = init,
  init_worker = init_worker,
  log         = log,
  metric_data = metric_data,
  collect     = collect,
  get_prometheus = get_prometheus,
  -- SPDX-SnippetBegin
  -- SPDX-License-Identifier: Apache-2.0
  -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
  set_export_upstream_health_metrics = set_export_upstream_health_metrics
  -- SPDX-SnippetEnd
}
