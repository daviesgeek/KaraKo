-- KaraKo multi-source UI. Every configured source goes through syncprofiles.lua.
local _ = require("gettext")
local T = require("ffi/util").template
local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local Device = require("device")
local Menu = require("ui/widget/menu")
local SpinWidget = require("ui/widget/spinwidget")
local InfoMessage = require("ui/widget/infomessage")

local M = {}

local function changed(plugin, menu)
    plugin:onFlushSettings()
    if menu then menu:updateItems() end
end

local function move(profiles, from, to)
    if to < 1 or to > #profiles then return end
    local entry = table.remove(profiles, from)
    table.insert(profiles, to, entry)
end

local function edit(plugin, profile, index)
    local function current_index()
        for n, candidate in ipairs(plugin.sync_profiles) do
            if candidate == profile then return n end
        end
        return nil
    end
    return {
        {
            text_func = function()
                return profile.enabled ~= false and _("Enabled: Yes") or _("Enabled: No")
            end,
            callback = function(menu)
                profile.enabled = profile.enabled == false
                changed(plugin, menu)
            end,
        },
        {
            text_func = function()
                return T(_("Sort order: %1"), profile.order == "published_desc"
                    and _("Newest published") or _("Newest added"))
            end,
            callback = function(menu)
                profile.order = profile.order == "published_desc" and "created_desc" or "published_desc"
                changed(plugin, menu)
            end,
        },
        {
            text_func = function()
                return T(_("Maximum articles: %1"), profile.max_articles or 30)
            end,
            callback = function(menu)
                UIManager:show(SpinWidget:new{
                    title_text = _("Maximum articles from this source"),
                    info_text = _("Maximum active articles selected, not downloads per sync."),
                    value = profile.max_articles or 30,
                    value_min = 1, value_max = 200, value_step = 1, value_hold_step = 10,
                    callback = function(spin)
                        profile.max_articles = spin.value
                        changed(plugin, menu)
                    end,
                })
            end,
        },
        {
            text = _("Move higher priority"),
            enabled_func = function() return (current_index() or 1) > 1 end,
            callback = function(menu)
                local i = current_index()
                if i then move(plugin.sync_profiles, i, i - 1); changed(plugin, menu) end
            end,
        },
        {
            text = _("Move lower priority"),
            enabled_func = function() return (current_index() or #plugin.sync_profiles) < #plugin.sync_profiles end,
            callback = function(menu)
                local i = current_index()
                if i then move(plugin.sync_profiles, i, i + 1); changed(plugin, menu) end
            end,
        },
        {
            text = _("Remove source"),
            callback = function(menu)
                local i = current_index()
                if i then table.remove(plugin.sync_profiles, i); changed(plugin, menu) end
            end,
        },
    }
end

local function choose_new_list(plugin)
    if plugin.server_url == "" or plugin.api_token == "" then
        UIManager:show(InfoMessage:new{ text = _("Configure your Karakeep server first.") })
        return
    end
    NetworkMgr:runWhenOnline(function()
        local ok, lists = plugin:getApi():getLists()
        if not ok or type(lists) ~= "table" then
            UIManager:show(InfoMessage:new{ text = _("Cannot load Karakeep lists.") })
            return
        end
        local entries = {}
        local known = {}
        for _, p in ipairs(plugin.sync_profiles) do known[tostring(p.list_id)] = true end
        for _, item in ipairs(lists) do
            local id = item.id and tostring(item.id)
            if id and not known[id] then
                local name = item.name or id
                entries[#entries + 1] = {
                    text = name,
                    callback = function()
                        plugin.sync_profiles[#plugin.sync_profiles + 1] = {
                            list_id = id, name = name, enabled = true,
                            order = "published_desc", max_articles = 30,
                        }
                        plugin:onFlushSettings()
                        UIManager:show(InfoMessage:new{ text = T(_("Added source: %1"), name) })
                    end,
                }
            end
        end
        if #entries == 0 then
            UIManager:show(InfoMessage:new{ text = _("No additional lists available.") })
            return
        end
        table.sort(entries, function(a, b) return a.text < b.text end)
        local chooser
        chooser = Menu:new{
            title = _("Add Karakeep list"), item_table = entries,
            width = Device.screen:getWidth(), height = Device.screen:getHeight(),
            close_callback = function() UIManager:close(chooser) end,
        }
        UIManager:show(chooser)
    end)
end

function M.build(plugin)
    local entries = {
        {
            text = _("Add list…"),
            callback = function() choose_new_list(plugin) end,
        },
    }
    for index, profile in ipairs(plugin.sync_profiles or {}) do
        local p, i = profile, index
        entries[#entries + 1] = {
            text_func = function()
                return T(_("%1. %2 (%3, max %4)%5"), i, p.name or p.list_id,
                    p.order == "published_desc" and _("published") or _("added"),
                    p.max_articles or 30, p.enabled == false and _(" [disabled]") or "")
            end,
            sub_item_table_func = function() return edit(plugin, p, i) end,
            keep_menu_open = true,
        }
    end
    return entries
end
return M
