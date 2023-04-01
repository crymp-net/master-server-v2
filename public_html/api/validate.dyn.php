<?lu
    local params = query
    if body ~= nil and #body > 0 then
        params = aio:parse_query(body)
    end

    local function encode(locals, result)
        if locals.encode then
            header("Content-type", "applicaton/json; charset=utf-8")
            return locals.encode(result)
        else
            return result.ok and "%Validation:Successful%" or "%Validation:Failed%"
        end
    end

    if params.prof and params.uid then
        local validated = crymp.api:validateToken(params.prof, params.uid)
        if not validated then
            write(encode(locals, {error = "fail"}))
        else
            write(encode(locals, {ok = true}))
        end
    else
        write(encode(locals, {error = "fail"}))
    end
?>