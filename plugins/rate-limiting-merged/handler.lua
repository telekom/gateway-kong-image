-- SPDX-FileCopyrightText: 2025 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/3.9.1/kong/plugins/rate-limiting/handler.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

-- Copyright (C) Kong Inc.
local timestamp = require "kong.tools.timestamp"
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local policies = require "kong.plugins.rate-limiting-merged.policies"
-- SPDX-SnippetEnd
local kong_meta = require "kong.meta"
local pdk_private_rl = require "kong.pdk.private.rate_limiting"


local kong = kong
local ngx = ngx
local max = math.max
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local min = math.min
-- SPDX-SnippetEnd
local time = ngx.time
local floor = math.floor
local pairs = pairs
local error = error
local tostring = tostring
local timer_at = ngx.timer.at
local SYNC_RATE_REALTIME = -1


local pdk_rl_store_response_header = pdk_private_rl.store_response_header
local pdk_rl_apply_response_headers = pdk_private_rl.apply_response_headers


local EMPTY = require("kong.tools.table").EMPTY
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local EXPIRATION = require "kong.plugins.rate-limiting-merged.expiration"
-- SPDX-SnippetEnd


local RATELIMIT_LIMIT     = "RateLimit-Limit"
local RATELIMIT_REMAINING = "RateLimit-Remaining"
local RATELIMIT_RESET     = "RateLimit-Reset"
local RETRY_AFTER         = "Retry-After"


local X_RATELIMIT_LIMIT = {
  second = "X-RateLimit-Limit-Second",
  minute = "X-RateLimit-Limit-Minute",
  hour   = "X-RateLimit-Limit-Hour",
  day    = "X-RateLimit-Limit-Day",
  month  = "X-RateLimit-Limit-Month",
  year   = "X-RateLimit-Limit-Year",
}

local X_RATELIMIT_REMAINING = {
  second = "X-RateLimit-Remaining-Second",
  minute = "X-RateLimit-Remaining-Minute",
  hour   = "X-RateLimit-Remaining-Hour",
  day    = "X-RateLimit-Remaining-Day",
  month  = "X-RateLimit-Remaining-Month",
  year   = "X-RateLimit-Remaining-Year",
}


local RateLimitingHandler = {}


RateLimitingHandler.VERSION = kong_meta.version
-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
RateLimitingHandler.PRIORITY = 910
-- SPDX-SnippetEnd


-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local function get_identifier(conf, limit_by)
  local identifier

  if limit_by == "service" then
    identifier = (kong.router.get_service() or
      EMPTY).id
  elseif limit_by == "consumer" then
    local consumer = kong.client.get_consumer() or EMPTY
    if conf.omit_consumer == (consumer.custom_id or "") then
      return nil, true
    end
    identifier = consumer.id
  end

  return identifier, nil
end


local function get_usage(conf, identifiers, limits, current_timestamp)
  local usage = {}
  local stop

  for k, v in pairs(limits) do -- Iterate over limit names
    for lk, lv in pairs(v) do -- Iterate over periods
      local current_usage, err = policies[conf.policy].usage(conf, identifiers[k], lk, current_timestamp)
      if err then
        return nil, nil, err
      end

      if not usage[lk] then
        usage[lk] = {}
      end

      -- What is the current remaining for the configured limit name?
      local remaining = lv - current_usage

      -- Recording usage, which needs to be merged with possibly existing values for period
      usage[lk].limit = min(lv, usage[lk].limit or lv)
      usage[lk].remaining = min(remaining, usage[lk].remaining or remaining)

      if remaining <= 0 then
        stop = lk
      end
    end
  end

  return usage, stop
end

local function getTableLength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end
-- SPDX-SnippetEnd


local function increment(premature, conf, ...)
  if premature then
    return
  end

  policies[conf.policy].increment(conf, ...)
end


-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
function RateLimitingHandler:access(conf)
  local current_timestamp = time() * 1000
  local fault_tolerant = conf.fault_tolerant

  local identifiers = {}
  local limits = conf.limits
  local skip
  for limit_by in pairs(limits) do
    identifiers[limit_by], skip = get_identifier(conf, limit_by)
    if skip then
      --consumer limit not applied for configured omit_consumer
      limits[limit_by] = nil
      --no more limits, can quit
      if getTableLength(limits) == 0 then
        return
      end
    end
  end

  local usage, stop, err = get_usage(conf, identifiers, limits, current_timestamp)
  if err then
    if not fault_tolerant then
      return error(err)
    end

    kong.log.err("failed to get usage: ", tostring(err))
  end

    if usage then
      -- Adding headers
      local reset
      local headers = {}
      if not conf.hide_client_headers then
        local timestamps
        local limit
        local window
        local remaining
        for k, v in pairs(usage) do
          local current_limit = v.limit
          local current_window = EXPIRATION[k]
          local current_remaining = v.remaining
          if stop == nil or stop == k then
            current_remaining = current_remaining - 1
          end
          current_remaining = max(0, current_remaining)

          if not limit or (current_remaining < remaining)
            or (current_remaining == remaining and
            current_window > window)
          then
            limit = current_limit
            window = current_window
            remaining = current_remaining

            if not timestamps then
              timestamps = timestamp.get_timestamps(current_timestamp)
            end

            reset = max(1, window - floor((current_timestamp - timestamps[k]) / 1000))
          end
          headers[X_RATELIMIT_LIMIT[k]] = current_limit
          headers[X_RATELIMIT_REMAINING[k]] = current_remaining

        end
        headers[RATELIMIT_LIMIT] = limit
        headers[RATELIMIT_REMAINING] = remaining
        headers[RATELIMIT_RESET] = reset
      end

      -- If limit is exceeded, terminate the request
      if stop then
        headers = headers or {}
        headers[RETRY_AFTER] = reset
        return kong.response.error(429, "API rate limit exceeded", headers)
      end

      kong.ctx.plugin.headers = headers
    end

  kong.ctx.plugin.current_timestamp = current_timestamp
  kong.ctx.plugin.limits = limits
  kong.ctx.plugin.identifiers = identifiers

end

function RateLimitingHandler:header_filter(conf)
  --we have to exclude request most probably stopped on other gateway from incrementing counts
  local status_code = kong.response.get_status()
  if status_code ~= 429 then
    local headers = kong.ctx.plugin.headers or {}
    local headers_remote = kong.response.get_headers() or {}
    if headers then
      for k,v in pairs(headers) do
        --merge headers from access phase with headers from other gateway
        headers[k] = min(v, headers_remote[k] or v)
      end
      kong.response.set_headers(headers)
    end

    local limits = kong.ctx.plugin.limits or {}
    local current_timestamp = kong.ctx.plugin.current_timestamp
    local identifiers = kong.ctx.plugin.identifiers
    for limit_by in pairs(limits) do -- Iterate over limit names
      local ok, err = timer_at(0, increment, conf, limits[limit_by], identifiers[limit_by], current_timestamp, 1)
      if not ok then
        kong.log.err("failed to create timer: ", err)
      end
    end

  end

end
-- SPDX-SnippetEnd


return RateLimitingHandler
