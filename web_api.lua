local db = require("crymp.db")

--- @class web_api
local api = {}

local standard_maps = {
    ["multiplayer/ps/shore"] = "Shore",
    ["multiplayer/ps/mesa"] = "Mesa",
    ["multiplayer/ps/plantation"] = "Plantation",
    ["multiplayer/ps/beach"] = "Beach",
    ["multiplayer/ps/refinery"] = "Refinery",
    ["multiplayer/ia/steelmill"] = "Steel Mill",
    ["multiplayer/ia/quarry"] = "Quarry",
    ["multiplayer/ia/armada"] = "Armada",
    ["multiplayer/ia/outpost"] = "Outpost"
}

local known_maps = {
    ["multiplayer/ps/shorehotels"] = "Shore Hotels",
    ["multiplayer/ia/rockvalleyaims"] = "Rock Valley Aims",
    ["multiplayer/ia/forestaimcamp"] = "Forest Aim Camp",
    ["multiplayer/ia/storageaiming"] = "Storage Aiming",
    ["multiplayer/ia/aimmapv2"] = "AimMap v2",
    ["multiplayer/ia/poolday_v2"] = "Poolday v2",
    ["multiplayer/ia/excavationoptim"] = "Excavation",
    ["multiplayer/ia/treehouseoptim"] = "Treehouse",
    ["multiplayer/ia/coastoptim"] = "Coast",
    ["multiplayer/ia/graveyardoptim"] = "Graveyard",
    ["multiplayer/ia/peakoptim"] = "Peak",
    ["multiplayer/ia/strandedoptim"] = "Stranded",
    ["multiplayer/ia/terminaloptim"] = "Terminal",
    ["multiplayer/ps/fighteen"] = "Mesa",
    ["multiplayer/ps/sunnyrefinery"] = "Sunny Refinery",
    ["multiplayer/ia/steelmillfrost"] = "Steel Mill Frost",
    ["multiplayer/ia/steelmillopen"] = "Steel Mill Open",
    ["multiplayer/ia/steel millflood"] = "Steel Mill Flood",
    ["multiplayer/ia/sunsetvillage"] = "Sunset Village",
    ["multiplayer/ia/paradiseatoll"] = "Paradise Atoll",
    ["multiplayer/ia/sewageswamps"] = "Sewage Swamps",
    ["multiplayer/ia/parkourcity"] = "Parkour City",
    ["multiplayer/ps/plantationtown"] = "Plantation Town",
    ["multiplayer/ia/steelmillmm"] = "Steel Mill"
}

for i, v in pairs(standard_maps) do
    known_maps[i] = v
end

function api:decodePasswordValue(value)
    if value == nil then return false end
    if value == "true" then return true end
    return (tonumber(value) or 0) > 0
end

