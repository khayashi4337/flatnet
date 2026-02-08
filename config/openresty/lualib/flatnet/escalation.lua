-- Flatnet Escalation Module
-- Manages connection states for Graceful Escalation pattern
--
-- Connection States:
--   GATEWAY_ONLY     - Gateway routing only (initial state)
--   P2P_ATTEMPTING   - P2P connection being established
--   P2P_ACTIVE       - P2P route is active
--   GATEWAY_FALLBACK - Fallback to Gateway after P2P failure
--
-- Usage:
--   local escalation = require("flatnet.escalation")
--   escalation.get_state(ip)
--   escalation.set_state(ip, state)
--   escalation.attempt_p2p(ip)

local _M = {}
local cjson = require("cjson.safe")

-- Shared dict for escalation state (configured in nginx.conf)
local SHARED_DICT_NAME = "flatnet_escalation"

-- Connection state constants
_M.STATE = {
    GATEWAY_ONLY = "GATEWAY_ONLY",
    P2P_ATTEMPTING = "P2P_ATTEMPTING",
    P2P_ACTIVE = "P2P_ACTIVE",
    GATEWAY_FALLBACK = "GATEWAY_FALLBACK"
}

-- Default configuration (can be overridden via escalation.conf)
local config = {
    -- Healthcheck settings
    healthcheck_interval = 5,         -- seconds
    healthcheck_timeout = 5000,       -- milliseconds
    healthcheck_failure_threshold = 3, -- consecutive failures for fallback

    -- Latency thresholds (milliseconds)
    latency_warning = 500,
    latency_fallback = 1000,

    -- P2P establishment settings
    p2p_attempt_timeout = 30,         -- seconds

    -- Retry backoff settings (seconds)
    retry_intervals = {10, 30, 60, 300},  -- 10s, 30s, 1min, 5min (max)

    -- Fallback settings
    fallback_retry_delay = 30,        -- seconds before retrying P2P after fallback
}

-- State entry prefix in shared dict
local STATE_PREFIX = "state:"
local METADATA_PREFIX = "meta:"
local RETRY_COUNT_PREFIX = "retry:"
local LAST_CHECK_PREFIX = "lastcheck:"
local LATENCY_PREFIX = "latency:"

-- Get shared dict with error handling
local function get_shared_dict()
    local dict = ngx.shared[SHARED_DICT_NAME]
    if not dict then
        ngx.log(ngx.ERR, "flatnet escalation: shared dict '", SHARED_DICT_NAME, "' not configured")
        return nil, "shared dict not configured"
    end
    return dict
end

-- Configure escalation module
-- @param opts table: Configuration options
function _M.configure(opts)
    if not opts then return end

    if opts.healthcheck_interval then
        config.healthcheck_interval = opts.healthcheck_interval
    end
    if opts.healthcheck_timeout then
        config.healthcheck_timeout = opts.healthcheck_timeout
    end
    if opts.healthcheck_failure_threshold then
        config.healthcheck_failure_threshold = opts.healthcheck_failure_threshold
    end
    if opts.latency_warning then
        config.latency_warning = opts.latency_warning
    end
    if opts.latency_fallback then
        config.latency_fallback = opts.latency_fallback
    end
    if opts.p2p_attempt_timeout then
        config.p2p_attempt_timeout = opts.p2p_attempt_timeout
    end
    if opts.retry_intervals then
        config.retry_intervals = opts.retry_intervals
    end
    if opts.fallback_retry_delay then
        config.fallback_retry_delay = opts.fallback_retry_delay
    end
end

-- Get current configuration
function _M.get_config()
    return config
end

-- Get connection state for an IP
-- @param ip string: Container IP address
-- @return string: Connection state (defaults to GATEWAY_ONLY)
function _M.get_state(ip)
    if not ip then
        return _M.STATE.GATEWAY_ONLY
    end

    local dict, err = get_shared_dict()
    if not dict then
        return _M.STATE.GATEWAY_ONLY
    end

    local state = dict:get(STATE_PREFIX .. ip)
    return state or _M.STATE.GATEWAY_ONLY
