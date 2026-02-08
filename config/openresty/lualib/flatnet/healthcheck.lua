-- Flatnet Healthcheck Module
-- Performs periodic health checks on P2P connections
--
-- Features:
-- - Periodic health check execution via ngx.timer
-- - Latency measurement
-- - Automatic fallback on failure threshold
-- - Retry with exponential backoff
--
-- Usage:
--   local healthcheck = require("flatnet.healthcheck")
--   healthcheck.start()

local _M = {}
local http = require("resty.http")
local escalation = require("flatnet.escalation")

-- Configuration (synced with escalation module config)
local config = {
    enabled = true,
    interval = 5,                -- Health check interval in seconds
    timeout = 5000,              -- Request timeout in milliseconds
    failure_threshold = 3,       -- Consecutive failures before fallback
    path = "/health",            -- Health check endpoint path
    port = 80,                   -- Default port for health check
}

-- Failure counter per IP (in-memory, will be reset on worker restart)
local failure_counts = {}

-- Worker flag to prevent multiple timers
local worker_started = false

-- Forward declaration for schedule_p2p_retry (used in process_health_result)
local schedule_p2p_retry

-- Configure healthcheck module
-- @param opts table: Configuration options
function _M.configure(opts)
    if not opts then return end

    if opts.enabled ~= nil then
        config.enabled = opts.enabled
    end
    if opts.interval then
        config.interval = opts.interval
    end
    if opts.timeout then
        config.timeout = opts.timeout
    end
    if opts.failure_threshold then
        config.failure_threshold = opts.failure_threshold
    end
    if opts.path then
        config.path = opts.path
    end
    if opts.port then
        config.port = opts.port
    end
end

-- Get current configuration
function _M.get_config()
    return config
end

-- Check health of a single P2P connection
-- @param ip string: Target IP address
-- @return boolean, number, string: success, latency_ms, error_message
local function check_p2p_health(ip)
    local httpc = http.new()
    httpc:set_timeout(config.timeout)

    local start_time = ngx.now()

    local uri = "http://" .. ip .. ":" .. config.port .. config.path

    local res, err = httpc:request_uri(uri, {
        method = "GET",
        headers = {
            ["User-Agent"] = "Flatnet-Healthcheck/1.0",
            ["X-Flatnet-Healthcheck"] = "1"
        }
    })

    local latency = (ngx.now() - start_time) * 1000  -- Convert to milliseconds

    if not res then
        return false, latency, "request failed: " .. (err or "unknown")
    end

    if res.status >= 200 and res.status < 300 then
        return true, latency, nil
    end

    return false, latency, "unexpected status: " .. res.status
end

-- Process health check result for an IP
-- @param ip string: Target IP address
-- @param success boolean: Health check result
-- @param latency number: Latency in milliseconds
-- @param err string: Error message if failed
local function process_health_result(ip, success, latency, err)
    -- Update latency
    escalation.update_latency(ip, latency)
    escalation.update_last_check(ip)

    if success then
        -- Reset failure count on success
        failure_counts[ip] = 0

        -- Check latency thresholds
        local esc_config = escalation.get_config()
        if latency > esc_config.latency_fallback then
            ngx.log(ngx.WARN, "flatnet healthcheck: ", ip, " latency ", latency,
                "ms exceeds fallback threshold (", esc_config.latency_fallback, "ms)")
            failure_counts[ip] = (failure_counts[ip] or 0) + 1
        end
    else
        -- Increment failure count
        failure_counts[ip] = (failure_counts[ip] or 0) + 1
        ngx.log(ngx.WARN, "flatnet healthcheck: ", ip, " failed: ", err,
            " (count: ", failure_counts[ip], "/", config.failure_threshold, ")")
    end

    -- Check if threshold exceeded
    if failure_counts[ip] >= config.failure_threshold then
        local current_state = escalation.get_state(ip)
        if current_state == escalation.STATE.P2P_ACTIVE then
            ngx.log(ngx.WARN, "flatnet healthcheck: ", ip,
                " reached failure threshold, falling back to gateway")
            escalation.fallback_to_gateway(ip, "healthcheck failure threshold exceeded")
            failure_counts[ip] = 0  -- Reset after fallback

            -- Schedule retry after backoff
            local retry_count = escalation.get_retry_count(ip)
            local retry_interval = escalation.get_retry_interval(retry_count)
            schedule_p2p_retry(ip, retry_interval)
        end
    end
