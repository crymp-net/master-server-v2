local db = require("crymp.db")
local DELETED_USER = {display="Aztec", id=0, rights=4}

--- @class web_ui
local web = {}

--- Get entire forum as a traversable tree structure for UI (can be cached later as well)
---@param rights integer requester user rights
---@return fun(on_resolved: fun(...: any)|thread)
function web:getForum(rights)
    return aio:cached("forum", tostring(rights), function()
        local resolve, resolver = aio:prepare_promise()
        local latest, latest3 = {}, {}
        local categoriesFuture = db.categories.all:by()
        local subcategoriesFuture = db.subcategories.all:by()
        local threadsFuture = db.threads.all:by({orderBy = "subc ASC, last_post_time DESC"})
        local now = os.time()
        local month = 90 * 86400
        aio:gather(categoriesFuture, subcategoriesFuture, threadsFuture)(function (categories, subcategories, threads)
            if not ispresent(categories, subcategories, threads) then
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
                            table.insert(latest, thread)
                        end
                    end
                end

                table.sort(latest, function (a, b)
                    return a.lastPostTime > b.lastPostTime
                end)

                for i=1, math.min(#latest, 3) do
                    table.insert(latest3, latest[i])
                end

                db.posts.all:findAuthorByIdIn(postIds)(function (result)
                    if result and ispresent(result) then
                        local postAuthors = {}
                        for _, post in ipairs(result) do
                            userIds[post.author] = true
                            postAuthors[post.id] = post.author
                        end
                        db.users.all:byIdIn(keys(userIds))(function(result)
                            if not result or not ispresent(result) then
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
                            if #latest3 > 0 then
                                table.insert(forum, {
                                    rights = 1,
                                    id = 0,
                                    name = "Latest",
                                    subcategories = {
                                        {
                                            rights = 1,
                                            id = 0,
                                            name = "Latest threads",
                                            threads = latest3
                                        }
                                    }
                                })
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
    end, 5)
end

function web:getSubcategory(rights, subcategory_id)
    return aio:cached("forum", "sub" .. rights, function()
        local resolve, resolver = aio:prepare_promise()
        db.subcategories.one:byId(subcategory_id)(function (subcategory)
            if not subcategory or iserror(subcategory) then
                resolve(subcategory)
                return
            end
            if subcategory.rights > rights then
                resolve({error = "unauthorized"})
                return
            end
            db.threads.all:bySubc(subcategory_id, {orderBy="last_post_time DESC, id DESC"})(function (threads)
                if not threads or iserror(threads) then
                    resolve({error = "failed to fetch threads"})
                    return
                end
                local userIds = {}
                local posts = {}
                for _, thread in ipairs(threads) do
                    table.insert(posts, thread.lastPostId)
                    userIds[thread.author] = false
                end
                db.posts.all:findAuthorByIdIn(posts)(function (result)
                    if not result or iserror(result) then
                        resolve({error = "failed to fetch author ids"})
                        return
                    end
                    local postAuthors = {}
                    for _, post in ipairs(result) do
                        userIds[post.author] = false
                        postAuthors[post.id] = post.author
                    end
                    db.users.all:byIdIn(keys(userIds))(function (users)
                        if not result or iserror(result) then
                            resolve({error = "failed to fetch authors"})
                            return
                        end
                        for _, user in ipairs(users) do
                            userIds[user.id] = user
                        end
                        for _, thread in ipairs(threads) do
                            thread.author = userIds[thread.author] or DELETED_USER
                            thread.lastPostBy = userIds[postAuthors[thread.lastPostId] or 0] or DELETED_USER
                        end
                        subcategory.threads = threads
                        resolve(subcategory)
                    end)
                end)
            end)
        end)
        return resolver
    end, 5)
end

--- Get URL of user's profile picture
---@param user any user object
---@return string picture URL
function web:getPicture(user)
    if not user.picture or #user.picture <= 1 then 
        return "/static/images/face.png"
    else
        return user.picture:gsub("%.?%.?/?static/", "/static/ucg/profile/")
    end
end

--- Get forum thread at given page with all required user objects
---@param id integer thread id
---@param rights integer requester rights
---@param page integer|string page
---@param perPage integer posts per page
---@return fun(on_resolved: fun(...: any)|thread)
function web:getForumThread(id, rights, page, perPage)
    local resolve, resolver = aio:prepare_promise()
    if type(page) == "string" then
        if page == "last" then
            page = -1
        else
            page = tonumber(page) or 0
        end
    else
        page = tonumber(page) or 1
    end
    local threadFuture = db.threads.one:byId(id)
    local postsFuture = db.posts.all:byThread(id)
    aio:gather(threadFuture, postsFuture)(function (thread, posts)
        if ispresent(thread) and ispresent(posts) then
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
            local usersFuture = db.users.all:byIdIn(keys(userIds))
            local subcategoryFuture = db.subcategories.one:byId(thread.subc)
            aio:gather(usersFuture, subcategoryFuture)(function (users, subcategory)
                if not ispresent(subcategory, users) or subcategory.rights > rights then
                    return resolve(nil)
                end
                local byId = {}
                if users then
                    for _, user in ipairs(users) do
                        user.picture = self:getPicture(user)
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

--- Add forum post
---@param user {id: integer} user that is logged in
---@param thread_id integer thread ID
---@param text string post text
---@return orminsert 
function web:addForumThreadPost(user, thread_id, text)
    -- we can trust that user has access to given thread as otherwise signed query wouldn't fit
    local now = os.time()
    local resolve, resolver = aio:prepare_promise()
    db.posts:insert({
        author = user.id,
        createdAt = now,
        text = text,
        thread = thread_id,
        likeCount = 0,
        invisible = 0
    })(function (result)
        if iserror(result) then
            resolve(nil)
        else
            local postId = result.last_insert_id
            db.threads:update({id = thread_id}, {
                lastPostId = postId,
                lastPostTime = now
            })(function (result)
                resolve(postId)
            end)
        end
    end)
    return resolver
end

--- Update form post text
---@param user any requester object
---@param threadId integer thread id
---@param postId integer post id
---@param text string new text
function web:updateForumThreadPost(user, threadId, postId, text)
    return db.posts:update({id = postId}, {text=text})
end


--- Add or remove like from post by user
---@param user any requester user object
---@param post_id integer post id
---@return fun(on_resolved: fun(result: ormerror|{incr: integer})|thread)
function web:likePost(user, post_id)
    local resolve, resolver = aio:prepare_promise()

    local updateCounts = function ()
        return db.posts.sql:exec("UPDATE f_posts SET like_count = (SELECT COUNT(*) FROM likes WHERE likes.post_id = '%d') WHERE f_posts.id = '%d' LIMIT 1", post_id, post_id)
    end

    db.likes.one:byUserIdPostId(user.id, post_id)(function (result)
        if iserror(result) then
            resolve(result)
        elseif not result then
            db.likes:insert({userId = user.id, postId = post_id})(function (result)
                if not result or iserror(result) then
                    resolve(result)
                else
                    updateCounts()(function (result)
                        resolve({incr = 1})
                    end)
                end
            end)
        else
            db.likes.deleteOne:byUserIdPostId(user.id, post_id)(function (result)
                if not result or iserror(result) then
                    resolve(result)
                else
                    updateCounts()(function (result)
                        resolve({incr = -1})
                    end)
                end
            end)
        end
    end)

    return resolver
end

--- Remove forum post, if thread becomes empty, remove thread as well
---@param postId integer post ID
---@return fun(on_resolved: fun(...: any)|thread)
function web:removePost(postId)
    local resolve, resolver = aio:prepare_promise()
    self:getPostById(postId)(function (post)
        if not post then
            resolve({ok = true})
        elseif iserror(post) then
            resolve(post)
        else
            local thread = post.thread
            db.posts.deleteOne:byId(postId)(function (result)
                if not result or iserror(result) then
                    resolve(result)
                    return
                end
                db.posts.count:byThread(thread)(function (posts)
                    if not posts then
                        resolve(result)
                        return
                    elseif posts == 0 then
                        -- if there are 0 posts left, delete thread as well
                        db.threads.deleteOne:byId(thread)(function (thr_result)
                            resolve(thr_result)
                        end)
                        return
                    end
                    -- ignore any errors happening here
                    db.posts.one:byThread(thread, {orderBy = "id DESC"})(function (lastPost)
                        if not lastPost or iserror(lastPost) then
                            resolve(result)
                            return
                        end
                        db.threads:update({id = thread}, {lastPostId=lastPost.id, lastPostTime=lastPost.createdAt})(function (result)
                            resolve(result)
                        end)
                    end)
                end)
            end)
        end
    end)
    return resolver
end

--- Get forum post by ID
---@param postId integer
---@return aiopromise<{id: integer}> promise
function web:getPostById(postId)
    return db.posts.one:byId(postId)
end

--- Encode forum post into HTML
---@param text string original text
---@return string text encoded as HTML
function web:encodePostText(text)
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

function web:getTop10(ip, port)
    local resolve, resolver = aio:prepare_promise()
    db.statistics.all:byTop10(ip, port)(function (result)
        if iserror(result) then
            resolve(result)
        elseif not result then
            resolve(nil)
        else
            local profileIds = {}
            local records = {}
            for _, stat in ipairs(result) do
                if stat.playerId < 800000 and stat.playerId >= 1 then
                    table.insert(profileIds, stat.playerId)
                    records[stat.playerId] = stat
                end
            end
            if #profileIds == 0 then
                resolve(result)
            else
                db.users.all:byIdIn(profileIds)(function (users)
                    if not users or iserror(users) then
                        resolve(result)
                    else
                        for _, user in ipairs(users) do
                            records[user.id].display = user.display
                            records[user.id].rights = user.rights
                        end
                    end
                    resolve(result)
                end)
            end
        end
    end)
    return resolver
end

return web