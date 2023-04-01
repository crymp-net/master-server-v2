<?lu
    local params = query
    local handle = params.a or params.mail or params.nick
    local pass = params.b or params.pass or params.password

    -- try to parse it from the body
    if not handle and not pass and body ~= nil and #body > 0 then
        if body:sub(1, 1) == "{" then
            params = codec.json_decode(body) 
        else
            params = aio:parse_query(body)
        end

        handle = params.a or params.mail or params.nick
        pass = params.b or params.pass or params.password
    end

    local function encode(locals, result)
        if locals.encode then
            header("Conten-type", "application/json; charset=utf-8")
            return locals.encode(result)
        end
        if not result then return "FAIL" end
        return result.id .. "," .. result.token .. "," .. result.name
    end

    if handle ~= nil and pass ~= nil then
        local result = await(crymp.api:login(handle, pass))
        if result ~= nil then
            write(encode(locals, result))
        else
            write(encode(locals, {error = "fail"}))
        end
    else
        write(encode(locals, {error = "fail"}))
    end
?>