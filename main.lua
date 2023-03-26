local db = require("crymp.db")
local aio = require("aio.aio")

crymp = {}
Servers = db.servers
Users = db.users
Posts = db.posts
Threads = db.threads
Subcategories = db.subcategories
Categories = db.categories

local DELETED_USER = {display="Deleted user", id=0, rights=4}

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
    return hash(hash_sha1(text) .. "S11!.bCxD");
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

function crymp:getForum(rights)
    local resolve, resolver = aio:prepare_promise()
    if CACHED_FORUM then
        resolve(CACHED_FORUM)
    else
        self:_getForum(rights)(function (forum)
            CACHED_FORUM = forum
            resolve(forum)
        end)
    end
    return resolver
end

function crymp:_getForum(rights)
    local resolve, resolver = aio:prepare_promise()
    local categoriesFuture = Categories.all:by()
    local subcategoriesFuture = Subcategories.all:by()
    local threadsFuture = Threads.all:by({orderBy = "subc ASC, last_post_time DESC"})
    local now = os.time()
    local month = 90 * 86400
    aio:gather(categoriesFuture, subcategoriesFuture, threadsFuture)(function (categories, subcategories, threads)
        if categories == nil or subcategories == nil or threads == nil then
            return resolve({})
        else
            local perCategory = {}
            local subcategoryLU = {}
            local userIds = {}
            local postIds = {}
            for _, subcategory in ipairs(subcategories) do
                subcategory.threads = {}
                subcategoryLU[subcategory.id] = subcategory
                if subcategory.rights <= rights then
                    perCategory[subcategory.main] = perCategory[subcategory.main] or {}
                    table.insert(perCategory[subcategory.main], subcategory)
                end
            end
                
            for _, thread in ipairs(threads) do
                local subcategory = subcategoryLU[thread.subc]
                if subcategory ~= nil then
                    local bucket = subcategory.threads
                    if #bucket < 3 and (#bucket < 2 or (now - thread.lastPostTime) < month) then
                        table.insert(bucket, thread)
                        userIds[thread.author] = true
                        table.insert(postIds, thread.lastPostId)
                    end
                end
            end

            Posts.all:findAuthorByIdIn(postIds)(function (result, error)
                if result then
                    local postAuthors = {}
                    for _, post in ipairs(result) do
                        userIds[post.author] = true
                        postAuthors[post.id] = post.author
                    end
                    Users.all:byIdIn(keys(userIds))(function(result, error)
                        if not result then
                            return resolve({})
                        end
                        local forum = {}
                        users = {}
                        for _, user in ipairs(result) do
                            users[user.id] = user
                        end
                        for _, thread in ipairs(threads) do
                            thread.author = users[thread.author] or DELETED_USER
                            thread.lastPostBy = users[postAuthors[thread.lastPostId] or 0] or DELETED_USER
                        end
                        for _, category in ipairs(categories) do
                            if category.rights <= rights then
                                category.subcategories = perCategory[category.id] or {}
                                table.insert(forum, category)
                            end
                        end
                        resolve(forum)
                    end)
                else
                    resolve({})
                end
            end)
        end
    end)
    return resolver
end

