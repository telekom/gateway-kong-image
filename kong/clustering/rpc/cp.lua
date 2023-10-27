local constants = require("kong.clustering.rpc.constants")
local callbacks = require("kong.clustering.rpc.callbacks")
local connector = require("kong.clustering.rpc.connector")
local handler = require("kong.clustering.rpc.handler")
local threads = require("kong.clustering.rpc.threads")
local peer = require("kong.clustering.rpc.peer")


local META_HELLO_METHOD = constants.META_HELLO_METHOD


local _M = {}
local _MT = { __index = _M, }


function _M.new(capabilities)
  local self = {
    connector = connector.new(),

    -- kong.meta.v1.hello
    capabilities = capabilities or {},

    -- hold all dps connecting to this cp
    peers = setmetatable({}, { __mode = "k", }),
  }

  callbacks.register(META_HELLO_METHOD, function(params)
    --ngx.log(ngx.ERR, "in meta.hello")
    return self.capabilities
  end)

  return setmetatable(self, _MT)
end


function _M:connect()
  return self.connector:init()
end


-- get one dp by opts.node_id
function _M:notify(method, params, opts)
  local _, peer = next(self.peers)
  if not peer then
    return nil, "peer is not available"
  end

  return peer:notify(method, params, opts)
end


-- get one dp by opts.node_id
function _M:call(method, params, opts)
  local _, peer = next(self.peers)
  if not peer then
    return nil,{ code = constants.INTERNAL_ERROR,
                 message = "peer is not available", }
  end

  return peer:call(method, params, opts)
end


function _M:run()
  local wb, err = self:connect()
  if not wb then
    ngx.log(ngx.ERR, "[cp] wb:connect err: ", err)
    return
  end

  -- log info of dp connection
  ngx.log(ngx.ERR, "[cp] wb:connect ok")

  -- set rpc peer
  local hdl = handler.new()
  local pr = peer.new(hdl)
  local thds = threads.new(wb, hdl)

  self.peers[wb] = pr

  -- cp/dp has almost the same workflow
  thds:run()

  self.peers[wb] = nil

  wb:send_close()

  ngx.log(ngx.ERR, "close wb")

  return ngx.exit(ngx.OK)
end


return _M