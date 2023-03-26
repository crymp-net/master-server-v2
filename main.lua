local db = require("crymp.db")
local aio = require("aio.aio")
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

local USER_SALT = os.getenv("USER_SALT") or "user-salt"

function hex(bytes)
    --- @type string[]|integer[]
    local result = {bytes:byte(1, #bytes)}
    for i=1,#result do
        result[i] = string.format("%02x", result[i])
    end
    return table.concat(result)
end

function isodate(time)
    return os.date("!%Y-%m-%dT%T", time)
end

function hash(text)
    return hex(crypto.sha256(text))
end

function hash_sha1(text)
    return hex(crypto.sha1(text))
end

function hash_password(text)
    return hash(hash_sha1(text) .. USER_SALT);
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

function crymp:getServers()
    return aio:cached("servers", "all", function()
        return Servers.all:by({orderBy="num_players DESC, rating DESC"})
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
    end
end

function crymp:getActivePlayers()
    local resolve, on_resolved = aio:prepare_promise()
    db.sql:select("SELECT SUM(num_players) as activePlayers FROM server")(function (rows, errorOrColumns)
        if not rows then
            resolve(0)
        else
            resolve(tonumber(rows[1].activePlayers))
        end
    end)
    return on_resolved
end

function crymp:exportPlayers(text)
    local players = {}
    for player in text:gmatch("%@([^@]+)") do
        local name, rank, kills, deaths, pid = player:match("(.-)%%(%d+)%%(%d+)%%(%d+)%%(.+)")
        if name and rank and kills and deaths and pid then
            local team = "0"
            if pid:find("%%") then
                pid, team = pid:match("(%d+)%%(%d+)")
            end
            table.insert(players, {
                name = name,
                rank = tonumber(rank),
                kills = tonumber(kills),
                deaths = tonumber(deaths),
                profile_id = tonumber(pid),
                team = tonumber(team)
            }) 
        end
    end
    return players
end