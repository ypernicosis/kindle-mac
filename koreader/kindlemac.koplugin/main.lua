--[[--
Kindle ↔ Mac: buttons that talk to `kindle servir` on the Mac.

  - Exportar trechos para o Ateliet: highlights and notes go to the book notes in the vault
  - Receber livros do Mac: books in ~/Kindle/Enviar come to documents/Livros
  - Transmitir a tela para o OBS: the screen streams to the Mac (tela.sh, in the background)
  - Abrir o Jobman: Jobman takes the screen; leaving it comes back here

The Mac's address and token are in settings/kindlemac.lua.

@module koplugin.kindlemac
--]]

local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")

local BOOK_DIR = "/mnt/us/documents/Livros"
local META_LIST = "/tmp/kindlemac-meta.txt"
local TELA_PID = "/tmp/kindlemac-tela.pid"
local TELA_STOP = "/tmp/kindlemac-tela.stop"
local TELA_NC = "/tmp/kindlemac-tela.nc"

local function q(s)
    return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

local function hex(s)
    return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
end

local function unhex(h)
    return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end))
end

-- os.execute returns 0 (Lua 5.1) or true (5.2 compat) on success
local function ok(cmd)
    local r = os.execute(cmd)
    return r == 0 or r == true
end

local function run(cmd)
    local f = io.popen(cmd .. " 2>/dev/null")
    if not f then return "" end
    local out = f:read("*a") or ""
    f:close()
    return out
end

local KindleMac = WidgetContainer:extend{
    name = "kindlemac",
    is_doc_only = false,
}

function KindleMac:init()
    self.plugin_dir = self.path
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/kindlemac.lua")
    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
end

function KindleMac:onDispatcherRegisterActions()
    Dispatcher:registerAction("kindlemac_trechos", { category = "none", event = "KindleMacTrechos", title = "Exportar trechos para o Ateliet", general = true })
    Dispatcher:registerAction("kindlemac_receber", { category = "none", event = "KindleMacReceber", title = "Receber livros do Mac", general = true })
    Dispatcher:registerAction("kindlemac_tela", { category = "none", event = "KindleMacTela", title = "Transmitir a tela para o OBS", general = true })
    Dispatcher:registerAction("kindlemac_jobman", { category = "none", event = "KindleMacJobman", title = "Abrir o Jobman", general = true, separator = true })
end

-- HTTP to the Mac, through curl: returns body, status (0 when unreachable).
function KindleMac:http(method, path, extra, timeout)
    local host = self.settings:readSetting("host")
    local port = self.settings:readSetting("porta") or 8766
    local token = self.settings:readSetting("token") or ""
    if not host then return "Endereço do Mac não configurado.", 0 end
    local cmd = string.format("curl -s -m %d -X %s -H %s -w '\\n%%{http_code}' %s %s",
        timeout or 20, method, q("X-Token: " .. token), extra or "", q("http://" .. host .. ":" .. port .. path))
    local out = run(cmd)
    local body, code = out:match("^(.*)\n(%d+)$")
    return body or out, tonumber(code) or 0
end

function KindleMac:notify(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout })
end

-- Shows "text" while fn runs (fn blocks the UI), then fn's result.
function KindleMac:busy(text, fn)
    NetworkMgr:runWhenOnline(function()
        local msg = InfoMessage:new{ text = text }
        UIManager:show(msg)
        UIManager:forceRePaint()
        local ok, result = pcall(fn)
        UIManager:close(msg)
        if not ok then
            logger.warn("kindlemac:", result)
            result = "Erro: " .. tostring(result)
        end
        if result then self:notify(result) end
    end)
end

function KindleMac:unreachable(code, body)
    if code == 0 then
        return "O Mac não respondeu.\n\nO `kindle servir` está rodando no Mac?\nEndereço: " .. tostring(self.settings:readSetting("host"))
    elseif code == 403 then
        return "O Mac recusou o token. Confira settings/kindlemac.lua."
    end
    return "O Mac respondeu " .. code .. ":\n" .. (body or "")
end

-- Exportar trechos ----------------------------------------------------------

function KindleMac:onKindleMacTrechos()
    -- the open book's latest highlights, written to its metadata first
    if self.ui.document and self.ui.saveSettings then
        self.ui:saveSettings()
    end
    self:busy("Exportando trechos para o Ateliet…", function()
        os.execute("find /mnt/us -path /mnt/us/koreader/data -prune -o -path '*.sdr/metadata.*.lua' -print 2>/dev/null"
            .. " | while IFS= read -r f; do printf '\\n@@KINDLE-FILE@@ %s\\n' \"$f\"; cat \"$f\"; done > " .. META_LIST)
        local body, code = self:http("POST", "/trechos/precisa", "--data-binary @" .. META_LIST, 30)
        if code ~= 200 then return self:unreachable(code, body) end
        for path in body:gmatch("[^\n]+") do
            local _, c = self:http("POST", "/trechos/livro",
                "-H " .. q("X-Caminho: " .. hex(path)) .. " --data-binary @" .. q(path), 120)
            if c ~= 200 then logger.warn("kindlemac: livro não enviado", path, c) end
        end
        body, code = self:http("POST", "/trechos/exportar", "", 60)
        os.remove(META_LIST)
        if code ~= 200 then return self:unreachable(code, body) end
        return body:match("^[^\n]*")
    end)
    return true
