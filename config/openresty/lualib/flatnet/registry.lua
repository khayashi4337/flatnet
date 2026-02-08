-- Flatnet Container Registry
-- Manages container information for multihost routing
--
-- Usage:
--   local registry = require("flatnet.registry")
--   registry.register(container_info)
--   registry.deregister(container_id)
--   local containers = registry.get_all()
--   local container = registry.get_by_ip(ip)

local _M = {}
local cjson = require("cjson.safe")

-- Shared dict for container data (configured in nginx.conf)
local SHARED_DICT_NAME = "flatnet_containers"

-- Default TTL for container entries (5 minutes)
local DEFAULT_TTL = 300

-- Maximum container info size (16KB - prevents memory abuse)
local MAX_INFO_SIZE = 16 * 1024

-- Container index prefix keys
local INDEX_BY_IP = "ip:"
local INDEX_BY_HOST = "host:"
local CONTAINER_PREFIX = "container:"
local CONTAINER_LIST_KEY = "container_list"
local LOCK_PREFIX = "lock:"

-- Lock timeout in seconds
local LOCK_TIMEOUT = 5
-- Lock retry interval in seconds
local LOCK_RETRY_INTERVAL = 0.01

-- Get shared dict with error handling
local function get_shared_dict()
    local dict = ngx.shared[SHARED_DICT_NAME]
    if not dict then
        ngx.log(ngx.ERR, "flatnet registry: shared dict '", SHARED_DICT_NAME, "' not configured")
        return nil, "shared dict not configured"
    end
    return dict
end

-- Acquire a simple spinlock for list operations
-- Uses dict:add() which is atomic - only succeeds if key doesn't exist
-- @param dict shared dict
-- @param lock_key lock key name
-- @return boolean success
local function acquire_lock(dict, lock_key)
    local deadline = ngx.now() + LOCK_TIMEOUT
    while ngx.now() < deadline do
        -- add() is atomic: only succeeds if key doesn't exist
        local ok, err = dict:add(lock_key, 1, LOCK_TIMEOUT)
        if ok then
            return true
        end
        -- Wait before retry
        ngx.sleep(LOCK_RETRY_INTERVAL)
    end
    ngx.log(ngx.WARN, "flatnet registry: failed to acquire lock ", lock_key)
    return false
end

-- Release lock
local function release_lock(dict, lock_key)
    dict:delete(lock_key)
end

-- Remove an ID from a comma-separated list safely
-- Handles edge cases: first item, middle item, last item, only item
local function remove_from_list(list, id)
    if not list or list == "" then
        return ""
    end

    -- Split into array
    local items = {}
    for item in list:gmatch("[^,]+") do
        if item ~= id then
            table.insert(items, item)
        end
    end

    return table.concat(items, ",")
end

-- Register a container
-- @param info table: Container info {id, ip, hostname, ports, hostId, createdAt}
-- @param ttl number: Optional TTL in seconds (default: 300)
-- @return boolean, string: success, error message
function _M.register(info, ttl)
    if not info or not info.id or not info.ip then
        return false, "container info must have id and ip"
    end

    local dict, err = get_shared_dict()
    if not dict then
        return false, err
    end

    ttl = ttl or DEFAULT_TTL

    -- Serialize container info
    local data = cjson.encode(info)
    if not data then
        return false, "failed to serialize container info"
    end

    -- Check serialized data size to prevent memory abuse
    if #data > MAX_INFO_SIZE then
        return false, "container info too large (max " .. MAX_INFO_SIZE .. " bytes)"
    end

    -- Store container data
    local container_key = CONTAINER_PREFIX .. info.id
    local ok, err = dict:set(container_key, data, ttl)
    if not ok then
        return false, "failed to store container: " .. (err or "unknown")
    end

    -- Create IP index
    local ip_key = INDEX_BY_IP .. info.ip
    ok, err = dict:set(ip_key, info.id, ttl)
    if not ok then
        ngx.log(ngx.WARN, "flatnet registry: failed to create IP index: ", err)
    end

    -- Create host index (add to list) with lock to prevent race condition
    -- Note: hostId defaults to 1 for containers without explicit host ID
    local host_id = info.hostId or 1
    local host_key = INDEX_BY_HOST .. host_id
    local host_lock_key = LOCK_PREFIX .. host_key

    if acquire_lock(dict, host_lock_key) then
        local host_list = dict:get(host_key) or ""
        if not host_list:find(info.id, 1, true) then
            host_list = host_list == "" and info.id or (host_list .. "," .. info.id)
            dict:set(host_key, host_list, ttl)
        end
        release_lock(dict, host_lock_key)
    else
        ngx.log(ngx.WARN, "flatnet registry: skipped host index update due to lock timeout")
    end

    -- Add to global container list with lock
    local list_lock_key = LOCK_PREFIX .. CONTAINER_LIST_KEY

    if acquire_lock(dict, list_lock_key) then
        local container_list = dict:get(CONTAINER_LIST_KEY) or ""
        if not container_list:find(info.id, 1, true) then
            container_list = container_list == "" and info.id or (container_list .. "," .. info.id)
            dict:set(CONTAINER_LIST_KEY, container_list, 0)  -- No TTL for the list
        end
        release_lock(dict, list_lock_key)
    else
        ngx.log(ngx.WARN, "flatnet registry: skipped container list update due to lock timeout")
    end

    ngx.log(ngx.INFO, "flatnet registry: registered container ", info.id, " with IP ", info.ip)
    return true
end

