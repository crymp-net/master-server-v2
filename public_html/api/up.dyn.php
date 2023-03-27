<?lu
    local ip, rPort = aio:get_ip(fd, headers)
    local update = crymp.api:toServerUpdate(query, ip, query.port)
    if update then
        local cookie = await(crymp.api:upsertServer(update))
        if not cookie then
            status("400 Bad request")
            | FAIL
        else
            | <<Cookie>>#[[cookie]]<<
        end
    else
        status("400 Bad request")
        | FAIL
    end
?>