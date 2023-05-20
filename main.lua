local db = require("crymp.db")
local aio = require("aio.aio")
local orm = require("server.orm")
local web_ui = loadfile("crymp/web_ui.lua")()
local web_api = loadfile("crymp/web_api.lua")()

aio:set_max_cache_size(100000)

local prev_stats = nil
if crymp then
    prev_stats = crymp.stats
end

crymp = {
    web = web_ui,
    api = web_api,
    stats = prev_stats or {
        apiLatency = {total = 0, count = 0, medians = {}},
        wwwLatency = {total = 0, count = 0, medians = {}},
        playersOnline = {total = 0, count = 0, medians = {}},
        logins = {total = 0, count = 0, medians = {}},
        validations = {total = 0, count = 0, medians = {}},
        serverUpdates = {total = 0, count = 0, medians = {}},
        gsServerUpdates = {total = 0, count = 0, medians = {}}
    },
    record_stat = function(self, key, value)
        if self.stats[key] then
            self.stats[key].total = self.stats[key].total + value
            self.stats[key].count = self.stats[key].count + 1
            -- if we get too many medians, remove one to keep it at 5k max
            if #self.stats[key].medians == 5000 then
                table.remove(self.stats[key].medians, 1)
            end
            table.insert(self.stats[key].medians, value)
        end
    end,
    collect_stats = function(self)
        for i, v in pairs(self.stats) do
            self.stats[i].average = self.stats[i].total / math.max(1, self.stats[i].count)
            table.sort(self.stats[i].medians)
            local median = 0
            local n = #self.stats[i].medians
            if n > 0 then
                if n % 2 == 0 then
                    median = (self.stats[i].medians[math.floor(n / 2)] + self.stats[i].medians[math.floor(n / 2 + 1)]) / 2
                else
                    median = self.stats[i].medians[math.floor((n - 1) / 2)]
                end
            end
            self.stats[i].median = median
        end
        return self.stats
    end,
    reset_stats = function(self)
        for i, v in pairs(self.stats) do
            self.stats[i] = {total = 0, count = 0, medians={}}
        end
    end
}

Servers = db.servers
Users = db.users
Posts = db.posts
Threads = db.threads
Subcategories = db.subcategories
Categories = db.categories

USER_SALT = os.getenv("USER_SALT") or "user-salt"
SECURE_LOGIN_SALT = os.getenv("SECURE_LOGIN_SALT") or "secure-login-salt"
TOKEN_SALT = os.getenv("TOKEN_SALT") or "token-salt"
STATIC_ID_SALT = os.getenv("STATIC_ID_SALT") or "static-id-salt"
RELEASE_SALT = os.getenv("RELEASE_SALT") or "release-salt"
PROXY_SECRET = os.getenv("PROXY_SECRET") or "proxy-secret"
GH_ACCESS_TOKEN = os.getenv("GH_ACCESS_TOKEN") or "gh-access-token"

function isodate(time)
    local ok, result = pcall(os.date, "!%Y-%m-%dT%T", time)
    if ok then return result end
    -- windows compatibility
    local ok, result = pcall(os.date, "%Y-%m-%dT%H:%I:%S", time)
    if ok then return result end
    return os.date()
end

function hash(text)
    return codec.hex_encode(crypto.sha256(text))
end

function hash_file(file)
    local f, _ = io.open(file, "rb")
    if not f then return nil end
    local contents = f:read("*all")
    f:close()
    return hash(contents)
end

function hash_sha1(text)
    return codec.hex_encode(crypto.sha1(text))
end

function hash_password(text)
    return hash(hash_sha1(text) .. USER_SALT);
end

function hash_secu_login(email, hashed_password)
    return hash_sha1(hashed_password .. "_" .. email .. SECURE_LOGIN_SALT)
end

function keys(dict)
    local k = {}
    for i, _ in pairs(dict) do table.insert(k, i) end
    return k
end

function on_before_http(method, endpoint, session)
    session.http_start = net.clock()
end

function on_after_http(method, endpoint, session)
    local latency = (net.clock() - session.http_start) * 1000 -- must be in ms
    if endpoint:match("^/api/") then
        crymp:record_stat("apiLatency", latency)
    else
        crymp:record_stat("wwwLatency", latency)
    end
