-- Flatnet Gateway Sync Module
-- Handles synchronization of container info between Gateways
--
-- Usage:
--   local sync = require("flatnet.sync")
--   sync.configure(peer_endpoints)
--   sync.pull_from_peers()
--   sync.push_to_peers(container_info)

local _M = {}
local cjson = require("cjson.safe")
local http = require("resty.http")
local registry = require("flatnet.registry")

-- Configuration
local config = {
    -- List of peer Gateway endpoints
    peers = {},
    -- This host's ID
    host_id = nil,
    -- Sync interval in seconds
    sync_interval = 30,
    -- Request timeout in milliseconds
    timeout = 5000,
    -- TTL for synced containers
    sync_ttl = 300,
    -- API path
    api_path = "/api/containers"
}

-- Configure sync module
-- @param opts table: Configuration options {peers, host_id, sync_interval, timeout, sync_ttl}
function _M.configure(opts)
    if opts.peers then
        config.peers = opts.peers
    end
    if opts.host_id then
        config.host_id = opts.host_id
    end
    if opts.sync_interval then
        config.sync_interval = opts.sync_interval
    end
    if opts.timeout then
        config.timeout = opts.timeout
    end
    if opts.sync_ttl then
        config.sync_ttl = opts.sync_ttl
    end
    if opts.api_path then
        config.api_path = opts.api_path
    end
end

-- Get current configuration
function _M.get_config()
    return config
end

-- Add a peer endpoint
-- @param endpoint string: Peer endpoint URL (e.g., "http://10.100.2.1:8080")
function _M.add_peer(endpoint)
    if not endpoint then return end

    -- Check for duplicates
    for _, peer in ipairs(config.peers) do
        if peer == endpoint then
            return
        end
    end

    table.insert(config.peers, endpoint)
    ngx.log(ngx.INFO, "flatnet sync: added peer ", endpoint)
end

-- Remove a peer endpoint
-- @param endpoint string: Peer endpoint URL
function _M.remove_peer(endpoint)
    for i, peer in ipairs(config.peers) do
        if peer == endpoint then
            table.remove(config.peers, i)
            ngx.log(ngx.INFO, "flatnet sync: removed peer ", endpoint)
            return true
        end
    end
    return false
end

-- Pull container info from a single peer
-- @param endpoint string: Peer endpoint URL
-- @return table|nil, string: containers array or nil, error message
local function pull_from_peer(endpoint)
    local httpc = http.new()
    httpc:set_timeout(config.timeout)

    local uri = endpoint .. config.api_path

    local res, err = httpc:request_uri(uri, {
        method = "GET",
        headers = {
            ["Accept"] = "application/json",
            ["X-Flatnet-Host-ID"] = config.host_id or "unknown"
        }
    })

    if not res then
        return nil, "request failed: " .. (err or "unknown")
    end

    if res.status ~= 200 then
        return nil, "unexpected status: " .. res.status
    end

    local containers = cjson.decode(res.body)
    if not containers then
        return nil, "failed to parse response"
    end

    return containers
end

-- Pull container info from all peers
-- @return number, number: success count, failure count
function _M.pull_from_peers()
    local success_count = 0
    local failure_count = 0
    local total_containers = 0

    for _, endpoint in ipairs(config.peers) do
        local containers, err = pull_from_peer(endpoint)
        if containers then
            -- Register all containers from this peer
            local registered, failed = registry.bulk_register(containers, config.sync_ttl)
            total_containers = total_containers + registered
            success_count = success_count + 1
            ngx.log(ngx.INFO, "flatnet sync: pulled ", registered, " containers from ", endpoint)
        else
            failure_count = failure_count + 1
            ngx.log(ngx.WARN, "flatnet sync: failed to pull from ", endpoint, ": ", err)
        end
    end

    ngx.log(ngx.INFO, "flatnet sync: pull complete, ", total_containers, " containers from ", success_count, " peers")
    return success_count, failure_count
