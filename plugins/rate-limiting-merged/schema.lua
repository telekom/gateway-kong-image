-- SPDX-FileCopyrightText: 2025 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/3.9.1/kong/plugins/rate-limiting/schema.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

local typedefs = require "kong.db.schema.typedefs"

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
local ORDERED_PERIODS = { "second", "minute", "hour" }
-- SPDX-SnippetEnd

local function validate_periods_order(config)
  for i, lower_period in ipairs(ORDERED_PERIODS) do
    local v1 = config[lower_period]
    if type(v1) == "number" then
      for j = i + 1, #ORDERED_PERIODS do
        local upper_period = ORDERED_PERIODS[j]
        local v2 = config[upper_period]
        if type(v2) == "number" and v2 < v1 then
          -- SPDX-SnippetBegin
          -- SPDX-License-Identifier: Apache-2.0
          -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
          return nil, string.format("The limit for %s(%.1f) cannot be lower than the limit for %s(%.1f)",
            upper_period, v2, lower_period, v1)
          -- SPDX-SnippetEnd
        end
      end
    end
  end

  return true
end

local function is_dbless()
  local _, database, role = pcall(function()
    return kong.configuration.database,
    -- SPDX-SnippetBegin
    -- SPDX-License-Identifier: Apache-2.0
    -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
    kong.configuration.role
    -- SPDX-SnippetEnd
  end)

  return database == "off" or role == "control_plane"
end

local policy
if is_dbless() then
  policy = {
    type = "string",
    default = "local",
    len_min = 0,
    one_of = {
      "local",
      "redis",
    },
  }
else
  policy = {
    type = "string",
    default = "local",
    len_min = 0,
    one_of = {
      "local",
      "cluster",
      "redis",
    },
  }
end

-- SPDX-SnippetBegin
-- SPDX-License-Identifier: Apache-2.0
-- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
return {
  name = "rate-limiting-merged",
  fields = {
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
      { policy = policy },
      { fault_tolerant = { type = "boolean", required = true, default = true }, },
      { redis_host = typedefs.host },
      { redis_port = typedefs.port({ default = 6379 }), },
      { redis_password = { type = "string", len_min = 0, referenceable = true }, },
      { redis_username = { type = "string", referenceable = true }, },
      { redis_ssl = { type = "boolean", required = true, default = false, }, },
      { redis_ssl_verify = { type = "boolean", required = true, default = false }, },
      { redis_server_name = typedefs.sni },
      { redis_timeout = { type = "number", default = 2000, }, },
      { redis_database = { type = "integer", default = 0 }, },
      { hide_client_headers = { type = "boolean", required = true, default = false }, },
      { omit_consumer = { type = "string", required = true, default = "gateway" }, },
      { limits = {
        type = "map",
        required = true,
        len_min = 1,
        keys = { type = "string", one_of = {
          "service",
          "consumer",
        }, },
        values = {
          type = "record",
          required = true,
          fields = {
            { second = { type = "number", gt = 0 }, },
            { minute = { type = "number", gt = 0 }, },
            { hour = { type = "number", gt = 0 }, },
          },
          custom_validator = validate_periods_order,
          entity_checks = {
            { at_least_one_of = ORDERED_PERIODS },
          },
        },
      },
      }
    },
      custom_validator = validate_periods_order,
    },
  },
},
}
-- SPDX-SnippetEnd