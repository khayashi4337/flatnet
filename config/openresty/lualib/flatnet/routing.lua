-- Flatnet Routing Module
-- Determines routing path based on connection state
--
-- Routes:
--   - P2P_ACTIVE: Direct route to container via Nebula tunnel
--   - Others: Route via Gateway
--
-- Usage:
--   local routing = require("flatnet.routing")
--   local route = routing.get_route(container_ip)

local _M = {}
local bit = require("bit")
local escalation = require("flatnet.escalation")
local registry = require("flatnet.registry")

-- Route types
_M.ROUTE_TYPE = {
    P2P = "p2p",
    GATEWAY = "gateway",
    LOCAL = "local",
    UNKNOWN = "unknown"
}

-- Configuration
local config = {
    -- Local host ID (containers on this host are accessed directly)
    local_host_id = nil,
    -- Gateway mappings: host_id -> gateway_ip
    gateway_map = {},
    -- Default gateway (if host not in map)
    default_gateway = nil,
    -- Local subnet (containers in this subnet are local)
    local_subnet = "10.87.1.0/24",
    -- P2P timeout for new connections (seconds)
    p2p_attempt_delay = 1,
}

-- Parse CIDR notation and check if IP is in subnet
-- @param ip string: IP address to check
-- @param cidr string: CIDR notation (e.g., "10.87.1.0/24")
-- @return boolean: True if IP is in subnet
local function ip_in_subnet(ip, cidr)
    if not ip or not cidr then
        return false
    end

    local subnet, prefix = cidr:match("^([%d%.]+)/(%d+)$")
    if not subnet or not prefix then
        return false
    end

    prefix = tonumber(prefix)
    if not prefix or prefix < 0 or prefix > 32 then
        return false
    end

    -- Convert IP strings to numbers
    local function ip_to_num(ip_str)
        local a, b, c, d = ip_str:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
        if not a then return nil end
        a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
        if not a or not b or not c or not d then return nil end
        if a > 255 or b > 255 or c > 255 or d > 255 then return nil end
        return a * 16777216 + b * 65536 + c * 256 + d
    end

    local ip_num = ip_to_num(ip)
    local subnet_num = ip_to_num(subnet)
    if not ip_num or not subnet_num then
        return false
    end

    -- Create mask
    local mask = 0xFFFFFFFF - (2^(32 - prefix) - 1)

    -- Check if IP is in subnet
    local ip_masked = bit.band(ip_num, mask)
    local subnet_masked = bit.band(subnet_num, mask)

    return ip_masked == subnet_masked
end

-- Configure routing module
-- @param opts table: Configuration options
function _M.configure(opts)
    if not opts then return end

    if opts.local_host_id then
        config.local_host_id = opts.local_host_id
    end
    if opts.gateway_map then
        config.gateway_map = opts.gateway_map
    end
    if opts.default_gateway then
        config.default_gateway = opts.default_gateway
    end
    if opts.local_subnet then
        config.local_subnet = opts.local_subnet
    end
    if opts.p2p_attempt_delay then
        config.p2p_attempt_delay = opts.p2p_attempt_delay
    end
end

-- Get current configuration
function _M.get_config()
    return config
end

-- Add gateway mapping
-- @param host_id number|string: Host ID
-- @param gateway_ip string: Gateway IP address
function _M.add_gateway(host_id, gateway_ip)
    config.gateway_map[tostring(host_id)] = gateway_ip
    ngx.log(ngx.INFO, "flatnet routing: added gateway ", gateway_ip, " for host ", host_id)
end

-- Remove gateway mapping
-- @param host_id number|string: Host ID
function _M.remove_gateway(host_id)
    config.gateway_map[tostring(host_id)] = nil
    ngx.log(ngx.INFO, "flatnet routing: removed gateway for host ", host_id)
end

-- Get gateway for a host
-- @param host_id number|string: Host ID
-- @return string|nil: Gateway IP or nil
function _M.get_gateway_for_host(host_id)
    if not host_id then
        return config.default_gateway
    end
    return config.gateway_map[tostring(host_id)] or config.default_gateway
end

-- Get gateway for a container IP
-- @param container_ip string: Container IP address
-- @return string|nil: Gateway IP or nil
function _M.get_gateway_for(container_ip)
    if not container_ip then
        return config.default_gateway
    end

    -- Look up container in registry to get host ID
    local container = registry.get_by_ip(container_ip)
    if container and container.hostId then
        return _M.get_gateway_for_host(container.hostId)
    end

    return config.default_gateway
end

-- Check if container is local (on this host)
-- @param container_ip string: Container IP address
-- @return boolean: True if container is local
function _M.is_local(container_ip)
    if not container_ip then
        return false
    end

    -- Check if IP is in local subnet
    if config.local_subnet and ip_in_subnet(container_ip, config.local_subnet) then
        return true
    end

    -- Check registry for host ID
    local container = registry.get_by_ip(container_ip)
    if container and container.hostId then
        return tostring(container.hostId) == tostring(config.local_host_id)
    end

    return false