end

-- Push container info to a single peer
-- @param endpoint string: Peer endpoint URL
-- @param container_info table: Container info to push
-- @return boolean, string: success, error message
local function push_to_peer(endpoint, container_info)
    local httpc = http.new()
    httpc:set_timeout(config.timeout)

    local uri = endpoint .. config.api_path
    local body = cjson.encode(container_info)

    if not body then
        return false, "failed to serialize container info"
    end

    local res, err = httpc:request_uri(uri, {
        method = "POST",
        headers = {
            ["Content-Type"] = "application/json",
            ["X-Flatnet-Host-ID"] = config.host_id or "unknown"
        },
        body = body
    })

    if not res then
        return false, "request failed: " .. (err or "unknown")
    end

    if res.status >= 200 and res.status < 300 then
        return true
    end

    return false, "unexpected status: " .. res.status
end

-- Push container info to all peers
-- @param container_info table: Container info to push
-- @return number, number: success count, failure count
function _M.push_to_peers(container_info)
    local success_count = 0
    local failure_count = 0

    for _, endpoint in ipairs(config.peers) do
        local ok, err = push_to_peer(endpoint, container_info)
        if ok then
            success_count = success_count + 1
        else
            failure_count = failure_count + 1
            ngx.log(ngx.WARN, "flatnet sync: failed to push to ", endpoint, ": ", err)
        end
    end

    return success_count, failure_count
end

-- Notify peers of container deletion
-- @param container_id string: Container ID to delete
-- @return number, number: success count, failure count
function _M.notify_deletion(container_id)
    local success_count = 0
    local failure_count = 0

    for _, endpoint in ipairs(config.peers) do
        local httpc = http.new()
        httpc:set_timeout(config.timeout)

        local uri = endpoint .. config.api_path .. "/" .. container_id

        local res, err = httpc:request_uri(uri, {
            method = "DELETE",
            headers = {
                ["X-Flatnet-Host-ID"] = config.host_id or "unknown"
            }
        })

        if res and res.status >= 200 and res.status < 300 then
            success_count = success_count + 1
        else
            failure_count = failure_count + 1
            ngx.log(ngx.WARN, "flatnet sync: failed to notify deletion to ", endpoint, ": ", err or ("status " .. (res and res.status or "nil")))
        end
    end

    return success_count, failure_count
end

-- Timer callback for periodic sync
local function sync_timer_handler(premature)
    if premature then
        return
    end

    ngx.log(ngx.DEBUG, "flatnet sync: running periodic sync")

    local ok, err = pcall(function()
        _M.pull_from_peers()
    end)

    if not ok then
        ngx.log(ngx.ERR, "flatnet sync: periodic sync failed: ", err)
    end

    -- Reschedule timer
    local ok, err = ngx.timer.at(config.sync_interval, sync_timer_handler)
    if not ok then
        ngx.log(ngx.ERR, "flatnet sync: failed to reschedule sync timer: ", err)
    end
end

-- Start periodic sync timer
-- Should be called from init_worker_by_lua
function _M.start_sync_timer()
    if #config.peers == 0 then
        ngx.log(ngx.INFO, "flatnet sync: no peers configured, sync disabled")
        return
    end

    local ok, err = ngx.timer.at(config.sync_interval, sync_timer_handler)
    if not ok then
        ngx.log(ngx.ERR, "flatnet sync: failed to start sync timer: ", err)
        return
    end

    ngx.log(ngx.INFO, "flatnet sync: started periodic sync, interval=", config.sync_interval, "s, peers=", #config.peers)
end

-- Get sync status
function _M.status()
    return {
        host_id = config.host_id,
        peer_count = #config.peers,
        peers = config.peers,
        sync_interval = config.sync_interval,
        sync_ttl = config.sync_ttl,
        local_containers = registry.count()
    }
end

return _M
