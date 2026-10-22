-- KaraKo unified multi-list selection engine. Pure Lua; no KOReader dependencies.
-- Returns selected, error, complete_for_cleanup, per_source_summary.
local M = {}
local PAGE_SIZE = 100
local MAX_PAGES_PER_SOURCE = 50

local function valid_date(s)
    if type(s) ~= "string" or not s:match("^%d%d%d%d%-%d%d%-%d%d") then return "" end
    return s
end

local function timestamp(b, order)
    local created = valid_date(b.createdAt)
    if order == "published_desc" then
        local published = valid_date((b.content or {}).datePublished)
        if published ~= "" then return published end
    end
    return created
end

local function by_date(order)
    return function(a, b)
        local da, db = timestamp(a, order), timestamp(b, order)
        if da ~= db then return da > db end
        local ca, cb = valid_date(a.createdAt), valid_date(b.createdAt)
        if ca ~= cb then return ca > cb end
        return tostring(a.id) < tostring(b.id)
    end
end

local function get_source(api, profile, readable)
    local all, seen_ids, seen_cursors, cursor = {}, {}, {}, nil
    local page_count = 0
    repeat
        page_count = page_count + 1
        local ok, result = api:getBookmarkPage{
            scope = "list", scope_id = profile.list_id,
            limit = PAGE_SIZE, cursor = cursor,
        }
        if not ok or type(result) ~= "table" or type(result.bookmarks) ~= "table" then
            return nil, (not ok and result) or "invalid_response"
        end
        for _, b in ipairs(result.bookmarks) do
            local id = b and b.id and tostring(b.id)
            if id and not seen_ids[id] and not b.archived and readable(b) then
                seen_ids[id] = true
                all[#all + 1] = b
            end
        end
        cursor = result.nextCursor
        if cursor ~= nil then
            if type(cursor) ~= "string" or cursor == "" or seen_cursors[cursor] then
                return nil, "invalid_cursor"
            end
            seen_cursors[cursor] = true
            if page_count >= MAX_PAGES_PER_SOURCE then return nil, "scan_limit" end
        end
    until cursor == nil
    return all, nil, page_count
end

-- The profiles' array index IS their priority (first = highest).
-- Quotas select EXISTING active articles, not number of NEW downloads.
-- Do not delete files for quota-excluded articles: complete is false if any
-- eligible bookmark was not selected, even when every API page was scanned.
function M.select(api, profiles, max_total, readable)
    if type(profiles) ~= "table" or type(readable) ~= "function" then
        return nil, "invalid_profiles", false
    end
    max_total = math.max(1, math.min(200, math.floor(tonumber(max_total) or 30)))
    local candidates, eligible_ids, selected, selected_ids, summaries = {}, {}, {}, {}, {}
    for _, p in ipairs(profiles) do
        if p.enabled ~= false then
            if type(p.list_id) ~= "string" or p.list_id == "" then
                return nil, "invalid_profile_list", false
            end
            local order = p.order == "published_desc" and "published_desc" or "created_desc"
            local all, err, pages = get_source(api, p, readable)
            if not all then return nil, err, false end
            for _, bookmark in ipairs(all) do eligible_ids[tostring(bookmark.id)] = true end
            table.sort(all, by_date(order))
            candidates[#candidates + 1] = {
                profile = p, order = order, bookmarks = all,
                summary = { name = p.name or p.list_id, candidates = #all, selected = 0, pages = pages },
            }
        end
    end
    if #candidates == 0 then return nil, "no_enabled_sources", false end

    for _, source in ipairs(candidates) do
        local count = 0
        local quota = math.max(0, math.min(200, math.floor(tonumber(source.profile.max_articles) or 30)))
        for _, b in ipairs(source.bookmarks) do
            if count >= quota or #selected >= max_total then break end
            local id = tostring(b.id)
            if not selected_ids[id] then
                selected_ids[id] = true
                -- The selected source decides which date Bookshelf should show.
                -- This is deliberately a local-only property (not a Karakeep write).
                b._karako_order = source.order
                selected[#selected + 1] = b
                count = count + 1
            end
        end
        source.summary.selected = count
        summaries[#summaries + 1] = source.summary
    end
    local complete = true
    for id in pairs(eligible_ids) do
        if not selected_ids[id] then complete = false; break end
    end
    return selected, nil, complete, summaries
end

return M