end

-- Set connection state for an IP
-- @param ip string: Container IP address
-- @param state string: New state
-- @param ttl number: Optional TTL in seconds (default: no expiry)
-- @return boolean, string: success, error message
function _M.set_state(ip, state, ttl)
    if not ip or not state then
        return false, "ip and state are required"
    end

    -- Validate state
    local valid = false
    for _, s in pairs(_M.STATE) do
        if s == state then
            valid = true
            break
        end
    end
    if not valid then
        return false, "invalid state: " .. state
    end

    local dict, err = get_shared_dict()
    if not dict then
        return false, err
    end

    local old_state = dict:get(STATE_PREFIX .. ip)

    -- Set new state
    local ok, set_err = dict:set(STATE_PREFIX .. ip, state, ttl or 0)
    if not ok then
        return false, "failed to set state: " .. (set_err or "unknown")
    end

    -- Log state transition
    if old_state and old_state ~= state then
        ngx.log(ngx.INFO, "flatnet escalation: ", ip, " state changed: ", old_state, " -> ", state)
    elseif not old_state then
        ngx.log(ngx.INFO, "flatnet escalation: ", ip, " initial state: ", state)
    end

    return true
end

-- Get metadata for an IP
-- @param ip string: Container IP address
-- @return table|nil: Metadata or nil
function _M.get_metadata(ip)
    if not ip then
        return nil
    end

    local dict, err = get_shared_dict()
    if not dict then
        return nil
    end

    local data = dict:get(METADATA_PREFIX .. ip)
    if not data then
        return nil
    end

    local decoded, decode_err = cjson.decode(data)
    if not decoded then
        ngx.log(ngx.WARN, "flatnet escalation: failed to decode metadata for ", ip, ": ", decode_err)
        return nil
    end
    return decoded
end

-- Set metadata for an IP
-- @param ip string: Container IP address
-- @param metadata table: Metadata to store
-- @return boolean, string: success, error message
function _M.set_metadata(ip, metadata)
    if not ip or not metadata then
        return false, "ip and metadata are required"
    end

    local dict, err = get_shared_dict()
    if not dict then
        return false, err
    end

    local data = cjson.encode(metadata)
    if not data then
        return false, "failed to encode metadata"
    end

    local ok, set_err = dict:set(METADATA_PREFIX .. ip, data, 0)
    if not ok then
        return false, "failed to set metadata: " .. (set_err or "unknown")
    end

    return true
end

-- Get retry count for an IP
-- @param ip string: Container IP address
-- @return number: Retry count (0 if not set)
function _M.get_retry_count(ip)
    if not ip then
        return 0
    end

    local dict, err = get_shared_dict()
    if not dict then
        return 0
    end

    return dict:get(RETRY_COUNT_PREFIX .. ip) or 0
end

-- Increment retry count for an IP
-- @param ip string: Container IP address
-- @return number: New retry count
function _M.increment_retry_count(ip)
    if not ip then
        return 0
    end

    local dict, err = get_shared_dict()
    if not dict then
        return 0
    end

    local new_count, err = dict:incr(RETRY_COUNT_PREFIX .. ip, 1, 0)
    if not new_count then
        ngx.log(ngx.WARN, "flatnet escalation: failed to increment retry count: ", err)
        return 0
    end

    return new_count
end

-- Reset retry count for an IP
-- @param ip string: Container IP address
function _M.reset_retry_count(ip)
    if not ip then
        return
    end

    local dict, err = get_shared_dict()
    if not dict then
        return
    end

    dict:delete(RETRY_COUNT_PREFIX .. ip)
end

