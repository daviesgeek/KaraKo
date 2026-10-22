-- Isolate the API wrapper from KOReader/LuaSocket dependencies. The method
-- being tested only delegates to :call(), so network I/O is mocked explicitly.
local Runner = require("spec.runner")
local describe, it = Runner.describe, Runner.it
local assertEqual, assertTrue = Runner.assertEqual, Runner.assertTrue

local dependencies = { "json", "socket.http", "logger", "ltn12", "socket", "socketutil" }
local previous = {}
for _, name in ipairs(dependencies) do
    previous[name] = package.loaded[name]
    package.loaded[name] = {}
end
local KarakeepApi = require("api")
package.loaded["api"] = nil
for _, name in ipairs(dependencies) do
    package.loaded[name] = previous[name]
end

describe("KarakeepApi:createBookmark", function()
    it("posts a link bookmark via the existing authorized REST client", function()
        local called = 0
        local api = setmetatable({
            call = function(_, method, path, options)
                called = called + 1
                assertEqual(method, "POST")
                assertEqual(path, "/bookmarks")
                assertEqual(options.body.type, "link")
                assertEqual(options.body.url, "https://example.com/article?x=1&y=2")
                return true, { id = "bookmark-id" }
            end,
        }, { __index = KarakeepApi })

        local ok, result = api:createBookmark("https://example.com/article?x=1&y=2")
        assertTrue(ok)
        assertEqual(result.id, "bookmark-id")
        assertEqual(called, 1)
    end)

    it("passes API failures back to the caller", function()
        local api = setmetatable({
            call = function()
                return false, "http_error", 403
            end,
        }, { __index = KarakeepApi })
        local ok, reason, status = api:createBookmark("https://example.com")
        assertEqual(ok, false)
        assertEqual(reason, "http_error")
        assertEqual(status, 403)
    end)
end)
