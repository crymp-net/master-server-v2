<?lu
    local ip, rPort = aio:get_ip(fd, headers)
    if not query.port then query = aio:parse_query(body) end
    local update = crymp.api:toServerUpdate(query, ip, query.port)
    if update then
        local cookie = await(crymp.api:upsertServer(update))
        if not cookie then
            status("400 Bad request")
            | FAIL
        else
            if endpoint:find("reg.php", 1, false) then
                | <<Cookie>>#[[cookie]]<<
            else
                | OK
            end
        end
    else
        status("400 Bad request")
        | FAIL
    end
?>