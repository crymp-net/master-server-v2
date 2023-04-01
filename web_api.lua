local db = require("crymp.db")

--- @class web_api
local api = {}

local standard_maps = {
    ["multiplayer/ps/shore"] = true,
    ["multiplayer/ps/mesa"] = true,
    ["multiplayer/ps/plantation"] = true,
    ["multiplayer/ps/beach"] = true,
    ["multiplayer/ps/refinery"] = true,
    ["multiplayer/ia/steelmill"] = true,
    ["multiplayer/ia/quarry"] = true,
    ["multiplayer/ia/armada"] = true,
    ["multiplayer/ia/outpost"] = true
}

--- Convert query parameters to server update
---@param query any
---@param ip string
---@param port integer|nil
---@return server_object|nil update
function api:toServerUpdate(query, ip, port, source)
    source = source or "http"
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
        players = source == "http" and query["players"] or nil,
        gamespyPlayers = source == "gamespy" and query["players"] or nil,
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
---@param own_ip string|nil ip of requester
function api.toPublic(server, own_ip)
    local players = crymp:exportPlayers(server.source == "gamespy" and server.players or server.gamespyPlayers)
    local map = (server.map or "multiplayer/ps/mesa"):lower()
    local mapName = server.mapName or (map:sub(16))
    local own = nil

    local gamespyLookup = {}
    if server.source == "http" and server.gamespyPlayers ~= nil and #server.gamespyPlayers > 1 then
        local gsPlayers = crymp:exportPlayers(server.gamespyPlayers)
        for _, player in ipairs(gsPlayers) do
            gamespyLookup[player.name] = player.team
        end
    end

    for _, player in ipairs(players) do
        player.profile_id = nil
        local hit = gamespyLookup[player.name]
        if player.team == nil and hit ~= nil then
            player.team = hit
        end
    end

    if own_ip ~= nil then
        own = server.ip == own_ip
    end

    return {
        ip = server.ip,
        port = server.gamespyPort or server.port,
        gamespy_port = server.gamespyPort,
        public_ip = server.ip,
        public_port = server.publicPort,
        local_ip = server.localIp,
        local_port = server.port,
        own = own,
        
        name = server.name,
        desc = server.description,
        pak = server.pak,
        map = map,
        mapnm = mapName,
        mapdnm = mapName,
        mapdl = (server.mapDownloadLink and #server.mapDownloadLink > 0) and "http://" .. server.mapDownloadLink:gsub("^http://", "") or "",

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
        rating = server.rating,

        gs = server.dx10 ~= nil
    }
end

--- Upsert map into repo
---@param params server_object
---@return aiopromise<string|nil> url promise
function api:upsertMap(params)
    local resolve, resolver = aio:prepare_promise()
    local mapName, version = params.map, "-1"
    --- @type string|nil
    local url = params.mapDownloadLink
    local credible = false
    if mapName:find("|", 1, false) then
        version, mapName = mapName:match("^(.-)|(.+)$")
    end
    mapName = mapName:lower():gsub("^%s*", ""):gsub("%s*$", "")
    if url and #url > 0 then
        url = url:gsub("^https?://", "")
        credible = url:find("nullptr.one/", 1, nil) ~= nil
    end
    if standard_maps[mapName] then
        resolve("")
        return resolver
    end
    local mapFuture = db.maps.one:byMapNameVersion(mapName, version)
    mapFuture(function (result)
        if result and result.error then
            resolve(url)
        else
            if #url == 0 then url = nil end
            if result and (not result.autoGenerated or not credible) then
                resolve(url or result.url)
            elseif result and result.autoGenerated and credible then
                db.maps:update({mapName=mapName, version=version}, {
                    autoGenerated = not credible,
                    url = url,
                    creatorName = params.name
                })(function (_)
                    resolve(url or result.name)
                end)
            elseif not result and url then
                db.maps:insert({mapName=mapName, version=version, url=url, autoGenerated=not credible, creatorName=params.name})(function (result)
                    resolve(url)
                end)
            elseif result then
                resolve(url or result.url)
            else
                resolve(url)
            end
        end
    end)
    return resolver
end

--- Insert or update a server
---@param params server_object
---@return aiopromise<string|nil>
function api:upsertServer(params)
    local resolve, resolver = aio:prepare_promise()
    local serverFuture = db.servers.one:byIpPort(params.ip, params.port)
    local mapFuture = self:upsertMap(params)

    aio:gather(serverFuture, mapFuture)(function (existingServer, existingMap)
        if existingServer and existingServer.error then
            print("get error: ", existingServer.error)
            resolve(nil)
        else
            params.mapDownloadLink = existingMap
            if existingServer then
                local playersBefore = existingServer.players
                db.servers:update({ip=params.ip, port=params.port}, params)(function (result)
                    if not result or result.error then
                        print("update error: ", result.error)
                        resolve(nil)
                    else
                        resolve(existingServer.cookie)
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
                    if result.error then
                        print("insert error: ", result.error)
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

function api:issueToken(profileId, time, nickname, name)
    name = name or "Nomad"
    nickname = nickname or "Nomad"
    profileId = tostring(profileId)
    time = tostring(time)
    local signing = profileId .. "_" .. time

    return {
        id = profileId,
        token = hash(signing .. TOKEN_SALT) .. "_" .. time,
        nickname = nickname,
        name = name
    }
end

function api:validateToken(profileId, token)
    local signature, time = token:match("(.-)_(%d+)")
    local validityPeriod = 3600 * 4
    if signature and time then
        local now = os.time()
        local time_then = tonumber(time)
        local diff = now - time_then
        if diff > validityPeriod then
            return false
        end
        return self:issueToken(profileId, time, "Nomad", "Nomad").token == token
    else
        if #token == 65 and tonumber(profileId) >= 1000000 and token:sub(1, 1) == "s" then
            local tok = token:sub(2):lower()
            local base = self:staticIDToken(tostring(profileId))
            return hash("S" .. base .. "ID") == tok
        else
            return false
        end
    end
end

function api:login(user, password)
    local resolve, resolver = aio:prepare_promise()
    local isEmail = user:match("(.-)@(.+)%.(.*)")
    local userFuture = nil
    if isEmail then
        userFuture = db.users.one:byEmail(user)
    else
        userFuture = db.users.one:byNick(user)
    end
    userFuture(function (user)
        if not user or iserror(user) then
            resolve(nil)
        else
            if hash_password(password) == user.password then
                resolve(self:issueToken(user.id, os.time(), user.nick, user.display))
            elseif password == hash_secu_login(user.email, user.password) then
                resolve(self:issueToken(user.id, os.time(), user.nick, user.display))
            else
                resolve(nil)
            end
        end
    end)
    return resolver
end

function api:staticIDToken(profileId)
    return hash(profileId .. "_" .. STATIC_ID_SALT)
end

return api