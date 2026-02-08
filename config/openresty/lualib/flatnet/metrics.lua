-- Flatnet Gateway Metrics Module
-- Phase 4, Stage 1: Monitoring
--
-- Exposes Prometheus metrics for the Gateway:
-- - Request counters (total, by status code)
-- - Response time histogram
-- - Active connections gauge
--
-- Usage:
--   local metrics = require("flatnet.metrics")
--   metrics.init()                    -- Initialize shared dict
--   metrics.record_request(status, duration)  -- Record request
--   metrics.inc_connections()         -- Increment active connections
--   metrics.dec_connections()         -- Decrement active connections
--   local output = metrics.export()   -- Export Prometheus format

local _M = {}

-- Shared dict for metrics (configured in nginx.conf)
local SHARED_DICT_NAME = "flatnet_metrics"

-- Metric names (Prometheus naming convention)
local METRIC_PREFIX = "flatnet_"

-- Histogram bucket boundaries (in seconds)
local DURATION_BUCKETS = {0.001, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10}

-- Keys for metrics
local KEY_REQUESTS_TOTAL = "requests_total"
local KEY_REQUESTS_BY_STATUS = "requests_status_"
local KEY_DURATION_SUM = "duration_sum"
local KEY_DURATION_COUNT = "duration_count"
local KEY_DURATION_BUCKET = "duration_bucket_"
local KEY_ACTIVE_CONNECTIONS = "active_connections"

-- Get shared dict with error handling
local function get_shared_dict()
    local dict = ngx.shared[SHARED_DICT_NAME]
    if not dict then
        ngx.log(ngx.ERR, "flatnet metrics: shared dict '", SHARED_DICT_NAME, "' not configured")
        return nil
    end
    return dict
end

-- Initialize metrics (call once at startup)
function _M.init()
    local dict = get_shared_dict()
    if not dict then
        return false
    end

    -- Initialize counters to 0
    dict:set(KEY_REQUESTS_TOTAL, 0)
    dict:set(KEY_DURATION_SUM, 0)
    dict:set(KEY_DURATION_COUNT, 0)
    dict:set(KEY_ACTIVE_CONNECTIONS, 0)

    -- Initialize histogram buckets
    for _, bucket in ipairs(DURATION_BUCKETS) do
        dict:set(KEY_DURATION_BUCKET .. bucket, 0)
    end
    dict:set(KEY_DURATION_BUCKET .. "+Inf", 0)

    ngx.log(ngx.INFO, "flatnet metrics: initialized")
    return true
end

-- Record a request with status code and duration
-- @param status number: HTTP status code
-- @param duration number: Request duration in seconds
function _M.record_request(status, duration)
    local dict = get_shared_dict()
    if not dict then
        return
    end

    -- Increment total requests
    dict:incr(KEY_REQUESTS_TOTAL, 1, 0)

    -- Increment requests by status code
    local status_key = KEY_REQUESTS_BY_STATUS .. tostring(status)
    dict:incr(status_key, 1, 0)

    -- Record duration histogram
    if duration and duration >= 0 then
        -- Increment sum
        dict:incr(KEY_DURATION_SUM, duration, 0)
        -- Increment count
        dict:incr(KEY_DURATION_COUNT, 1, 0)

        -- Increment appropriate buckets
        for _, bucket in ipairs(DURATION_BUCKETS) do
            if duration <= bucket then
                dict:incr(KEY_DURATION_BUCKET .. bucket, 1, 0)
            end
        end
        -- Always increment +Inf bucket
        dict:incr(KEY_DURATION_BUCKET .. "+Inf", 1, 0)
    end
end

-- Increment active connections
function _M.inc_connections()
    local dict = get_shared_dict()
    if not dict then
        return
    end
    dict:incr(KEY_ACTIVE_CONNECTIONS, 1, 0)
end

-- Decrement active connections
-- Note: Uses atomic incr with init value 0 to avoid race conditions.
-- If counter goes negative (rare edge case), it's acceptable as it will
-- self-correct with subsequent inc_connections calls.
function _M.dec_connections()
    local dict = get_shared_dict()
    if not dict then
        return
    end
    -- Atomic decrement with init value 0
    -- Returns new value; if it was 0, incr(-1, 0) returns -1 but this is
    -- better than a non-atomic read-then-write pattern
    local newval, err = dict:incr(KEY_ACTIVE_CONNECTIONS, -1, 0)
    if newval and newval < 0 then
        -- Reset to 0 if we went negative (edge case)
        dict:set(KEY_ACTIVE_CONNECTIONS, 0)
    end
end

-- Get current active connections
function _M.get_connections()
    local dict = get_shared_dict()
    if not dict then
        return 0
    end
    return dict:get(KEY_ACTIVE_CONNECTIONS) or 0
end