end

-- Get route for a container IP
-- @param container_ip string: Container IP address
-- @param opts table: Optional settings {skip_p2p_attempt}
-- @return table: Route info {type, target, state, container}
function _M.get_route(container_ip, opts)
    opts = opts or {}

    if not container_ip then
        return {
            type = _M.ROUTE_TYPE.UNKNOWN,
            target = nil,
            state = nil,
            error = "container_ip is required"
        }
    end

    -- Check if container is local
    if _M.is_local(container_ip) then
        return {
            type = _M.ROUTE_TYPE.LOCAL,
            target = container_ip,
            state = "LOCAL",
            container = registry.get_by_ip(container_ip)
        }
    end

    -- Get connection state
    local state = escalation.get_state(container_ip)

    -- Determine route based on state
    if state == escalation.STATE.P2P_ACTIVE then
        -- Route directly via P2P
        return {
            type = _M.ROUTE_TYPE.P2P,
            target = container_ip,
            state = state,
            container = registry.get_by_ip(container_ip)
        }
    end

    -- All other states route via Gateway
    local gateway = _M.get_gateway_for(container_ip)

    -- If GATEWAY_ONLY and P2P attempt is allowed, start P2P attempt in background
    if state == escalation.STATE.GATEWAY_ONLY and not opts.skip_p2p_attempt then
        -- Schedule P2P attempt (non-blocking)
        local timer_ok, timer_err = ngx.timer.at(config.p2p_attempt_delay, function(premature)
            if premature then
                return
            end
            local ok, err = escalation.attempt_p2p(container_ip, gateway)
            if not ok then
                ngx.log(ngx.DEBUG, "flatnet routing: P2P attempt for ", container_ip, " failed: ", err)
            end
        end)
        if not timer_ok then
            ngx.log(ngx.WARN, "flatnet routing: failed to schedule P2P attempt: ", timer_err)
        end
    end

    return {
        type = _M.ROUTE_TYPE.GATEWAY,
        target = gateway,
        state = state,
        container = registry.get_by_ip(container_ip)
    }
end

-- Get upstream for nginx proxy
-- @param container_ip string: Container IP address
-- @param port number: Target port (default: 80)
-- @return string: Upstream URL (e.g., "http://10.87.1.2:80")
function _M.get_upstream(container_ip, port)
    port = port or 80

    local route = _M.get_route(container_ip)

    if route.type == _M.ROUTE_TYPE.P2P or route.type == _M.ROUTE_TYPE.LOCAL then
        -- Direct route to container
        return "http://" .. container_ip .. ":" .. port
    elseif route.type == _M.ROUTE_TYPE.GATEWAY and route.target then
        -- Route via gateway
        -- Gateway will proxy to container based on X-Flatnet-Target header
        return "http://" .. route.target .. ":8080"
    end

    -- Fallback: try direct route
    return "http://" .. container_ip .. ":" .. port
end

-- Check route and update escalation state
-- Called after a request to update state based on result
-- @param container_ip string: Container IP address
-- @param success boolean: Whether the request succeeded
-- @param latency number: Request latency in milliseconds (optional)
function _M.update_route_status(container_ip, success, latency)
    if not container_ip then
        return
    end

    local state = escalation.get_state(container_ip)

    if state == escalation.STATE.P2P_ATTEMPTING then
        if success then
            -- P2P connection successful
            escalation.activate_p2p(container_ip)
        else
            -- P2P attempt failed
            escalation.reset_to_gateway_only(container_ip, "P2P attempt failed")
        end
    elseif state == escalation.STATE.P2P_ACTIVE then
        if not success then
            -- P2P connection failed, need healthcheck to confirm
            ngx.log(ngx.WARN, "flatnet routing: P2P request failed for ", container_ip)
        elseif latency then
            escalation.update_latency(container_ip, latency)
        end
    end
end

-- Get all routes summary
-- @return table: Map of container_ip -> route_info
function _M.get_all_routes()
    local containers = registry.get_all()
    local routes = {}

    for _, container in ipairs(containers) do
        if container.ip then
            routes[container.ip] = _M.get_route(container.ip, {skip_p2p_attempt = true})
        end
    end

    return routes
end

-- Get routing statistics
-- @return table: Statistics
function _M.stats()
    local esc_stats = escalation.stats()

    -- Count gateway mappings
    local gateway_count = 0
    for _ in pairs(config.gateway_map) do
        gateway_count = gateway_count + 1
    end

    return {
        local_host_id = config.local_host_id,
        gateway_count = gateway_count,
        default_gateway = config.default_gateway,
        local_subnet = config.local_subnet,
        escalation = esc_stats
    }
end

return _M
