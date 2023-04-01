local mysql = require("server.mysql")
local orm = require("server.orm")

--- @type mysql
local sql = CRYMP_SQL
if not sql then
    CRYMP_SQL = mysql:new()
    sql = CRYMP_SQL
    local user, password, db = os.getenv("DB_USER") or "80s", os.getenv("DB_PASSWORD") or "password", os.getenv("DB_NAME") or "nsfw"
    sql:connect(user, password, db)(function (ok, err)
        if not ok then
            print("Failed to connect to SQL: ", err)
        end
    end)
end

--- @class server_object
--- @field ip string
--- @field port integer
--- @field behindProxy boolean
--- @field source string
--- @field localIp string
--- @field publicPort integer
--- @field gamespyPort integer
--- @field name string
--- @field description string
--- @field pak string
--- @field map string
--- @field mapName string
--- @field mapDownloadLink string
--- @field players string
--- @field gamespyPlayers string|nil
--- @field password string
--- @field ranked boolean
--- @field numPlayers integer
--- @field maxPlayers integer
--- @field gameVersion integer
--- @field timeLeft integer
--- @field dx10 boolean
--- @field voiceChat boolean
--- @field antiCheat boolean
--- @field dedicated boolean
--- @field rating number|nil
--- @field gamepadsOnly boolean
--- @field friendlyFire boolean

--- @type ormrepo
local servers = orm:create(sql, {
    source = "server",
    index = {"ip", "port"},
    --- @type ormentity
    entity = {
        ip = { field = "ip", type = orm.t.varchar(255) },
        port = { field = "port", type = orm.t.int },
        activeTime = { field = "active_time", type = orm.t.int },
        antiCheat = { field = "anti_cheat", type = orm.t.bit },
        behindProxy = { field = "behind_proxy", type = orm.t.bit },
        cookie = { field = "cookie", type = orm.t.varchar(255) },
        dedicated = { field = "dedicated", type = orm.t.bit },
        description = { field = "description", type = orm.t.text },
        dx10 = { field = "dx10", type = orm.t.bit },
        friendlyFire = { field = "friendly_fire", type = orm.t.bit },
        game = { field = "game", type = orm.t.varchar(255) },
        gameVersion = { field = "game_version", type = orm.t.int },
        gamepadsOnly = { field = "gamepads_only", type = orm.t.bit },
        gamespyPlayers = { field = "gamespy_players", type = orm.t.text },
        gamespyPort = { field = "gamespy_port", type = orm.t.int },
        lastUpdated = { field = "last_updated", type = orm.t.datetime },
        localIp = { field = "local_ip", type = orm.t.varchar(255) },
        map = { field = "map", type = orm.t.varchar(255) },
        mapDownloadLink = { field = "map_download_link", type = orm.t.varchar(255) },
        mapName = { field = "map_name", type = orm.t.varchar(255) },
        maxPlayers = { field = "max_players", type = orm.t.int },
        name = { field = "name", type = orm.t.varchar(255) },
        numPlayers = { field = "num_players", type = orm.t.int },
        pak = { field = "pak", type = orm.t.varchar(255) },
        password = { field = "password", type = orm.t.varchar(255) },
        peopleTime = { field = "people_time", type = orm.t.int },
        players = { field = "players", type = orm.t.text },
        publicPort = { field = "public_port", type = orm.t.int },
        ranked = { field = "ranked", type = orm.t.bit },
        rating = { field = "rating", type = orm.t.double },
        ratingUpdates = { field = "rating_updates", type = orm.t.int },
        isReal = { field = "is_real", type = orm.t.bit },
        source = { field = "source", type = orm.t.varchar(255) },
        timeLeft = { field = "time_left", type = orm.t.int },
        uptime = { field = "uptime", type = orm.t.int },
        voiceChat = { field = "voice_chat", type = orm.t.bit },
    },
    findByIpPort = true,
    findByIsReal = true,
    findBy = true,
    findByActive = "SELECT * FROM server WHERE last_updated > '%s' AND is_real = '\\1'",
    findByOnline = "SELECT SUM(num_players) AS total_players FROM server WHERE last_updated > '%s' AND is_real = '\\1'"
})

local users = orm:create(sql, {
    source = "f_users",
    index = "id",
    --- @type ormentity
    entity = {
        id = { field = "id", type = orm.t.int },
        nick = { field = "nick", type = orm.t.varchar(26) },
        email = { field = "email", type = orm.t.text },
        display = { field = "display", type = orm.t.text },
        rights = { field = "rights", type = orm.t.int },
        picture = { field = "photo", type=orm.t.text }
    },
    findById = true,
    findByIdIn = "WHERE id IN %s",
    findBy = true,
    findByEmail = true,
    findByNick = true
})

local posts = orm:create(sql, {
    source = "f_posts",
    index = "id",
    --- @type ormentity
    entity = {
        id = { field="id", type=orm.t.int },
        author = { field="author", type=orm.t.int },
        createdAt = { field="date", type=orm.t.int },
        text = { field="text", type=orm.t.text },
        thread = { field="thread", type=orm.t.int },
        likeCount = { field="like_count", type=orm.t.int },
        invisible = { field="invisible", type=orm.t.int }
    },
    findByThread = true,
    findById = true,
    findAuthorByIdIn = "SELECT id, author FROM f_posts WHERE id IN %s"
})

local threads = orm:create(sql, {
    source = "f_threads",
    index = "id",
    --- @type ormentity
    entity = {
        id = { field="id", type=orm.t.int },
        author = { field="author", type=orm.t.int },
        name = { field="name", type=orm.t.text },
        subc = { field="subc", type=orm.t.int },
        createdAt = { field="date", type=orm.t.int },
        hidden = { field="hidden", type=orm.t.int },
        encrypted = { field="encrypted", type=orm.t.int },
        lastPostId = { field="last_post_id", type=orm.t.int },
        lastPostTime = { field="last_post_time", type=orm.t.int }
    },
    findById = true,
    findBy = true
})

local subcategories = orm:create(sql, {
    source = "f_subc",
    index = "id",
    --- @type ormentity
    entity = {
        id = { field="id", type=orm.t.int },
        main = { field="main", type=orm.t.int },
        name = { field="name", type=orm.t.text },
        rights = { field="rights", type=orm.t.int }
    },
    findBy = true,
    findById = true
})

local categories = orm:create(sql, {
    source = "f_categories",
    index = "id",
    --- @type ormentity
    entity = {
        id = { field="id", type=orm.t.int },
        name = { field="name", type=orm.t.text },
        rights = { field="rights", type=orm.t.int }
    },
    findBy = true
})

local maps = orm:create(sql, {
    source = "map_repo_entry",
    index = {"map_name", "version"},
    --- @type ormentity
    entity = {
        mapName = { field = "map_name", type=orm.t.varchar(255) },
        version = { field = "version", type=orm.t.varchar(255) },
        autoGenerated = {field = "auto_generated", type=orm.t.bit },
        creatorName = {field = "creator_name", type=orm.t.varchar(255)},
        url = {field = "url", type=orm.t.varchar(255)}
    },

    findByMapNameVersion = true
})

return {
    sql = sql,
    servers = servers,
    users = users,
    posts = posts,
    threads = threads,
    subcategories = subcategories,
    categories = categories,
    maps = maps
}