-- Format a metric line in Prometheus text format
local function format_metric(name, value, labels, metric_type, help)
    local lines = {}

    -- Add HELP line
    if help then
        table.insert(lines, string.format("# HELP %s %s", name, help))
    end

    -- Add TYPE line
    if metric_type then
        table.insert(lines, string.format("# TYPE %s %s", name, metric_type))
    end

    -- Add metric value
    if labels and #labels > 0 then
        local label_str = table.concat(labels, ",")
        table.insert(lines, string.format("%s{%s} %s", name, label_str, tostring(value)))
    else
        table.insert(lines, string.format("%s %s", name, tostring(value)))
    end

    return table.concat(lines, "\n")
end

-- Export all metrics in Prometheus text format
function _M.export()
    local dict = get_shared_dict()
    if not dict then
        return "# ERROR: metrics shared dict not available\n"
    end

    local output = {}

    -- Gateway info metric
    table.insert(output, "# HELP flatnet_gateway_info Gateway information")
    table.insert(output, "# TYPE flatnet_gateway_info gauge")
    table.insert(output, 'flatnet_gateway_info{version="1.0.0",phase="4"} 1')
    table.insert(output, "")

    -- Active connections (gauge)
    local connections = dict:get(KEY_ACTIVE_CONNECTIONS) or 0
    table.insert(output, "# HELP flatnet_active_connections Current number of active connections")
    table.insert(output, "# TYPE flatnet_active_connections gauge")
    table.insert(output, string.format("flatnet_active_connections %d", connections))
    table.insert(output, "")

    -- Total requests (counter)
    local total = dict:get(KEY_REQUESTS_TOTAL) or 0
    table.insert(output, "# HELP flatnet_http_requests_total Total number of HTTP requests")
    table.insert(output, "# TYPE flatnet_http_requests_total counter")
    table.insert(output, string.format("flatnet_http_requests_total %d", total))
    table.insert(output, "")

    -- Requests by status code (counter with labels)
    table.insert(output, "# HELP flatnet_http_requests_by_status_total HTTP requests by status code")
    table.insert(output, "# TYPE flatnet_http_requests_by_status_total counter")

    -- Get all keys and filter for status codes
    local keys = dict:get_keys(0)
    local status_codes = {}
    for _, key in ipairs(keys) do
        local status = key:match("^requests_status_(%d+)$")
        if status then
            table.insert(status_codes, status)
        end
    end
    table.sort(status_codes)

    for _, status in ipairs(status_codes) do
        local count = dict:get(KEY_REQUESTS_BY_STATUS .. status) or 0
        table.insert(output, string.format('flatnet_http_requests_total{status="%s"} %d', status, count))
    end
    table.insert(output, "")

    -- Request duration histogram
    table.insert(output, "# HELP flatnet_http_request_duration_seconds HTTP request duration in seconds")
    table.insert(output, "# TYPE flatnet_http_request_duration_seconds histogram")

    -- Histogram buckets
    for _, bucket in ipairs(DURATION_BUCKETS) do
        local count = dict:get(KEY_DURATION_BUCKET .. bucket) or 0
        table.insert(output, string.format('flatnet_http_request_duration_seconds_bucket{le="%s"} %d', tostring(bucket), count))
    end
    local inf_count = dict:get(KEY_DURATION_BUCKET .. "+Inf") or 0
    table.insert(output, string.format('flatnet_http_request_duration_seconds_bucket{le="+Inf"} %d', inf_count))

    -- Histogram sum and count
    local duration_sum = dict:get(KEY_DURATION_SUM) or 0
    local duration_count = dict:get(KEY_DURATION_COUNT) or 0
    table.insert(output, string.format("flatnet_http_request_duration_seconds_sum %s", tostring(duration_sum)))
    table.insert(output, string.format("flatnet_http_request_duration_seconds_count %d", duration_count))
    table.insert(output, "")

    return table.concat(output, "\n") .. "\n"
end

-- Reset all metrics (for testing)
function _M.reset()
    local dict = get_shared_dict()
    if not dict then
        return false
    end

    dict:flush_all()
    return _M.init()
end

-- Get stats summary
function _M.stats()
    local dict = get_shared_dict()
    if not dict then
        return {error = "shared dict not available"}
    end

    local total = dict:get(KEY_REQUESTS_TOTAL) or 0
    local duration_sum = dict:get(KEY_DURATION_SUM) or 0
    local duration_count = dict:get(KEY_DURATION_COUNT) or 0
    local connections = dict:get(KEY_ACTIVE_CONNECTIONS) or 0

    return {
        requests_total = total,
        active_connections = connections,
        avg_duration = duration_count > 0 and (duration_sum / duration_count) or 0,
        shared_dict_name = SHARED_DICT_NAME
    }
end

return _M
