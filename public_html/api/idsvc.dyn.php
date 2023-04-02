<?lu
    local function encode(locals, result)
        local encoder = locals.encode
        if encoder then
            header("Content-type", encoder == codec.json_encode and "application/json; charset=utf-8" or "text/lua; charset=utf-8")
            return encoder(result)
        else
            if result.error then
                return "900000/KICKME"
            else
                return result.id .. "/" .. result.token
            end
        end
    end
    local hwid = query.hwid or headers["x-sfwcl-hwid"]
    if not hwid or not hwid:find(":") then
        status("400 Bad request")
        return write(encode(locals, {error="invalid hwid/1"}))
    end
    local locale = query.lng or query.locale or headers["x-sfwcl-locale"] or "en-US"
    local tz = tonumber(query.tz or headers["x-sfwcl-tz"]) or 0
    local clientVer = query.ver or headers["x-sfwcl-ver"] or "17"
    local id, signature = hwid:match("([0-9A-Fa-f]+):([0-9A-Fa-f]+)")
    if id and signature and #id == 64 and #signature == 64 and hash(id .. "idsvc"):lower() == signature:lower() then
        local result = await(crymp.api:getStaticID(id, locale, tz, clientVer))
        if not result then
            status("500 Internal server error")
            return write(encode(locals, {error="server error"}))
        else
            return write(encode(locals, result))
        end
    else
        status("400 Bad request")
        return write(encode(locals, {error="invalid hwid/2"}))
    end
?>