end

-- Receber livros -------------------------------------------------------------

function KindleMac:onKindleMacReceber()
    self:busy("Procurando livros no Mac…", function()
        local body, code = self:http("GET", "/fila")
        if code ~= 200 then return self:unreachable(code, body) end
        os.execute("mkdir -p " .. q(BOOK_DIR))
        local got, names = 0, {}
        for h in body:gmatch("(%x+)\t%d+\t[^\n]*") do
            local name = unhex(h)
            local dest = BOOK_DIR .. "/" .. name
            local _, c = self:http("GET", "/fila/arquivo?n=" .. h, "-o " .. q(dest .. ".part"), 300)
            if c == 200 and os.rename(dest .. ".part", dest) then
                self:http("POST", "/fila/feito?n=" .. h)
                got = got + 1
                names[#names + 1] = "• " .. name
            else
                os.remove(dest .. ".part")
            end
        end
        if got == 0 then
            return "Nenhum livro na fila.\n\nNo Mac, ponha os livros em ~/Kindle/Enviar\nou use `kindle-enviar --fila`."
        end
        local FileManager = require("apps/filemanager/filemanager")
        if FileManager.instance then FileManager.instance:onRefresh() end
        return got .. " livro(s) em Livros:\n" .. table.concat(names, "\n")
    end)
    return true
end

-- Transmitir a tela ----------------------------------------------------------

function KindleMac:streaming()
    local pid = run("cat " .. TELA_PID):match("%d+")
    return pid ~= nil and ok("kill -0 " .. pid .. " 2>/dev/null")
end

function KindleMac:onKindleMacTela()
    if self:streaming() then
        os.execute("touch " .. TELA_STOP .. "; kill $(cat " .. TELA_NC .. ") 2>/dev/null")
        self:notify("Transmissão da tela encerrada.", 2)
        return true
    end
    NetworkMgr:runWhenOnline(function()
        local body, code = self:http("GET", "/ping", "", 5)
        if code ~= 200 then
            self:notify(self:unreachable(code, body))
            return
        end
        local fps = self.settings:readSetting("fps") or 3
        os.execute(string.format("setsid sh %s %s %d %s %d > /dev/null 2>&1 < /dev/null &",
            q(self.plugin_dir .. "/tela.sh"), q(self.settings:readSetting("host")),
            self.settings:readSetting("porta_tela") or 8767, q(self.settings:readSetting("token") or ""),
            math.floor(1000000 / fps)))
        self:notify("Transmitindo a tela para o OBS.\nToque de novo para parar.", 3)
    end)
    return true
end

-- Jobman ----------------------------------------------------------------------

function KindleMac:onKindleMacJobman()
    if not ok("test -x /mnt/us/jobman/jobman") then
        self:notify("Não achei o Jobman em /mnt/us/jobman.")
        return true
    end
    UIManager:nextTick(function()
        -- Jobman draws on the screen and reads the touch itself: KOReader lets go of
        -- its input until Jobman closes (its back button, or the power button).
        Device.input:teardown()
        os.execute("sh " .. q(self.plugin_dir .. "/jobman.sh"))
        Device:openInputDevices()
        UIManager:setDirty("all", "full")
    end)
    return true
end

-- Menu ------------------------------------------------------------------------

function KindleMac:setHost()
    local dialog
    dialog = InputDialog:new{
        title = "Endereço do Mac (IP na rede)",
        input = self.settings:readSetting("host") or "",
        input_type = "string",
        buttons = {{
            { text = "Cancelar", id = "close", callback = function() UIManager:close(dialog) end },
            { text = "Salvar", is_enter_default = true, callback = function()
                local v = dialog:getInputText():gsub("%s", "")
                if v ~= "" then
                    self.settings:saveSetting("host", v)
                    self.settings:flush()
                end
                UIManager:close(dialog)
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function KindleMac:addToMainMenu(menu_items)
    menu_items.kindlemac = {
        text = "Kindle ↔ Mac",
        sorting_hint = "tools",
        sub_item_table = {
            { text = "Exportar trechos para o Ateliet", callback = function() self:onKindleMacTrechos() end },
            { text = "Receber livros do Mac", callback = function() self:onKindleMacReceber() end },
            {
                text = "Transmitir a tela para o OBS",
                checked_func = function() return self:streaming() end,
                callback = function() self:onKindleMacTela() end,
                separator = true,
            },
            { text = "Abrir o Jobman", callback = function() self:onKindleMacJobman() end, separator = true },
            {
                text_func = function() return "Endereço do Mac: " .. (self.settings:readSetting("host") or "?") end,
                keep_menu_open = true,
                callback = function() self:setHost() end,
            },
            {
                text = "Testar a conexão",
                keep_menu_open = true,
                callback = function()
                    self:busy("Chamando o Mac…", function()
                        local body, code = self:http("GET", "/ping", "", 5)
                        if code ~= 200 then return self:unreachable(code, body) end
                        return "Mac respondeu: " .. body:gsub("^ok%s*", "")
                    end)
                end,
            },
        },
    }
end

return KindleMac
