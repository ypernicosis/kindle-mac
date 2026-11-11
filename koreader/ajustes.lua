-- Reading tweaks for KOReader. Run with KOReader closed, from /mnt/us/koreader:
--   ./luajit ajustes.lua
package.path = "frontend/?.lua;" .. package.path
local dump = require("dump")

local function load(path)
    local ok, t = pcall(dofile, path)
    return ok and t or {}
end

local function save(path, t)
    local f = assert(io.open(path .. ".tmp", "w"))
    f:write("-- " .. path .. "\nreturn " .. dump(t) .. "\n")
    f:close()
    os.rename(path .. ".tmp", path)
end

local function list_ifos(dir)
    local out = {}
    local p = io.popen('find "' .. dir .. '" -name "*.ifo"')
    for l in p:lines() do out[#out + 1] = l end
    p:close()
    return out
end

-- settings.reader.lua
local path = "settings.reader.lua"
local s = load(path)

s.cre_font = "Literata"                 -- default font for new books
s.copt_line_spacing = 110               -- a little more air between lines
s.copt_h_page_margins = { 15, 15 }
s.copt_t_page_margin = 15
s.copt_b_page_margin = 15
s.copt_font_kerning = 3                 -- best kerning (HarfBuzz)
s.text_lang_default = "pt-BR"           -- hyphenation for books without a language

s.screensaver_type = "cover"            -- current book's cover when sleeping
s.screensaver_show_message = false
s.screensaver_img_background = "white"

s.auto_suspend_timeout_seconds = 1800   -- sleep after 30 min idle (was never)

s.home_dir = "/mnt/us/documents"
s.lastdir = "/mnt/us/documents"

s.vocabulary_builder = s.vocabulary_builder or {}
s.vocabulary_builder.enabled = true     -- looked-up words go to the vocabulary builder

s.footer = s.footer or {}
s.footer.book_chapter = true            -- chapter title in the status bar

-- Dictionaries: Portuguese first, then English, then the rest by name.
local first = {
    "wikt-pt-pt", "wikt-en-pt", "freedict-eng-por", "wiktionary-English-English",
    "wiktionary-Portuguese-English", "freedict-por-eng",
}
local rank = {}
for i, n in ipairs(first) do rank[n] = i end
local ifos = list_ifos("/mnt/us/koreader/data/dict")
table.sort(ifos, function(a, b)
    local ra = rank[a:match("/dict/([^/]+)/")] or 100
    local rb = rank[b:match("/dict/([^/]+)/")] or 100
    if ra ~= rb then return ra < rb end
    return a < b
end)
s.dicts_order = {}
for i, f in ipairs(ifos) do s.dicts_order[f] = i end

save(path, s)

-- settings/gestures.lua: tap the bottom right corner to toggle night mode
local gpath = "settings/gestures.lua"
local g = load(gpath)
if g.gesture_reader then
    local cur = g.gesture_reader.tap_right_bottom_corner
    if not cur or next(cur) == nil then
        g.gesture_reader.tap_right_bottom_corner = { night_mode = true }
        save(gpath, g)
    end
end

print("ok: " .. #ifos .. " dicionarios ordenados")