function crymp:getForumThread(id, rights, page, perPage)
    local resolve, resolver = aio:prepare_promise()
    if type(page) == "string" then
        if page == "last" then
            page = -1
        else
            page = tonumber(page) or 0
        end
    else
        page = tonumber(page)
    end
    local threadFuture = Threads.one:byId(id)
    local postsFuture = Posts.all:byThread(id)
    aio:gather(threadFuture, postsFuture)(function (thread, posts)
        if thread and posts then
            local pages = math.floor((#posts - 1) / perPage)
            if page < 0 then
                page = pages + page + 1
            else
                page = page - 1
            end
            if page > pages then
                page = pages - 1
            end
            if page < 0 then
                page = 0
            end
            thread.pages = pages
            thread.page = page
            local viewable = {}
            local userIds = {}
            userIds[thread.author] = true
            for i=1 + page*perPage, math.min(#posts, page*perPage + perPage) do
                local post = posts[i]
                table.insert(viewable, post)
                userIds[post.author] = true
            end
            local usersFuture = Users.all:byIdIn(keys(userIds))
            local subcategoryFuture = Subcategories.one:byId(thread.subc)
            aio:gather(usersFuture, subcategoryFuture)(function (users, subcategory)
                if not subcategory or subcategory.rights > rights then
                    return resolve(nil)
                end
                local byId = {}
                if users then
                    for _, user in ipairs(users) do
                        if not user.picture or #user.picture <= 1 then user.picture = "/static/images/face.png" end
                        byId[user.id] = user
                    end
                end
                for _, post in ipairs(viewable) do
                    post.author = byId[post.author] or DELETED_USER
                end
                thread.posts = viewable
                thread.author = byId[thread.author] or DELETED_USER
                resolve(thread)
            end)
        else
            resolve(nil)
        end
    end)
    return resolver
end

function crymp:encodePostText(text)
    return aio:cached("post", text, function()
        text = codec.html_encode(text)
        
        text = text:gsub("%[quote](.-)%[/quote]", function(a) return string.format("<div class=\"quote\">%s</div>", a) end)
        text = text:gsub("%[b](.-)%[/b]", function(a) return string.format("<b>%s</b>", a) end)
        text = text:gsub("%[u](.-)%[/u]", function(a) return string.format("<u>%s</u>", a) end)
        text = text:gsub("%[i](.-)%[/i]", function(a) return string.format("<i>%s</i>", a) end)
        text = text:gsub("%[small](.-)%[/small]", function(a) return string.format("<small>%s</small>", a) end)
        text = text:gsub("%[h1](.-)%[/h1]", function(a) return string.format("<h1>%s</h1>", a) end)
        text = text:gsub("%[h2](.-)%[/h2]", function(a) return string.format("<h2>%s</h2>", a) end)
        text = text:gsub("%[h3](.-)%[/h3]", function(a) return string.format("<h3>%s</h3>", a) end)
        text = text:gsub("%[code](.-)%[/code]", function(a) return string.format("<code>%s</code>", a) end)

        text = text:gsub("%[img]([^\"<>]+)%[/img]", function(a) return string.format("<a href=\"%s\" target=\"_blank\"><img src=\"%s\" style=\"max-width: 100%% cursor: pointer;\"></a>", a, a) end)

        text = text:gsub("%[yt]https://youtu%.be/([^\"&<>]-)%[/yt]", function(c)
            return string.format("<iframe style=\"max-width: 100%%\" width=\"800\" height=\"480\" src=\"https://www.youtube.com/embed/%s?feature=player_embedded\" frameborder=\"0\" allowfullscreen ytype=\"1\"></iframe>", c) 
        end)
        text = text:gsub("%[yt]https://www%.youtube%.com/watch%?v=([^\"&<>]-)%[/yt]", function(c)
            return string.format("<iframe style=\"max-width: 100%%\" width=\"800\" height=\"480\" src=\"https://www.youtube.com/embed/%s?feature=player_embedded\" frameborder=\"0\" allowfullscreen ytype=\"2\"></iframe>", c) 
        end)
        text = text:gsub("%[yt]([a-zA-Z0-9_\\-]-)%[/yt]", function(a) 
            return string.format("<iframe style=\"max-width: 100%%\" width=\"800\" height=\"480\" src=\"https://www.youtube.com/embed/%s?feature=player_embedded\" frameborder=\"0\" allowfullscreen ytype=\"3\"></iframe>", a) 
        end)
        text = text:gsub("%[url](.-)%[/url]", function(a) return a end)

        text = text:gsub("^http(s?)://([^ \n\t\r<>\"]+)", function(ssl, link)
            return string.format("<a href=\"http%s://%s\" target=\"_blank\" rel=\"nofollow\">http%s://%s</a>", ssl or "", link, ssl or "", link)
        end)

        text = text:gsub("([^>\"])http(s?)://([^ \n\t\r<>\"]+)", function(pre, ssl, link)
            return string.format("%s<a href=\"http%s://%s\" target=\"_blank\" rel=\"nofollow\">http%s://%s</a>", pre, ssl or "", link, ssl or "", link)
        end)

        return text
    end)
end