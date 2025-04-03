-- SPDX-FileCopyrightText: 2020 Kong Inc.
--
-- SPDX-License-Identifier: Apache-2.0

-- Based on: https://github.com/Kong/kong/blob/2.8.3/kong/plugins/rate-limiting/expiration.lua

return {
  second = 1,
  minute = 60,
  hour   = 3600,
  day    = 86400,
  month  = 2592000,
  year   = 31536000,
}
