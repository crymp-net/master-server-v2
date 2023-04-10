local db = require("crymp.db")
local aio = require("aio.aio")
local orm = require("server.orm")
local web_ui = loadfile("crymp/web_ui.lua")()
local web_api = loadfile("crymp/web_api.lua")()

crymp = {
    web = web_ui,
    api = web_api
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
    return os.date("!%Y-%m-%dT%T", time)
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

--- Get border timestamp for getting servers
---@return string
function crymp:getBorder()
    return orm.t.datetime.toformat(os.time() - 86400 * 365)
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
        return db.statistics.one:byUser(params.profileId)
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
                resolve(tonumber(result.total_players))
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