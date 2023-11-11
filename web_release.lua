aio:stream_http_post("/api/v2_release", function (fd, query_, headers, body)
    local query = aio:parse_query(query_)
    return coroutine.create(function (...)
        local response_headers = {}
        local status = "200 OK"
        local read_body = function (store)
            local chunks = {}
            local remaining = tonumber(headers["content-length"] or "0")
            while remaining > 0 do
                local data = coroutine.yield(math.min(100000, remaining))
                if not data then
                    coroutine.yield(false)
                    return nil
                end
                remaining = remaining - #data
                if store then
                    chunks[#chunks+1] = data
                end
            end
            return table.concat(chunks)
        end
        local header = function (key, value)
            response_headers[key] = value
        end
        local write = function (value, did_read)
            if value.error and did_read ~= true then
                read_body(false)
            end
            fd:http_response(status, response_headers, codec.json_encode(value))
        end
        header("content-type", "application/json")
        local now = os["time"]()
        local time = tonumber(query["time"] or 0)
        local ctx = query["context"] or "none"
        local commit_hash = query["commit"]
        if commit_hash == nil or #commit_hash < 16 then
            status = "400 Bad request"
            return write(make_error("commit hash is missing in query"))
        end
        if not (ctx == "release" or ctx == "dev") then
            status = "400 Bad reqeust"
            return write(make_error("invalid context: " .. ctx))
        end
        if not time or not query["signature"] or (now - time) > RELEASE_EXPIRY then
            status = "400 Bad request"
            return write(make_error("expired or bad request"))
        end
        local expected = codec.hex_encode(crypto.hmac_sha256(query["time"], RELEASE_SALT))
        if expected:lower() ~= query["signature"]:lower() then
            status = "401 Unauthorized"
            return write(make_error("invalid token"))
        end
        if headers["x-body-signature"] == nil then
            status = "400 Bad request"
            return write(make_error("x-body-signature missing"))
        end
        if headers["x-file-upload"] == nil then
            status = "400 Bad request"
            return write(make_error("x-file-upload missing"))
        end
        local files = codec.json_decode(headers["x-file-upload"])
        local files_ok = {}
        local found_32, found_64 = false, false
        local file_sum = 0

        if ctx == "dev" then
            commit_hash = "d-" .. commit_hash
        elseif ctx == "release" then
            commit_hash = "r-" .. commit_hash
        else
            commit_hash = "u-" .. commit_hash
        end

        if files then
            for _, file in ipairs(files) do
                if not tonumber(file.size) or not file.name then
                    files_ok = make_error("missing file fields")
                    break
                end
                if file.name == "CryMP-Client64.exe" then found_64 = true end
                if file.name == "CryMP-Client32.exe" then found_32 = true end
                file_sum = file_sum + file.size
            end
            if file_sum ~= tonumber(headers["content-length"]) then
                files_ok = make_error("file size - content-length mismatch, sum: " .. tostring(file_sum) .. ", recv: " .. tostring(headers["content-length"]))
            end
            if not found_32 or not found_64 then
                files_ok = make_error("couldn't file both CryMP-Client32.exe and CryMP-Client64.exe")
            end
        else
            files_ok = make_error("x-file-upload not found")
        end
        if iserror(files_ok) then
            status = "400 Bad request"
            return write(files_ok)
        end
        local result = read_body(true)
        if not result or codec.hex_encode(crypto.hmac_sha256(result, RELEASE_SALT)) ~= headers["x-body-signature"] then
            status = "400 Bad request"
            return write(make_error("invalid body signature"), true)
        end
        local pivot = 1
        local dest = "crymp/public_html/static/releases/" .. commit_hash
        if not net.mkdir(dest) then
            status = "500 Internal server error"
            return write(make_error("failed to create release dir"), true)
        end
        local err = nil
        for _, file in ipairs(files) do
            file.content = result:sub(pivot, pivot + file.size - 1)
            pivot = pivot + file.size
            if file.name == "CryMP-Client32.exe" or file.name == "CryMP-Client64.exe" then
                local f, _ = io.open(dest .. "/" .. file.name, "wb")
                if not f then
                    status = "500 Internal server error"
                    return write(make_error("failed to open " .. file.name .. "for writing"), true)
                end
                f, err = f:write(file.content)
                if not f then
                    status = "500 Internal server error"
                    return write(make_error("failed to write " .. file.name .. ", reason: " .. tostring(err)), true)
                end
                f:close()
            end
        end
        crymp.api:updateReleaseByCommit(ctx, commit_hash, dest)(function (success)
            write(success, true)
        end)
    end)
end)