-- Deregister a container
-- @param container_id string: Container ID
-- @return boolean, string: success, error message
function _M.deregister(container_id)
    if not container_id then
        return false, "container_id is required"
    end

    local dict, err = get_shared_dict()
    if not dict then
        return false, err
    end

    -- Get container info first (for index cleanup)
    local container_key = CONTAINER_PREFIX .. container_id
    local data = dict:get(container_key)

    if data then
        local info = cjson.decode(data)
        if info then
            -- Remove IP index
            if info.ip then
                dict:delete(INDEX_BY_IP .. info.ip)
            end

            -- Remove from host index with lock
            if info.hostId then
                local host_key = INDEX_BY_HOST .. info.hostId
                local host_lock_key = LOCK_PREFIX .. host_key

                if acquire_lock(dict, host_lock_key) then
                    local host_list = dict:get(host_key) or ""
                    host_list = remove_from_list(host_list, container_id)
                    if host_list == "" then
                        dict:delete(host_key)
                    else
                        dict:set(host_key, host_list, 0)
                    end
                    release_lock(dict, host_lock_key)
                else
                    ngx.log(ngx.WARN, "flatnet registry: skipped host index cleanup due to lock timeout")
                end
            end
        end
    end

    -- Remove container data
    dict:delete(container_key)

    -- Remove from global list with lock
    local list_lock_key = LOCK_PREFIX .. CONTAINER_LIST_KEY

    if acquire_lock(dict, list_lock_key) then
        local container_list = dict:get(CONTAINER_LIST_KEY) or ""
        container_list = remove_from_list(container_list, container_id)
        dict:set(CONTAINER_LIST_KEY, container_list, 0)
        release_lock(dict, list_lock_key)
    else
        ngx.log(ngx.WARN, "flatnet registry: skipped container list cleanup due to lock timeout")
    end

    ngx.log(ngx.INFO, "flatnet registry: deregistered container ", container_id)
    return true
end

-- Get container by ID
-- @param container_id string: Container ID
-- @return table|nil, string|nil: Container info or nil, error message
function _M.get(container_id)
    if not container_id then
        return nil, "container_id is required"
    end

    local dict, err = get_shared_dict()
    if not dict then
        return nil, err
    end

    local container_key = CONTAINER_PREFIX .. container_id
    local data = dict:get(container_key)
    if not data then
        return nil, nil  -- Not found (not an error)
    end

    local info, decode_err = cjson.decode(data)
    if not info then
        ngx.log(ngx.ERR, "flatnet registry: corrupted data for container ", container_id, ": ", decode_err)
        -- Clean up corrupted entry
        dict:delete(container_key)
        return nil, "corrupted container data"
    end

    return info
end

-- Get container by IP address
-- @param ip string: IP address
-- @return table|nil: Container info or nil if not found
function _M.get_by_ip(ip)
    if not ip then
        return nil
    end

    local dict, err = get_shared_dict()
    if not dict then
        return nil
    end

    local ip_key = INDEX_BY_IP .. ip
    local container_id = dict:get(ip_key)
    if not container_id then
        return nil
    end

    return _M.get(container_id)
end

-- Get all containers
-- @return table: Array of container info objects
function _M.get_all()
    local dict, err = get_shared_dict()
    if not dict then
        return {}
    end

    local container_list = dict:get(CONTAINER_LIST_KEY) or ""
    if container_list == "" then
        return {}
    end

    local containers = {}
    for container_id in container_list:gmatch("[^,]+") do
        local info = _M.get(container_id)
        if info then
            table.insert(containers, info)
        end
    end

    return containers
end

-- Get containers by host ID
-- @param host_id number: Host ID
-- @return table: Array of container info objects for this host
function _M.get_by_host(host_id)
    local dict, err = get_shared_dict()
    if not dict then
        return {}
    end

    local host_key = INDEX_BY_HOST .. host_id
    local host_list = dict:get(host_key) or ""
    if host_list == "" then
        return {}
    end

    local containers = {}
    for container_id in host_list:gmatch("[^,]+") do
        local info = _M.get(container_id)
        if info then
            table.insert(containers, info)
        end
    end

    return containers
end

-- Get container count
-- @return number: Total container count
function _M.count()
    local dict, err = get_shared_dict()
    if not dict then
        return 0
    end

    local container_list = dict:get(CONTAINER_LIST_KEY) or ""
    if container_list == "" then
        return 0
    end

    local count = 0
    for _ in container_list:gmatch("[^,]+") do
        count = count + 1
    end

    return count
end

-- Bulk register containers (for sync)
-- @param containers table: Array of container info objects
-- @param ttl number: Optional TTL in seconds
-- @return number, number: success count, failure count
function _M.bulk_register(containers, ttl)
    local success_count = 0
    local failure_count = 0

    for _, info in ipairs(containers) do
        local ok, err = _M.register(info, ttl)
        if ok then
            success_count = success_count + 1
        else
            failure_count = failure_count + 1
            ngx.log(ngx.WARN, "flatnet registry: bulk register failed for ", info.id or "unknown", ": ", err)
        end
    end

    return success_count, failure_count
end

-- Clear all containers
-- @return boolean: success
function _M.clear()
    local dict, err = get_shared_dict()
    if not dict then
        return false
    end

    dict:flush_all()
    ngx.log(ngx.INFO, "flatnet registry: cleared all containers")
    return true
end

-- Get registry stats
-- @return table: Stats {count, memory_used, shared_dict_name}
function _M.stats()
    local dict, err = get_shared_dict()
    if not dict then
        return {count = 0, error = err}
    end

    return {
        count = _M.count(),
        shared_dict_name = SHARED_DICT_NAME,
        free_space = dict:free_space(),
        capacity = dict:capacity and dict:capacity() or "unknown"
    }
end

return _M
