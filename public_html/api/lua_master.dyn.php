function dataret() return <?lu
    header("content-type", "text/lua; charset=utf-8")
    local servers = await(crymp:getServers())
    write(codec.lua_encode(aio:map(servers, crymp.api.toPublic)))
?> end