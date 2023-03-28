local db = require("crymp.db")

--- @class web_api
local api = {}

--- Convert query parameters to server update
---@param query any
---@param ip string
---@param port integer|nil
---@return server_object|nil update
function api:toServerUpdate(query, ip, port)
    port = port or 64087
    local ok = true
    local required = {
        "timeLeft", "name", "players", "numPlayers", "maxPlayers", "map", "port", "ip"
    }
    local obj = {
        behindProxy = false,
        source = "http",
        ip = ip,
        port = tonumber(query.port),
        description = query["desc"],
        timeLeft = tonumber(query["timel"]),
        name = query["name"],
        players = query["players"],
        numPlayers = tonumber(query["numpl"]),
        maxPlayers = tonumber(query["maxpl"] or "0"),
        pak = query["pak"],
        map = query["map"] ~= nil and query["map"]:lower() or nil,
        mapName = query["mapnm"],
        mapDownloadLink = query["mapdl"],
        password = query["pass"] or "0",
        ranked = (query["ranked"] or "0") == "1",
        gameVersion = tonumber(query["ver"] or "6156"),
        localIp = query["local"],
        publicPort = tonumber(query["public_port"] or port),
        dx10 = query["dx10"] and query["dx10"] == "1" or nil,
        voiceChat = query["voicechat"] and query["voicechat"] == "1" or nil,
        dedicated = query["dedicated"] and query["dedicated"] == "1" or nil,
        antiCheat = query["anticheat"] and query["anticheat"] == "1" or nil,
        gamepadsOnly = query["gamepadonly"] and query["gamepadonly"] == "1" or nil,
        friendlyFire = query["friendlyfire"] and query["friendlyfire"] == "1" or nil
    }
    for _, i in ipairs(required) do
        if obj[i] == nil then
            return nil
        end
    end
    return obj
end

--- To public server entity
---@param server server_object
function api:toPublic(server)
    server = server or self
    local players = crymp:exportPlayers(server.players)
    local map = (server.map or "multiplayer/ps/mesa"):lower()
    local mapName = server.mapName or (map:sub(16))

    return {
        ip = server.ip,
        port = server.gamespyPort or server.port,
        gamespy_port = server.gamespyPort,
        public_ip = server.ip,
        public_port = server.publicPort,
        local_ip = server.localIp,
        local_port = server.port,
        
        name = server.name,
        desc = server.description,
        pak = server.pak,
        map = map,
        mapnm = mapName,
        mapdnm = mapName,
        mapdl = server.mapDownloadLink,

        players = players,
        pass = (server.password and #server.password > 0 and server.password ~= "0") and "1" or "0",

        ranked = server.ranked and 1 or 0,
        trusted = 0,

        numpl = server.numPlayers,
        maxpl = server.maxPlayers,
        ver = server.gameVersion or 6156,
        ntimel = server.timeLeft,
        timel = crymp:formatTime(server.timeLeft),

        dx10 = server.dx10,
        voicecomm = server.voiceChat,
        anticheat = server.antiCheat,
        dedicated = server.dedicated,
        gamepadsonly = server.gamepadsOnly,
        friendlyfire = server.friendlyFire,
        rating = server.rating
    }
end

--- Insert or update a server
---@param params server_object
---@return aiopromise<string|nil>
function api:upsertServer(params)
    local resolve, resolver = aio:prepare_promise()
    db.servers.one:byIpPort(params.ip, params.port)(function (existing, error)
        if error then
            resolve(nil)
        else
            if existing then
                local playersBefore = existing.players
                db.servers:update({ip=params.ip, port=params.port}, params)(function (result)
                    if not result or result.error then
                        print("update error: ", result.error)
                        resolve(nil)
                    else
                        resolve(existing.cookie)
                    end
                end)
            else
                params.isReal = false
                if params.friendlyFire == nil then params.friendlyFire = false end
                if params.antiCheat == nil then params.antiCheat = false end
                if params.gamepadsOnly == nil then params.gamepadsOnly = false end
                if params.dedicated == nil then params.dedicated = false end
                if params.voiceChat == nil then params.voiceChat = false end
                if params.dx10 == nil then params.dx10 = false end
                params.activeTime = 30
                params.uptime = 30
                params.ratingUpdates = 0
                params.rating = 0
                params.peopleTime = params.numPlayers > 0 and params.activeTime or 0
                params.cookie = codec.hex_encode(crypto.random(16))
                db.servers:insert(params)(function (result)
                    if not result or result.error then
                        print(result.error)
                        resolve(nil)
                    else
                        resolve(params.cookie)
                    end
                end)
            end
        end
    end)
    return resolver
end

return api