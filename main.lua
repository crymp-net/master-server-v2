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

function sign(text, salt)
    return string.format("%s.%s", text, hash(text .. salt))
end

function signed(text, salt)
    if type(text) ~= "string" then
        return nil
    end
    local payload, signature = text:match("(.*)%.([a-f0-9]+)$")
    if payload and signature then
        if hash(payload .. salt) == signature then
            return payload
        end
    end
    return nil
end

function crymp:getBorder()
    return orm.t.datetime.toformat(os.time() - 86400 * 365)
end

function crymp:getServers()
    return aio:cached("servers", "all", function()
        local border = self:getBorder()
        return Servers.all:byActive(border, {orderBy="num_players DESC, rating DESC"})
    end)
end

function crymp:getServer(ip, port)
    port = tonumber(port)
    return Servers.one:byIpPort(ip, port)
end

function crymp:formatTime(seconds)
    seconds = seconds or 0
    if seconds == 0 then
        seconds = "unlimited"
    else
        seconds = string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
    end
    return seconds
end

function crymp:getGameRules(map)
    local rules = (map or "multiplayer/ps/mesa"):match("/ps/") and "PowerStruggle" or "InstantActon"
    return rules
end

function crymp:getUser(params)
    if params.id then
        return Users.one:byId(params.id)
    elseif params.email then
        return Users.one:byEmail(params.email)
    elseif params.nick then
        return Users.one:byNick(params.nick)
    end
end

function crymp:getActivePlayers()
    local resolve, on_resolved = aio:prepare_promise()
    Servers.one:byOnline(self:getBorder())(function (result)
        if not result or iserror(result) then
            resolve(0)
        else
            resolve(tonumber(result.total_players))
        end
    end)
    return on_resolved
end

--- Convert @name%rank,kills,deaths,pid%team ... string to objects
---@param text any
---@return {name: string, rank: number, kills: number, deaths: number, profile_id: number, team: number|nil}[] players
function crymp:exportPlayers(text)
    local players = {}
    text = text or ""
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