--- Convert query parameters to server update
---@param query any
---@param ip string
---@param port integer|nil
---@return server_object|nil update
function api:toServerUpdate(query, ip, port, source)
    source = source or "http"
    port = port or 64087
    query.players = query.players or ""
    local ok = true
    if type(query.players) == "table" then
        local playerString = {}
        if #query.players > 0 then playerString[#playerString+1] = "@" end
        for i, player in ipairs(query.players) do
            local team = player.team or 0
            if player.name then
                player.kills = tonumber(player.kills or 0) or 0
                player.deaths = tonumber(player.deaths or 0) or 0
                player.rank = tonumber(player.rank or 0) or 0
                player.profile_id = tostring(player.profile_id or 0)
                if type(team) == "string" then
                    if team == "us" then
                        team = 2 
                    elseif team == "nk" then
                        team = 1
                    else
                        team = 0
                    end
                end
                playerString[#playerString+1] = string.format("%s%%%d%%%d%%%d%%%s%%%d", player.name or "Nomad", player.rank or 0, player.kills or 0, player.deaths or 0, player.profile_id or 0, team)
            end
        end
        query.players = table.join(playerString, "@")
    end
    local nPlayers = #crymp:exportPlayers(query.players)
    local behindProxy = false
    local required = {
        "timeLeft", "name", "numPlayers", "maxPlayers", "map", "port", "ip"
    }
    if query.proxy_ip and query.proxy_secret == PROXY_SECRET then
        ip = query.proxy_ip
        behindProxy = true
        source = "gamespy"
    end

    if query.mapdl and tostring(query.mapdl):find("pak:") then
        query.mapdl = query.mapdl:gsub("%+pak:", " pak:")
        local part1, part2 = query.mapdl:match("^(.-)pak:(.*)$")
        if part1 and part2 then
            query.mapdl = part1:gsub(" *$", ""):gsub("^ *", "")
            query.pak = part2:gsub(" *$", ""):gsub("^ *", "")
        end
    end

    local rules = query["rules"]

    if rules == nil then
        if query["map"] ~= nil then
            local map = query["map"]:lower()
            if map:find("/ps/") then
                rules = "PowerStruggle"
            elseif map:find("/ia/") then
                rules = "InstantAction"
            elseif map:find("/tia/") then
                rules = "TeamInstantAction"
            end
        end
    end

    rules = rules or ""

    local obj = {
        behindProxy = behindProxy,
        source = source,
        ip = ip,
        port = tonumber(query.port),
        gamespyPort = source == "gamespy" and query.port or nil,
        description = query["desc"],
        timeLeft = tonumber(query["timel"]),
        name = query["name"],
        players = source == "http" and query["players"] or nil,
        gamespyPlayers = source == "gamespy" and query["players"] or nil,
        numPlayers = nPlayers or 0,
        maxPlayers = tonumber(query["maxpl"] or "0"),
        pak = query["pak"],
        map = query["map"] ~= nil and query["map"]:lower() or nil,
        mapName = query["mapnm"] or self:guessMapName(query["map"] or "multiplayer/ps/mesa"),
        mapDownloadLink = query["mapdl"],
        password = self:decodePasswordValue(query["pass"]) and "1" or "",
        ranked = (query["ranked"] or "0") == "1",
        gameVersion = tonumber(query["ver"] or "6156"),
        localIp = query["local"],
        publicPort = tonumber(query["public_port"] or port),
        dx10 = query["dx10"] and query["dx10"] == "1" or nil,
        voiceChat = query["voicechat"] and query["voicechat"] == "1" or nil,
        dedicated = query["dedicated"] and query["dedicated"] == "1" or nil,
        antiCheat = query["anticheat"] and query["anticheat"] == "1" or nil,
        gamepadsOnly = query["gamepadsonly"] and query["gamepadsonly"] == "1" or nil,
        friendlyFire = query["friendlyfire"] and query["friendlyfire"] == "1" or nil,
        rules = rules
    }
    for _, i in ipairs(required) do
        if obj[i] == nil then
            return nil
        end
    end
    -- at least one must be present
    if not obj.players and not obj.gamespyPlayers then
        return
    end
    return obj
end

--- To public server entity that can be used in API responses
---@param server server_object server to be sanitized
---@param index integer server index
---@param own_ip string|nil ip of requester
function api.toPublic(server, index, own_ip)
    local players = crymp:exportPlayers(server.source == "http" and server.players or server.gamespyPlayers)
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
        timel = crymp:formatTime(server.timeLeft, false),
        available = server.isReal and 1 or 0,

        dx10 = server.dx10,
        voicecomm = server.voiceChat,
        anticheat = server.antiCheat,
        dedicated = server.dedicated,
        gamepadsonly = server.gamepadsOnly,
        friendlyfire = server.friendlyFire,
        rating = server.rating,
        source = server.source or "http",

        gs = server.dx10 ~= nil,
        rules = server.rules
    }
end

function api:guessMapName(map)
    map = map:lower()
    local hit = known_maps[map]
    if hit then return hit end
    local name = map:match("^multiplayer/[a-z]+/(.+)$")
    if not name then return "Mesa" end
    local parts = {}
    for part in name:gmatch("([^_%-]+)") do
        if #part <= 2 then
            table.insert(parts, part)
        else
            table.insert(parts, part:sub(1, 1):upper() .. part:sub(2))
        end
    end
    return table.concat(parts, " ")
end