-- Get next retry interval based on retry count
-- @param retry_count number: Current retry count
-- @return number: Retry interval in seconds
function _M.get_retry_interval(retry_count)
    local intervals = config.retry_intervals
    if retry_count < 1 then
        return intervals[1]
    end
    if retry_count >= #intervals then
        return intervals[#intervals]  -- Max interval
    end
    return intervals[retry_count]
end

-- Update latency for an IP
-- @param ip string: Container IP address
-- @param latency number: Latency in milliseconds
function _M.update_latency(ip, latency)
    if not ip or not latency then
        return
    end

    local dict, err = get_shared_dict()
    if not dict then
        return
    end

    dict:set(LATENCY_PREFIX .. ip, latency, 60)  -- TTL 60s

    -- Check latency thresholds
    if latency > config.latency_fallback then
        ngx.log(ngx.WARN, "flatnet escalation: ", ip, " latency ", latency, "ms exceeds fallback threshold")
    elseif latency > config.latency_warning then
        ngx.log(ngx.WARN, "flatnet escalation: ", ip, " latency ", latency, "ms exceeds warning threshold")
    end
end

-- Get latency for an IP
-- @param ip string: Container IP address
-- @return number|nil: Latency in milliseconds or nil
function _M.get_latency(ip)
    if not ip then
        return nil
    end

    local dict, err = get_shared_dict()
    if not dict then
        return nil
    end

    return dict:get(LATENCY_PREFIX .. ip)
end

-- Update last healthcheck timestamp
-- @param ip string: Container IP address
function _M.update_last_check(ip)
    if not ip then
        return
    end

    local dict, err = get_shared_dict()
    if not dict then
        return
    end

    dict:set(LAST_CHECK_PREFIX .. ip, ngx.now(), 0)
end

-- Get last healthcheck timestamp
-- @param ip string: Container IP address
-- @return number|nil: Timestamp or nil
function _M.get_last_check(ip)
    if not ip then
        return nil
    end

    local dict, err = get_shared_dict()
    if not dict then
        return nil
    end

    return dict:get(LAST_CHECK_PREFIX .. ip)
end

-- Transition to P2P_ATTEMPTING state and start P2P establishment
-- @param ip string: Container IP address
-- @param target_gateway string: Target Gateway IP for P2P
-- @return boolean, string: success, error message
function _M.attempt_p2p(ip, target_gateway)
    if not ip then
        return false, "ip is required"
    end

    local current_state = _M.get_state(ip)

    -- Only attempt P2P from GATEWAY_ONLY or GATEWAY_FALLBACK states
    if current_state ~= _M.STATE.GATEWAY_ONLY and current_state ~= _M.STATE.GATEWAY_FALLBACK then
        return false, "P2P attempt not allowed from state: " .. current_state
    end

    -- Set state to P2P_ATTEMPTING
    local ok, err = _M.set_state(ip, _M.STATE.P2P_ATTEMPTING)
    if not ok then
        return false, err
    end

    -- Store metadata
    _M.set_metadata(ip, {
        target_gateway = target_gateway,
        attempt_started = ngx.now()
    })

    ngx.log(ngx.INFO, "flatnet escalation: starting P2P attempt for ", ip, " via ", target_gateway or "direct")

    return true
end

-- Mark P2P as active
-- @param ip string: Container IP address
-- @return boolean, string: success, error message
function _M.activate_p2p(ip)
    if not ip then
        return false, "ip is required"
    end

    local current_state = _M.get_state(ip)
    if current_state ~= _M.STATE.P2P_ATTEMPTING then
        return false, "cannot activate P2P from state: " .. current_state
    end

    -- Reset retry count on successful P2P
    _M.reset_retry_count(ip)

    local ok, err = _M.set_state(ip, _M.STATE.P2P_ACTIVE)
    if not ok then
        return false, err
    end

    ngx.log(ngx.INFO, "flatnet escalation: P2P activated for ", ip)
    return true
end

-- Fallback to Gateway
-- @param ip string: Container IP address
-- @param reason string: Reason for fallback
-- @return boolean, string: success, error message
function _M.fallback_to_gateway(ip, reason)
    if not ip then
        return false, "ip is required"
    end

    local current_state = _M.get_state(ip)

    -- Update retry count for backoff
    local retry_count = _M.increment_retry_count(ip)

    local ok, err = _M.set_state(ip, _M.STATE.GATEWAY_FALLBACK)
    if not ok then
        return false, err
    end

    ngx.log(ngx.WARN, "flatnet escalation: fallback to gateway for ", ip,
        ", reason: ", reason or "unknown",
        ", retry_count: ", retry_count)

    return true
end

-- Reset state to GATEWAY_ONLY
-- @param ip string: Container IP address
-- @param reason string: Reason for reset
-- @return boolean, string: success, error message
function _M.reset_to_gateway_only(ip, reason)
    if not ip then
        return false, "ip is required"
    end

    local ok, err = _M.set_state(ip, _M.STATE.GATEWAY_ONLY)
    if not ok then
        return false, err
    end

    -- Clear metadata
    local dict = get_shared_dict()
    if dict then
        dict:delete(METADATA_PREFIX .. ip)
    end

    ngx.log(ngx.INFO, "flatnet escalation: reset to GATEWAY_ONLY for ", ip,
        ", reason: ", reason or "manual")

    return true
end

-- Get all IPs with P2P_ACTIVE state
-- @return table: Array of IP addresses
function _M.get_active_p2p_ips()
    local dict, err = get_shared_dict()
    if not dict then
        return {}
    end

    local keys = dict:get_keys(1000)  -- Limit to 1000 entries
    local result = {}

    for _, key in ipairs(keys) do
        if key:sub(1, #STATE_PREFIX) == STATE_PREFIX then
            local value = dict:get(key)
            if value == _M.STATE.P2P_ACTIVE then
                local ip = key:sub(#STATE_PREFIX + 1)
                table.insert(result, ip)
            end
        end
    end

    return result
end

-- Get all escalation states
-- @return table: Map of IP -> state info
function _M.get_all_states()
    local dict, err = get_shared_dict()
    if not dict then
        return {}
    end

    local keys = dict:get_keys(1000)
    local result = {}

    for _, key in ipairs(keys) do
        if key:sub(1, #STATE_PREFIX) == STATE_PREFIX then
            local ip = key:sub(#STATE_PREFIX + 1)
            local state = dict:get(key)
            local metadata = _M.get_metadata(ip)
            local latency = _M.get_latency(ip)
            local retry_count = _M.get_retry_count(ip)
            local last_check = _M.get_last_check(ip)

            result[ip] = {
                state = state,
                metadata = metadata,
                latency = latency,
                retry_count = retry_count,
                last_check = last_check
            }
        end
    end

    return result
end

-- Get escalation statistics
-- @return table: Statistics
function _M.stats()
    local dict, err = get_shared_dict()
    if not dict then
        return {error = err}
    end

    local states = _M.get_all_states()
    local counts = {
        GATEWAY_ONLY = 0,
        P2P_ATTEMPTING = 0,
        P2P_ACTIVE = 0,
        GATEWAY_FALLBACK = 0
    }

    for _, info in pairs(states) do
        if info.state and counts[info.state] then
            counts[info.state] = counts[info.state] + 1
        end
    end

    return {
        total = counts.GATEWAY_ONLY + counts.P2P_ATTEMPTING + counts.P2P_ACTIVE + counts.GATEWAY_FALLBACK,
        states = counts,
        config = {
            healthcheck_interval = config.healthcheck_interval,
            latency_warning = config.latency_warning,
            latency_fallback = config.latency_fallback
        }
    }
end

-- Clear all escalation data for an IP
-- @param ip string: Container IP address
function _M.clear(ip)
    if not ip then
        return
    end

    local dict, err = get_shared_dict()
    if not dict then
        return
    end

    dict:delete(STATE_PREFIX .. ip)
    dict:delete(METADATA_PREFIX .. ip)
    dict:delete(RETRY_COUNT_PREFIX .. ip)
    dict:delete(LAST_CHECK_PREFIX .. ip)
    dict:delete(LATENCY_PREFIX .. ip)

    ngx.log(ngx.INFO, "flatnet escalation: cleared all data for ", ip)
end

-- Clear all escalation data
function _M.clear_all()
    local dict, err = get_shared_dict()
    if not dict then
        return
    end

    dict:flush_all()
    ngx.log(ngx.INFO, "flatnet escalation: cleared all data")
end

return _M