end

--- Get border timestamp for getting servers
---@return string
function crymp:getBorder()
    return orm.t.datetime.toformat(os.time() - 240)
end

--- Get list of servers
---@param all boolean|nil if true, unreachable servers are returned
---@return aiopromise<table[]|mysqlerror>
function crymp:getServers(all)
    return aio:cached("servers", tostring(all), function()
        all = all or false
        local border = self:getBorder()
        if all then
            return Servers.all:byActiveAll(border, {orderBy="is_real DESC, num_players DESC, rating DESC"})
        else
            return Servers.all:byActive(border, {orderBy="num_players DESC, rating DESC"})
        end
    end, 3)
end

--- Get server by IP and port
---@param ip string
---@param port integer|string|nil
---@return aiopromise<table|mysqlerror|nil>
function crymp:getServer(ip, port)
    port = tonumber(port)
    return Servers.one:byIpPort(ip, port)
end

--- Format time
---@param seconds integer seconds time
---@param pretty boolean|string prettify, can be either bool or "short"
---@return string time
function crymp:formatTime(seconds, pretty)
    seconds = tonumber(seconds) or 0
    if pretty then
        local h, m, a = "hours", "minutes", " and "
        if pretty == "short" then
            h = "h"
            m = "min"
            a = ", "
        end
        if seconds < 3600 then
            return math.floor(seconds / 60) .. " " .. m
        else
            return string.format("%d %s%s%d %s", math.floor(seconds / 3600), h, a, math.floor((seconds / 60) % 60), m)
        end
    end
    if seconds == 0 then
        seconds = "unlimited"
    else
        seconds = string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
    end
    return seconds
end

--- Get game rules from map name
---@param map string map name
---@return string rules
function crymp:getGameRules(map)
    local rules = (map or "multiplayer/ps/mesa"):match("/ps/") and "Power Struggle" or "Instant Action"
    return rules
end

--- Get user by params
---@param params any
---@return aiopromise<table|nil>|nil user
function crymp:getUser(params)
    if params.id then
        return Users.one:byId(params.id)
    elseif params.email then
        return Users.one:byEmail(params.email)
    elseif params.nick then
        return Users.one:byNick(params.nick)
    end
end

--- Update last seen timestamp for user
---@param user any requester user
---@return nil
function crymp:touch(user)
    -- calling this once every 60s is fine
    return aio:cached("touch", tostring(user.id), function ()
        return db.users:update(user, {
            lastSeen = os.time()
        })
    end, 60)
end

--- Get statistics according to params
---@param params any params
---@return aiopromise<{kills: integer, deaths: integer, playedTime: integer}>|nil
function crymp:getStatistics(params)
    if params.profileId then
        return aio:cached("stats", params.profileId, function ()
            return db.statistics.one:byUser(params.profileId)
        end, 60)
    end
end

--- Get number of active players
---@return aiopromise<integer>
function crymp:getActivePlayers()
    return aio:cached("servers", "active", function()
        local resolve, on_resolved = aio:prepare_promise()
        Servers.one:byOnline(self:getBorder())(function (result)
            if not result or iserror(result) then
                resolve(0)
            else
                resolve(tonumber(result.total_players or 0))
            end
        end)
        return on_resolved
    end, 1)
end

--- Convert @name%rank%kills%deaths%pid%team ... string to objects
---@param text any
---@return {name: string, rank: number, kills: number, deaths: number, profile_id: number, team: number|nil}[] players
function crymp:exportPlayers(text)
    local players = {}
    text = text or ""
    if #text < 2 then return {} end
    for player in text:gmatch("%@([^@]+)") do
        local name, rank, kills, deaths, pid = player:match("(.-)%%(%d+)%%(%d+)%%(%d+)%%(.+)")
        if name and rank and kills and deaths and pid then
            local team =nil
            if pid:find("%%") then
                pid, team = pid:match("(%d+)%%(%d+)")
                team = tonumber(team)
            end
            table.insert(players, {
                name = name,
                rank = tonumber(rank),
                kills = tonumber(kills),
                deaths = tonumber(deaths),
                profile_id = tonumber(pid),
                team = team
            }) 
        end
    end
    return players
end