end

-- Schedule P2P retry after fallback
-- @param ip string: Target IP address
-- @param delay number: Delay in seconds before retry
schedule_p2p_retry = function(ip, delay)
    local ok, err = ngx.timer.at(delay, function(premature)
        if premature then
            return
        end

        local current_state = escalation.get_state(ip)
        if current_state == escalation.STATE.GATEWAY_FALLBACK then
            ngx.log(ngx.INFO, "flatnet healthcheck: retrying P2P for ", ip, " after ", delay, "s delay")
            -- Reset to GATEWAY_ONLY to allow new P2P attempt
            escalation.reset_to_gateway_only(ip, "scheduled retry")
        end
    end)
    if not ok then
        ngx.log(ngx.ERR, "flatnet healthcheck: failed to schedule P2P retry: ", err)
    end
end

-- Main health check worker function
-- @param premature boolean: True if timer is being shut down
local function healthcheck_worker(premature)
    if premature then
        return
    end

    if not config.enabled then
        -- Reschedule even if disabled (in case it gets enabled later)
        local ok, err = ngx.timer.at(config.interval, healthcheck_worker)
        if not ok then
            ngx.log(ngx.ERR, "flatnet healthcheck: failed to reschedule timer: ", err)
        end
        return
    end

    -- Get all P2P_ACTIVE connections
    local active_ips = escalation.get_active_p2p_ips()

    if #active_ips > 0 then
        ngx.log(ngx.DEBUG, "flatnet healthcheck: checking ", #active_ips, " P2P connections")

        for _, ip in ipairs(active_ips) do
            -- Run health check
            local success, latency, err = check_p2p_health(ip)
            process_health_result(ip, success, latency, err)
        end
    end

    -- Reschedule timer
    local ok, err = ngx.timer.at(config.interval, healthcheck_worker)
    if not ok then
        ngx.log(ngx.ERR, "flatnet healthcheck: failed to reschedule timer: ", err)
    end
end

-- Start the health check worker
-- Should be called from init_worker_by_lua
function _M.start()
    if worker_started then
        ngx.log(ngx.WARN, "flatnet healthcheck: worker already started")
        return
    end

    worker_started = true

    -- Delay initial start to allow other modules to initialize
    local ok, err = ngx.timer.at(config.interval, healthcheck_worker)
    if not ok then
        ngx.log(ngx.ERR, "flatnet healthcheck: failed to start worker: ", err)
        worker_started = false
        return
    end

    ngx.log(ngx.INFO, "flatnet healthcheck: started with interval=", config.interval, "s")
end

-- Manually trigger health check for a specific IP
-- @param ip string: Target IP address
-- @return boolean, number, string: success, latency_ms, error_message
function _M.check(ip)
    if not ip then
        return false, 0, "ip is required"
    end

    local success, latency, err = check_p2p_health(ip)
    process_health_result(ip, success, latency, err)

    return success, latency, err
end

-- Get failure count for an IP
-- @param ip string: Target IP address
-- @return number: Failure count
function _M.get_failure_count(ip)
    return failure_counts[ip] or 0
end

-- Reset failure count for an IP
-- @param ip string: Target IP address
function _M.reset_failure_count(ip)
    failure_counts[ip] = 0
end

-- Clear failure count for an IP (removes entry from table)
-- @param ip string: Target IP address
function _M.clear_failure_count(ip)
    failure_counts[ip] = nil
end

-- Clear all failure counts (for memory management)
function _M.clear_all_failure_counts()
    failure_counts = {}
end

-- Get health check status
-- @return table: Status information
function _M.status()
    local active_ips = escalation.get_active_p2p_ips()
    local failures = {}

    for ip, count in pairs(failure_counts) do
        if count > 0 then
            failures[ip] = count
        end
    end

    return {
        enabled = config.enabled,
        worker_started = worker_started,
        interval = config.interval,
        failure_threshold = config.failure_threshold,
        active_p2p_count = #active_ips,
        active_ips = active_ips,
        failure_counts = failures
    }
end

-- Enable health check
function _M.enable()
    config.enabled = true
    ngx.log(ngx.INFO, "flatnet healthcheck: enabled")
end

-- Disable health check
function _M.disable()
    config.enabled = false
    ngx.log(ngx.INFO, "flatnet healthcheck: disabled")
end

return _M
