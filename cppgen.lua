local db = require("crymp.db")

text = ""
for i, v in pairs(db) do
    if v.entity then
        text = text .. "    struct " .. i .. " : public orm::with_orm {\n"
        local props = ""
        for j, w in pairs(v.entity) do
            local t = w.type.name()
            if t == "text" then t = "std::string" end
            if t == "decimal" then t = "double" end
            if t == "datetime" then t = "orm::datetime" end
            local vch = t:match("varchar%((%d+)%)")
            if vch then
                t = "util::varstr<" .. vch .. ">"
            end
            text = text .. "        " .. t .. " " .. j .. ";\n"
            props = props .. "                { \"" .. (w.field or j) .. "\", " .. j .. " },\n"
        end
        text = text .. "\n        orm::mapper get_orm() {\n            return {\n" .. props .. "            };\n        }\n"
        text = text .. "    };\n\n"
    end
end

local f, err = io.open("db.cpp", "w")
if f then
    f:write("#include <90s/orm/orm.hpp>\n\nnamespace db {\n   using namespace s90;\n")
    f:write(text)
    f:write("}\n")
    f:close()
end

aio:quit()