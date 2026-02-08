-- Flatnet Container API Handler
-- Handles HTTP requests for container registration and lookup
--
-- Endpoints:
--   GET    /api/containers         - List all containers
--   GET    /api/containers/:id     - Get container by ID
--   POST   /api/containers         - Register container
--   DELETE /api/containers/:id     - Deregister container

local cjson = require("cjson.safe")
local registry = require("flatnet.registry")
local sync = require("flatnet.sync")

-- Get request method and path
local method = ngx.req.get_method()
local uri = ngx.var.uri

-- Helper: Send JSON response
local function json_response(status, data)
    ngx.status = status
    ngx.header["Content-Type"] = "application/json"
    ngx.say(cjson.encode(data))
    return ngx.exit(status)
end

-- Helper: Extract container ID from URI
-- Only allows alphanumeric characters, underscores, and hyphens
local function get_container_id()
    -- URI pattern: /api/containers/:id
    local id = uri:match("^/api/containers/([^/]+)$")
    if id then
        -- Validate ID contains only safe characters (alphanumeric, underscore, hyphen)
        if not id:match("^[a-zA-Z0-9_-]+$") then
            return nil
        end
        -- Limit ID length to prevent abuse
        if #id > 128 then
            return nil
        end
    end
    return id
end

-- Helper: Read JSON body
local function read_json_body()
    ngx.req.read_body()
    local body = ngx.req.get_body_data()
    if not body then
        return nil, "empty body"
    end

    local data = cjson.decode(body)
    if not data then
        return nil, "invalid JSON"
    end

    return data
end

-- GET /api/containers - List all containers
local function handle_list()
    local containers = registry.get_all()
    local result = {}

    for _, container in ipairs(containers) do
        -- Add TTL info (approximate based on registration)
        local ttl = 300  -- Default TTL
        table.insert(result, {
            id = container.id,
            ip = container.ip,
            hostname = container.hostname,
            ports = container.ports,
            hostId = container.hostId,
            createdAt = container.createdAt,
            ttl = ttl
        })
    end

    return json_response(200, result)
end

-- GET /api/containers/:id - Get container by ID
local function handle_get(container_id)
    local container = registry.get(container_id)
    if not container then
        return json_response(404, {error = "container not found", id = container_id})
    end

    return json_response(200, container)
end

-- POST /api/containers - Register container
local function handle_register()
    local data, err = read_json_body()
    if not data then
        return json_response(400, {error = "invalid request body", details = err})
    end

    -- Validate required fields
    if not data.id or not data.ip then
        return json_response(400, {error = "missing required fields: id, ip"})
    end

    -- Register container
    -- Note: hostId defaults to 1 (single-host default) if not provided
    local ok, err = registry.register({
        id = data.id,
        ip = data.ip,
        hostname = data.hostname,
        ports = data.ports,
        hostId = data.hostId or 1,
        createdAt = data.createdAt
    })

    if not ok then
        return json_response(500, {error = "registration failed", details = err})
    end

    -- Notify peers asynchronously to avoid blocking the response
    local peer_host_id = ngx.req.get_headers()["X-Flatnet-Host-ID"]
    if not peer_host_id then
        -- Only push to peers if not already receiving from a peer
        -- This prevents infinite sync loops
        local push_data = {
            id = data.id,
            ip = data.ip,
            hostname = data.hostname,
            ports = data.ports,
            hostId = data.hostId or 1,
            createdAt = data.createdAt
        }
        local ok, err = ngx.timer.at(0, function(premature)
            if premature then return end
            local sync_module = require("flatnet.sync")
            sync_module.push_to_peers(push_data)
        end)
        if not ok then
            ngx.log(ngx.WARN, "flatnet api: failed to schedule peer notification: ", err)
        end
    end

    return json_response(201, {success = true, id = data.id})
end

-- DELETE /api/containers/:id - Deregister container
local function handle_delete(container_id)
    local container = registry.get(container_id)
    if not container then
        -- Idempotent: return success even if not found
        return json_response(200, {success = true, id = container_id, note = "already deleted"})
    end

    local ok, err = registry.deregister(container_id)
    if not ok then
        return json_response(500, {error = "deregistration failed", details = err})
    end

    -- Notify peers asynchronously
    local peer_host_id = ngx.req.get_headers()["X-Flatnet-Host-ID"]
    if not peer_host_id then
        local delete_id = container_id  -- Capture for closure
        local ok, err = ngx.timer.at(0, function(premature)
            if premature then return end
            local sync_module = require("flatnet.sync")
            sync_module.notify_deletion(delete_id)
        end)
        if not ok then
            ngx.log(ngx.WARN, "flatnet api: failed to schedule deletion notification: ", err)
        end
    end

    return json_response(200, {success = true, id = container_id})
end

-- Router
local container_id = get_container_id()

if method == "GET" then
    if container_id then
        handle_get(container_id)
    else
        handle_list()
    end
elseif method == "POST" then
    if container_id then
        return json_response(405, {error = "method not allowed", method = method, path = uri})
    end
    handle_register()
elseif method == "DELETE" then
    if not container_id then
        return json_response(400, {error = "container ID required for DELETE"})
    end
    handle_delete(container_id)
else
    return json_response(405, {error = "method not allowed", method = method, allowed = {"GET", "POST", "DELETE"}})
end
