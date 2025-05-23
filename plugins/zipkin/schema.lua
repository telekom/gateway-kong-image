-- SPDX-FileCopyrightText: 2021 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/2.8.3/kong/plugins/zipkin/schema.lua
-- Changes for Open Telekom Integration Platform are marked with 'SPDX-SnippetBegin' and '-- SPDX-SnippetEnd'

local typedefs = require "kong.db.schema.typedefs"
local Schema = require "kong.db.schema"

local PROTECTED_TAGS = {
  "error",
  "http.method",
  "http.path",
  "http.status_code",
  "kong.balancer.state",
  "kong.balancer.try",
  "kong.consumer",
  "kong.credential",
  "kong.node.id",
  "kong.route",
  "kong.service",
  "lc",
  "peer.hostname",
}

local static_tag = Schema.define {
  type = "record",
  fields = {
    { name = { type = "string", required = true, not_one_of = PROTECTED_TAGS } },
    { value = { type = "string", required = true } },
  },
}

local validate_static_tags = function(tags)
  if type(tags) ~= "table" then
    return true
  end
  local found = {}
  for i = 1, #tags do
    local name = tags[i].name
    if found[name] then
      return nil, "repeated tags are not allowed: " .. name
    end
    found[name] = true
  end
  return true
end

return {
  name = "zipkin",
  fields = {
    { config = {
        type = "record",
        fields = {
          { local_service_name = { type = "string", required = true, default = "kong" } },
          { http_endpoint = typedefs.url },
          { sample_ratio = { type = "number",
                             default = 0.001,
                             between = { 0, 1 } } },
                                        -- SPDX-SnippetBegin
                                        -- SPDX-License-Identifier: Apache-2.0
                                        -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
                                        { local_component_name = { type = "string", default = nil } },
                                        -- SPDX-SnippetEnd
                                        { default_service_name = { type = "string", default = nil } },
          { include_credential = { type = "boolean", required = true, default = true } },
          { traceid_byte_count = { type = "integer", required = true, default = 16, one_of = { 8, 16 } } },
          { header_type = { type = "string", required = true, default = "preserve",
                            one_of = { "preserve", "ignore", "b3", "b3-single", "w3c", "jaeger", "ot" } } },
          { default_header_type = { type = "string", required = true, default = "b3",
                                    one_of = { "b3", "b3-single", "w3c", "jaeger", "ot" } } },
          { tags_header = { type = "string", required = true, default = "Zipkin-Tags" } },
          -- SPDX-SnippetBegin
          -- SPDX-License-Identifier: Apache-2.0
          -- SPDX-SnippetCopyrightText: 2025 Deutsche Telekom AG
          { environment = { type = "string", default = nil } },
          { zone = { type = "string", default = nil } },
          { force_sample = { type = "boolean", default = false } },
          -- SPDX-SnippetEnd
          { static_tags = { type = "array", elements = static_tag,
                            custom_validator = validate_static_tags } },
        },
    }, },
  },
}