--- Upsert map into repo
---@param params server_object
---@return aiopromise<string|nil> url promise
function api:upsertMap(params)
    local resolve, resolver = aio:prepare_promise()
    local mapPath, version = params.map, "-1"
    --- @type string|nil
    local url = params.mapDownloadLink
    local credible = false
    if mapPath:find("|", 1, false) then
        version, mapPath = mapPath:match("^(.-)|(.+)$")
    end
    mapPath = mapPath:lower():gsub("^%s*", ""):gsub("%s*$", "")
    if url and #url > 0 then
        url = url:gsub("^https?://", "")
        credible = url:find("nullptr.one/", 1, nil) ~= nil
    end
    if standard_maps[mapPath] then
        resolve("")
        return resolver
    end
    local mapFuture = db.maps.one:byMapNameVersion(mapPath, version)
    mapFuture(function (result)
        if result and result.error then
            resolve(url)
        else
            if not url or #url == 0 then url = nil end
            if result and (not result.autoGenerated or not credible) then
                resolve(url or result.url)
            elseif result and result.autoGenerated and credible then
                db.maps:update({mapName=mapPath, version=version}, {
                    autoGenerated = not credible,
                    url = url,
                    creatorName = params.name
                })(function (_)
                    resolve(url or result.name)
                end)
            elseif not result and url then
                db.maps:insert({mapName=mapPath, version=version, url=url, autoGenerated=not credible, creatorName=params.name})(function (result)
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
---@param params server_object server update
---@return aiopromise<string|nil>
function api:upsertServer(params)
    local resolve, resolver = aio:prepare_promise()
    local serverFuture = db.servers.one:byIpPort(params.ip, params.port)
    local mapFuture = self:upsertMap(params)
    params.source = params.source or "http"

    crymp:record_stat(params.source == "http" and "serverUpdates" or "gsServerUpdates", 1)
    
    crymp:getActivePlayers()(function(count)
        crymp:record_stat("playersOnline", count)
    end)

    aio:gather(serverFuture, mapFuture)(function (existingServer, existingMap)
        if existingServer and existingServer.error then
            print("get error: ", existingServer.error)
            resolve(nil)
        else
            params.mapDownloadLink = existingMap
            params.lastUpdated = os.date("*t")
            if existingServer then
                local timeDelta = os.time() - os.time(existingServer.lastUpdated)
                local ratio = timeDelta / 30
                local needsFullGSUpdate = false
                if params.maxPlayers == 0 then
                    needsFullGSUpdate = params.source ~= "http" and params.maxPlayers ~= existingServer.maxPlayers
                    params.maxPlayers = existingServer.maxPlayers or 32
                end
                if existingServer.source ~= "http" and params.source ~= "http" then
                    needsFullGSUpdate = true
                end
                params.uptime = existingServer.uptime + timeDelta
                params.activeTime = existingServer.activeTime + (params.numPlayers > 0 and timeDelta or 0)
                params.peopleTime = existingServer.peopleTime + params.numPlayers * timeDelta

                local UP_BIAS = 0.01
                local DOWN_BIAS = 0.00075

                -- max tolerable ratio for upval is 2 minutes worth of play time in delta
                local UP_VAL = math.sqrt(params.numPlayers) * UP_BIAS * math.min(4, ratio)
                local DOWN_VAL = (1 + DOWN_BIAS) ^ ratio

                params.rating = ((existingServer.rating or 0) + UP_VAL) / DOWN_VAL
                params.ratingUpdates = existingServer.ratingUpdates + 1

                if params.source ~= "http" and not needsFullGSUpdate then
                    -- if server already has SSM, let GS update only these
                    params = {
                        ip = params.ip,
                        port = params.port,
                        mapName = params.mapName,
                        gamespyPlayers = params.gamespyPlayers,
                        gamespyPort = params.gamespyPort,
                        maxPlayers = existingServer.maxPlayers == 0 and params.maxPlayers or nil,
                        dx10 = params.dx10,
                        voiceChat = params.voiceChat,
                        dedicated = params.dedicated,
                        antiCheat = params.antiCheat,
                        gamepadsOnly = params.gamepadsOnly,
                        friendlyFire = params.friendlyFire
                    }
                else
                    params.mapName = self:guessMapName(params.map)
                end

                local performUpdate = function()
                    db.servers:update({ip=params.ip, port=params.port}, params)(function (result)
                        if not result or result.error then
                            print("update error: ", result.error)
                            resolve(nil)
                        else
                            -- resolve right away, leave stats as background job
                            resolve(existingServer.cookie)
                            if params.source == "http" then
                                self:updateStatistics(params, existingServer, timeDelta)(function (stats)
                                    if iserror(stats) and not stats.old then
                                        print("failed to update player stats: ", stats.error)
                                        print("query: ", stats.original_query)
                                        print(codec.json_encode({
                                            params = params,
                                            existingServer = existingServer,
                                            timeDelta = timeDelta
                                        }))
                                    end
                                end)
                            end
                        end
                    end)
                end

                -- if server was reachable in past, no need to do this again
                if existingServer.isReal then
                    performUpdate()
                else
                    -- otherwise do ping and verify if it's reachable or not
                    self:ping(params.ip, params.port)(function (reachable)
                        params.isReal = type(reachable) == "number"
                        performUpdate()
                    end)
                end
            else
                self:ping(params.ip, params.port)(function (reachable)
                    params.isReal = type(reachable) == "number"
                    params.players = params.players or ""
                    params.gamespyPlayers = params.gamespyPlayers or ""
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
                end)
            end
        end
    end)
    return resolver
end

--- Issue temporary token for given profile ID at given time
---@param profileId string|number profile ID
---@param time string|number time when token was issued
---@param nickname string player nickname
---@param name string player display name
---@return table
function api:issueToken(profileId, time, nickname, name)
    name = name or "Nomad"
    nickname = nickname or "Nomad"
    profileId = tostring(profileId)
    time = tostring(time)
    local signing = profileId .. "_" .. time

    return {
        id = profileId,
        token = codec.hex_encode(crypto.hmac_sha256(signing, TOKEN_SALT)) .. "_" .. time,
        nickname = nickname,
        name = name
    }
end

--- Update per player statistics for given server
---@param server server_object current server object
---@param before server_object past server object (to compute delta against)
---@param delta integer delta time in seconds
---@return fun(on_resolved: fun(...: any)|thread)
function api:updateStatistics(server, before, delta)
    local resolve, resolver = aio:prepare_promise()
    if delta > 180 then
        resolve({error = "too late to update statistics, delta: " .. delta, old = true})
        return resolver
    end
    local ids = {}
    local now = crymp:exportPlayers(server.players)
    local historic = crymp:exportPlayers(before.players)
    local deltas = {}
    if #now == 0 then
        resolve({updates = 0})
    else
        for _, player in ipairs(historic) do
            if (player.profile_id >= 1 and player.profile_id < 800000) or player.profile_id > 1000000 then
                ids[player.profile_id] = player
            end
        end
        for _, player in ipairs(now) do
            local hit = ids[player.profile_id]
            if hit then
                local diff = {
                    ip = server.ip,
                    port = server.port,
                    playerId = player.profile_id,
                    name = player.name,
                    kills = player.kills - hit.kills,
                    deaths = player.deaths - hit.deaths,
                    playedTime = delta
                }
                -- protect against too high increments, max 7 kills / 30s
                if diff.kills > 7 * (delta / 30) then diff.kills = 0 end
                if diff.deaths > 7 * (delta / 30) then diff.deaths = 0 end
                -- make sure stats cant decrease
                if diff.kills < 0 then diff.kills = 0 end
                if diff.deaths < 0 then diff.deaths = 0 end
                deltas[player.profile_id] = diff
            elseif (player.profile_id >= 1 and player.profile_id < 800000) or player.profile_id > 1000000 then
                deltas[player.profile_id] = {
                    ip = server.ip,
                    port = server.port,
                    playerId = player.profile_id,
                    name = player.name,
                    kills = 0,
                    deaths = 0,
                    playedTime = delta,
                }
                ids[player.profile_id] = player
            end
        end
        local allIds = keys(ids)
        if #allIds == 0 then
            resolve({ok = true})
            return resolver
        end
        db.statistics.all:byIpPortPlayerIds(server.ip, server.port, allIds)(function (current)
            if current and iserror(current) then
                resolve({error = "failed to update stats: " .. current.error .. ", all ids: " .. codec.json_encode(allIds)})
            elseif current then
                local values = {}
                -- update delta into absolute values
                for _, player in ipairs(current) do
                    local record = deltas[player.playerId]
                    if record then
                        record.kills = player.kills + record.kills
                        record.deaths = player.deaths + record.deaths
                        record.playedTime = player.playedTime + record.playedTime
                    end
                end
                for _, player in pairs(deltas) do
                    table.insert(values, player)
                end
                db.statistics:replace(unpack(values))(function (result)
                    resolve(result)
                end)
            else
                resolve({error = "failed to update stats, current was nil"})
            end
        end)
    end
    return resolver
end

--- Validate token provided by user to the game server
---@param profileId string player profile ID
---@param token string provided token
---@return boolean ok true if token is ok
function api:validateToken(profileId, token)
    crymp:record_stat("validations", 1)
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

--- Perform user login on API endpoints
---@param user string nickname or email or ::tr:staticID
---@param password string password secured password or token for staticID
---@param strict boolean|nil if true, only real users with real password are accepted
---@return aiopromise<table> ok
function api:login(user, password, strict)
    strict = strict or false
    if not strict then
        crymp:record_stat("logins", 1)
    end
    local resolve, resolver = aio:prepare_promise()
    local isEmail = user:match("(.-)@(.+)%.(.*)")
    local userFuture = nil
    if isEmail or strict then
        userFuture = db.users.one:byEmail(user:lower())
    else
        userFuture = db.users.one:byNick(user)
    end
    -- if static ID is used
    if not strict and user:match("^::tr:") then
        local profileId = user:sub(6)
        local staticIdSign = self:staticIDToken(profileId)
        if password == staticIdSign then
            resolve(self:issueToken(profileId, os.time(), "Nomad", "Nomad"))
        else
            resolve(nil)
        end
        return resolver
    end
    userFuture(function (user)
        if not user or iserror(user) then
            resolve(nil)
        else
            local delta = os.time() - os.time(user.lastAttempt)
            local attempts = user.loginAttempts + 1
            local result = nil
            if user.loginAttempts >= 20 and delta < 1200 then
                result = {error = "Too many failed attempts, retry again in 20 minutes"}
            elseif user.loginAttempts >= 3 and delta < 60 then
                result = {error = "Too many failed attempts, retry again in 1 minute"}
            elseif hash_password(password) == user.password then
                result = self:issueToken(user.id, os.time(), user.nick, user.display)
                attempts = 0
            elseif not strict and password == hash_secu_login(user.email, user.password) then
                result = self:issueToken(user.id, os.time(), user.nick, user.display)
                attempts = 0
            else
                result = {error = "Invalid username or password"}
            end
            db.users:update(user, {loginAttempts = attempts, lastAttempt = os.date("*t")})(function (upResult)
                if not upResult or iserror(upResult) then
                    resolve({error = "database error"})
                else
                    resolve(result)
                end
            end)
        end
    end)
    return resolver
end

--- Get signed token for static ID
---@param profileId string|number
---@return string signed token
function api:staticIDToken(profileId)
    return codec.hex_encode(crypto.sha1(codec.hex_encode(crypto.hmac_sha256(tostring(profileId), STATIC_ID_SALT))))
end

--- Get or create static ID
---@param hardwareId string
---@param locale string
---@param tz number
---@param clientVer string
---@return aiopromise<table>
function api:getStaticID(hardwareId, locale, tz, clientVer)
    local resolve, resolver = aio:prepare_promise()
    db.staticIds.one:byHwid(hardwareId)(function (result)
        if iserror(result) then
            resolve(nil)
        elseif result ~= nil then
            local profileId = string.format("%d", result.id + 1000000)
            db.staticIds:update({id = result.id}, {
                lastLaunch = os.time(),
                launches = result.launches + 1,
                locale = locale or result.locale or "en-US",
                tz = tz or result.tz or 0,
                clientVersion = clientVer,
            })(function (result)
                resolve({id = profileId, token=self:staticIDToken(profileId)})
            end)
        else
            db.staticIds:insert({
                hwid = hardwareId,
                createdAt = os.time(),
                ip = "-",
                clientVersion = clientVer or "18",
                locale = locale or "en-US",
                tz = tz or 0,
                launches = 1,
                lastLaunch = os.time()
            })(function (result)
                if iserror(result) then
                    resolve(nil)
                else
                    local profileId = tostring(result.last_insert_id + 1000000)
                    resolve({id = profileId, token=self:staticIDToken(profileId)})
                end
            end)
        end
    end)
    return resolver
end

--- Update info about release in database
---@param release_type string release type, release or dev
---@param commit string commit hash
---@param dest string destination
---@return fun(on_resolved: fun(result)|thread)
function api:updateReleaseByCommit(release_type, commit, dest)
    local resolve, resolver = aio:prepare_promise()
    db.releases.one:byReleaseTypeCommit(release_type, commit)(function (result)
        if iserror(result) then
            return resolve(result)
        else
            local entry = {
                releaseType = release_type,
                commit = commit,
                lastUpdated = os.date("*t"),
                hash32 = hash_file(dest .. "/CryMP-Client32.exe"),
                hash64 = hash_file(dest .. "/CryMP-Client64.exe")
            }
            if not entry.hash32 or not entry.hash64 then
                return resolve({error = "failed to compute file hash"})
            end
            if not result then
                db.releases:insert(entry)(function (result)
                    if iserror(result) then
                        resolve(result)
                    else
                        self:getReleaseByCommit(release_type, commit)(resolve)
                    end
                end)
            else
                db.releases:update({releaseType = release_type, commit = commit}, entry)(function (result)
                    if iserror(result) then
                        resolve(result)
                    else
                        self:getReleaseByCommit(release_type, commit)(resolve)
                    end
                end)
            end
        end
    end)
    return resolver
end

--- Get release by commit or if commit is "latest", get latest release
---@param release_type string release type
---@param commit string commit hash
---@return fun(on_resolved: fun(any)|thread)
function api:getReleaseByCommit(release_type, commit)
    release_type = release_type or "release"
    local resolve, resolver = aio:prepare_promise()
    local future = nil
    if commit ~= "latest" then
        future = db.releases.one:byReleaseTypeCommit(release_type, commit)
    else
        future = db.releases.one:byReleaseType(release_type, {orderBy = "updated_at DESC"})
    end
    future(function (result)
        if not result then
            resolve({error = "no release found"})
        elseif iserror(result) then
            resolve({error = "database error"})
        else
            resolve({
                files = {
                    {
                        type = "exe",
                        arch = 32,
                        hash = result.hash32,
                        path = "CryMP-Client32.exe",
                        url = "https://crymp.nullptr.one/static/releases/" .. result.commit .. "/CryMP-Client32.exe"
                    },
                    {
                        type = "exe",
                        arch = 64,
                        hash = result.hash64,
                        path = "CryMP-Client64.exe",
                        url = "https://crymp.nullptr.one/static/releases/" .. result.commit .. "/CryMP-Client64.exe"
                    }
                }
            })
        end
    end)
    return resolver
end

function api:ping(ip, port)
    return aio:cached("ping", ip .. ":" .. port, function ()
        local resolve, resolver = aio:prepare_promise()
        aio:popen_read(ELFD, "./gsemu/bin/ping", ip, port)(function (contents)
            if not contents then
                return resolve(make_error("failed to launch ping"))
            end
            if (tonumber(contents) or 0) < 0 then
                return resolve(make_error("server unreachable"))
            end
            resolve(tonumber(contents))
        end)
        return resolver
    end, 5)
end

--- Update current release based on GitHub API
--- Fetches information about latest release and corresponding ZIP files
---@return fun(on_resolved: fun(any)|thread)
function api:updateReleases()
    return aio:cached("releases", "rel", function()
        local resolve, resolver = aio:prepare_promise()
        aio:popen_read(ELFD, "curl", "--silent", "https://api.github.com/repositories/213009308/releases")(function (contents)
            if not contents then
                return resolve(make_error("failed to download releases from GitHub"))
            end
            local releases = codec.json_decode(contents)
            if releases == nil or #releases < 1 or #releases[1].assets < 1 then
                return resolve(make_error("failed to parse releases from GitHub, response: " .. tostring(contents)))
            end
            local commit = releases[1].target_commitish
            local asset = releases[1].assets[1]
            local target_file = "/tmp/sfwcl_" .. commit .. ".zip"
            local dest = "crymp/public_html/static/releases/" .. commit
            local f, _ = io.open(dest .. "/CryMP-Client64.exe", "rb")
            if f then
                f:close()
                return self:getReleaseByCommit("release", commit)(resolve)
            end
            aio:popen_read(ELFD, "curl", "--silent", "-L", asset.browser_download_url, "--output", target_file)(function (contents)
                if contents == nil then
                    pcall(self.cleanupRelease, self, dest, {target_file})
                    return resolve(make_error("failed to download Zip from GitHub"))
                end
                aio:popen_read(ELFD, "unzip", target_file, "-d", dest)(function (contents)
                    if not contents or not contents:find("inflating") then
                        pcall(self.cleanupRelease, self, dest, {target_file})
                        return resolve(make_error("failed to inflate zip, error: \n" .. tostring(contents)))
                    end
                    pcall(self.cleanupRelease, self, dest, {target_file})
                    self:updateReleaseByCommit("release", commit, dest)(resolve)
                end)
            end)
        end)
        return resolver
    end, 5)
end

function api:updateDevReleases()
    return aio:cached("releases", "dev", function()
        local resolve, resolver = aio:prepare_promise()
        local auth = "Authorization: token " .. GH_ACCESS_TOKEN
        aio:popen_read(ELFD, "curl", "--silent", "-H", auth, "https://api.github.com/repos/crymp-net/client-server/actions/artifacts")(function (contents)
            if not contents then
                return resolve(make_error("failed to download dev releases from GitHub"))
            end
            local releases = codec.json_decode(contents)
            if releases == nil or not releases.artifacts or #releases.artifacts < 1 then
                return resolve(make_error("failed to parse dev releases from GitHub, response: " .. tostring(contents)))
            end
            local has32, has64 = false, false
            for _, artifact in ipairs(releases.artifacts) do
                if artifact.name:match("^(CryMP%-Client64).*$") then
                    if not has32 or has32.workflow_run.head_sha == artifact.workflow_run.head_sha then
                        has64 = artifact
                    end
                elseif artifact.name:match("^(CryMP%-Client32).*$") then
                    if not has64 or has64.workflow_run.head_sha == artifact.workflow_run.head_sha then
                        has32 = artifact
                    end
                end
                if has64 and has32 then break end
            end
            if has64 and has32 then
                local commit = has32.workflow_run.head_sha
                local target_file = "/tmp/sfwcl_" .. commit
                local dest = "crymp/public_html/static/releases/" .. commit
                local f, _ = io.open(dest .. "/CryMP-Client64.exe", "rb")
                if f then
                    f:close()
                    return self:getReleaseByCommit("dev", commit)(resolve)
                end
                local get32 = aio:popen_read(ELFD, "curl", "--silent", "-L", "-H", auth, has32.archive_download_url, "--output", target_file .. "_32.zip")
                local get64 = aio:popen_read(ELFD, "curl", "--silent", "-L", "-H", auth, has64.archive_download_url, "--output", target_file .. "_64.zip")
                aio:gather(get32, get64)(function (res32, res64)
                    if not res32 or not res64 then
                        pcall(self.cleanupRelease, self, dest, {target_file .. "_32.zip", target_file .. "_64.zip"})
                        return resolve(make_error("downloading release ZIP failed"))
                    end
                    local unzip32 = aio:popen_read(ELFD, "unzip", target_file .. "_32.zip", "-d", dest)
                    local unzip64 = aio:popen_read(ELFD, "unzip", target_file .. "_64.zip", "-d", dest)
                    aio:gather(unzip32, unzip64)(function (contents32, contents64)
                        if not contents32 or not contents32:find("inflating") or not contents64 or not contents64:find("inflating") then
                            pcall(self.cleanupRelease, self, dest, {target_file .. "_32.zip", target_file .. "_64.zip"})
                            return resolve(make_error("failed to inflate zip, 32bit: \n" .. tostring(contents32) .. "\n64bit: " .. tostring(contents64)))
                        end
                        pcall(self.cleanupRelease, self, dest, {target_file .. "_32.zip", target_file .. "_64.zip"})
                        self:updateReleaseByCommit("dev", commit, dest)(resolve)
                    end)
                end)
            else
                resolve(make_error("failed to find pair of executables"))
            end
        end)
        return resolver
    end, 5)
end

function api:cleanupRelease(dest, files)
    local dest_files = net.listdir(dest .. "/")
    for _, file in ipairs(dest_files) do
        if file:match("%.pdb$") then
            pcall(os.remove, dest .. "/" .. file)
        end
    end
    for _, file in ipairs(files) do
        pcall(os.remove, file)
    end
end

return api