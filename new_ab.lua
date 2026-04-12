script_name("���������")
script_author("Haribo")
script_version("5.0")

local se = require "samp.events"
local imgui = require "mimgui"
local encoding = require "encoding"
local ffi = require "ffi"
local acef = require "arizona-events"
local fa = require "fAwesome5"
local fa_glyph_ranges = imgui.new.ImWchar[3](fa.min_range, fa.max_range, 0)

encoding.default = "CP1251"
local u8 = encoding.UTF8

DIR = getWorkingDirectory() .. "\\config\\prices"
PATH = DIR .. "\\prices.ab"
AB_AREA = {
	-2154.29, -744.62, -- [A]
	-2113.49, -975.06  -- [B]
}

LOGS_PATH = DIR .. "\\logs.json"
my_logs = {}
if doesFileExist(LOGS_PATH) then
	local file = io.open(LOGS_PATH, "r")
	if file then
		local status, res = pcall(decodeJson, file:read("*a"))
		my_logs = (status and type(res) == "table") and res or {}
		file:close()
	end
end
function save_logs()
	if not doesDirectoryExist(DIR) then createDirectory(DIR) end
	local file = io.open(LOGS_PATH, "w")
	if file then
		file:write(encodeJson(my_logs))
		file:close()
	end
end

PLATES = {}
MARKERS = {}
V = {}
local sorted_models_cache = {}
local function RebuildSortedCache()
	sorted_models_cache = {}
	for model, _ in pairs(V) do
		table.insert(sorted_models_cache, model)
	end
	table.sort(sorted_models_cache)
end

parsing = {
	active = false,
	last_body = nil,
	timer = 0
}

pending_buy = {
	active = false,
	model = "���������",
	price = 0,
	time = 0
}

pending_sell = {
	active = false,
	model = "���������",
	price = 0,
	time = 0
}

auto_update = {
	ui_scale = 100,
	last_update = 0,
	website = "", -- URL ������ ����� ��� ��������� ���
	attempting = false,
	sound_enabled = true,
	accent_color = {0.31, 0.67, 1.0},
	rounding = 18.0
}

if doesFileExist(PATH) then
	local file = io.open(PATH, "r")
	local status, res = pcall(decodeJson, file:read("*a"))
	V = (status and type(res) == "table") and res or {}
	file:close()

	if type(V) ~= "table" then
		V = {}
	end
end
RebuildSortedCache()

-- �������� ������� ��������������
local UPDATE_CONFIG_PATH = DIR .. "\\autoupdate.cfg"
if doesFileExist(UPDATE_CONFIG_PATH) then
	local file = io.open(UPDATE_CONFIG_PATH, "r")
	local status, config = pcall(decodeJson, file:read("*a"))
	file:close()
	
	if status and type(config) == "table" then
		if config.ui_scale ~= nil then auto_update.ui_scale = config.ui_scale end
		if config.website ~= nil then auto_update.website = config.website end
		if config.sound_enabled ~= nil then auto_update.sound_enabled = config.sound_enabled end
		if config.accent_color ~= nil then auto_update.accent_color = config.accent_color end
		if config.rounding ~= nil then auto_update.rounding = config.rounding end
	end
end

local renderWindow = imgui.new.bool(false)
local need_reload = false
local uiShowLogs = imgui.new.bool(false)
local uiShowUpdates = imgui.new.bool(false)
local logAddAction = imgui.new.int(0)
local logAddModel = imgui.new.char[256]("")
local logAddPrice = imgui.new.char[256]("")
local searchBuffer = imgui.new.char[256]("")
local editingLogIndex = imgui.new.int(-1)
local editLogModel = imgui.new.char[256]("")
local editLogPrice = imgui.new.char[256]("")
local uiAlpha = 0.0
local uiSoundEnabled = imgui.new.bool(auto_update.sound_enabled)
local uiAccentColor = imgui.new.float[3](auto_update.accent_color[1], auto_update.accent_color[2], auto_update.accent_color[3])
local uiRounding = imgui.new.float(auto_update.rounding)

local scaleValues = { 75, 100, 125, 150 }
local scaleOptions = { "75%", "100%", "125%", "150%" }
local function getScaleIndex(val)
	for i, v in ipairs(scaleValues) do if v == val then return i - 1 end end
	return 1 -- �� ��������� 100%
end
local uiScaleIndex = imgui.new.int(getScaleIndex(auto_update.ui_scale or 100))
local prevScale = scaleValues[uiScaleIndex[0] + 1]

local SCRIPT_UPDATE_URL = "https://raw.githubusercontent.com/Likyor/AutoBazar/refs/heads/main/new_ab.lua" -- ������ �� ���������� new_ab.lua
local UPDATE_JSON_URL = "https://raw.githubusercontent.com/Likyor/AutoBazar/refs/heads/main/update.json" -- ������ �� ���� ������ ������ �� JSON

local isUpdating = false
local function checkAndDownloadUpdate()
	if isUpdating then return end
	isUpdating = true
	lua_thread.create(function()
		wait(0)
		showCefNotification("�������� ����������...", false)
		local response = fetchUrl(UPDATE_JSON_URL)
		if response and response ~= "" then
			local status, data = pcall(decodeJson, response)
			if status and type(data) == "table" and data.version then
				local current_ver = tonumber(thisScript().version) or 5.0
				local new_ver = tonumber(data.version)
				if new_ver and new_ver > current_ver then
					showCefNotification(string.format("������� ����� ������: <b>%s</b>. ��������...", data.version), false)
					local script_code = fetchUrl(SCRIPT_UPDATE_URL)
					if script_code and script_code ~= "" then
						local file = io.open(thisScript().path, "w")
						if file then
							file:write(script_code)
							file:close()
							showCefNotification("���������� ���������! ����������...", false)
							wait(1500)
							thisScript():reload()
						else
							showCefNotification("������ ��� ���������� ����� ����������.", true)
						end
					else
						showCefNotification("������ ��� ���������� ����� ����������.", true)
					end
				else
					showCefNotification("� ��� ����������� ���������� ������ �������.", false)
				end
			else
				showCefNotification("������ ��� ��������� ������ ����������.", true)
			end
		else
			showCefNotification("������ ���������� ��� �������� ����������.", true)
		end
		isUpdating = false
	end)
end

function VCount()
	local i = 0
	for _, _ in pairs(V) do
		i = i + 1
	end
	return i
end

function save_prices()
	if not doesDirectoryExist(DIR) then
		createDirectory(DIR)
	end

	local file = io.open(PATH, "w")
	file:write(encodeJson(V))
	file:close()
end

function save_autoupdate_config()
	if not doesDirectoryExist(DIR) then
		createDirectory(DIR)
	end
	
	local config = {
		ui_scale = auto_update.ui_scale,
		website = auto_update.website,
		sound_enabled = auto_update.sound_enabled,
		accent_color = auto_update.accent_color,
		rounding = auto_update.rounding
	}
	
	local file = io.open(DIR .. "\\autoupdate.cfg", "w")
	file:write(encodeJson(config))
	file:close()
end

do -- Custom string's methods
	local mt = getmetatable("")
	local lower = string.lower
	function mt.__index:lower() -- Patch string.lower() for working with Cyrillic
		for i = 192, 223 do
			self = self:gsub(string.char(i), string.char(i + 32))
		end
		self = self:gsub(string.char(168), string.char(184))
		return lower(self)
	end
	function mt.__index:split(sep, plain) -- Splits a string by separator
		result, pos = {}, 1
		repeat
			local s, f = self:find(sep or " ", pos, plain)
			result[#result + 1] = self:sub(pos, s and s - 1)
			pos = f and f + 1
		until pos == nil
		return result
	end
end

function chatMessage(message, ...)
	message = ("[���������] {EEEEEE}" .. message):format(...)
	return sampAddChatMessage(message, 0xFF6640)
end

function convertToPriceFormat(num)
	num = tostring(num)
	local b, e = ("%d"):format(num):gsub("^%-", "")
	local c = b:reverse():gsub("%d%d%d", "%1.")
	local d = c:reverse():gsub("^%.", "")
	return (e == 1 and "-" or "") .. d
end

function formatAbbreviated(num)
    if not num or type(num) ~= 'number' then return "N/A" end
    if num < 1000 then return tostring(num) end

    local formattedNum
    local suffix = ""
    if num >= 1000000 then
        formattedNum = num / 1000000
        suffix = "��"
    elseif num >= 1000 then
        formattedNum = num / 1000
        suffix = "�"
    end

    if formattedNum == math.floor(formattedNum) then
        return string.format("%d%s", formattedNum, suffix)
    else
        local s = string.format("%.2f", formattedNum)
        s = s:gsub("0*$", "") -- remove trailing zeros
        s = s:gsub("%.$", "")  -- remove trailing dot
        return s .. suffix
    end
end

function parseAbbreviatedPrice(str)
	if not str then return nil end
	local s = str:gsub("{%x+}", ""):gsub("<[^>]+>", ""):gsub("[%s%$]", "")
	s = s:gsub("\160", ""):gsub("\194\160", "")
	local prefix, numStr, suffix = s:match("^(%D*)([%d%.,]+)(%D*)$")
	if numStr then
		local cleanNumStr = numStr:gsub(",", ".")
		local num = tonumber(cleanNumStr)
		if num then
			local letters = (prefix .. suffix):lower()
			local cleanLetters = ""
			for i = 1, #letters do
				local b = letters:byte(i)
				if (b >= 97 and b <= 122) or b > 127 then
					cleanLetters = cleanLetters .. string.char(b)
				end
			end
			if cleanLetters == "kkk" or cleanLetters == "���" or cleanLetters == "����" or cleanLetters == "mlrd" or cleanLetters == "b" or cleanLetters == "�" then
				return math.floor(num * 1000000000)
			elseif cleanLetters == "kk" or cleanLetters == "��" or cleanLetters == "���" or cleanLetters == "mln" or cleanLetters == "m" or cleanLetters == "�" then
				return math.floor(num * 1000000)
			elseif cleanLetters == "k" or cleanLetters == "�" or cleanLetters == "���" or cleanLetters == "tys" or cleanLetters == "t" or cleanLetters == "�" then
				return math.floor(num * 1000)
			end
		end
	end
	local digits = str:gsub("%D", "")
	if digits ~= "" then
		return tonumber(digits)
	end
	return nil
end

function reformatPrices(text)
	local chars = "kK��mM��lL��nN��tT��yY��sS��bB��rR��dD��"
	local pattern_vc_1 = "([" .. chars .. "]+%s+%d+%s+[" .. chars .. "]+%s+[%d%.,]+)"
	local pattern_vc_2 = "([" .. chars .. "]+%s+[%d%.,]+)"
	local pattern_normal = "([%d%.,]+%s*[" .. chars .. "%.]*)"

	local function formatWithDollar(num)
		local p = parseAbbreviatedPrice(num)
		return p and ("$" .. convertToPriceFormat(p)) or ("$" .. num)
	end
	
	local function formatWithDollarEnd(num)
		local p = parseAbbreviatedPrice(num)
		return p and ("$" .. convertToPriceFormat(p)) or (num .. "$")
	end

	text = text:gsub("%$%s*" .. pattern_vc_1, formatWithDollar)
	text = text:gsub("%$%s*" .. pattern_vc_2, formatWithDollar)
	text = text:gsub("%$%s*" .. pattern_normal, formatWithDollar)
	
	text = text:gsub(pattern_vc_1 .. "%s*%$", formatWithDollarEnd)
	text = text:gsub(pattern_vc_2 .. "%s*%$", formatWithDollarEnd)
	text = text:gsub(pattern_normal .. "%s*%$", formatWithDollarEnd)
	
	local function formatBare(prefix, num, suffix)
		local p = parseAbbreviatedPrice(num)
		if p then
			local hasLetters = num:match("[" .. chars .. "]")
			if hasLetters or p >= 1000 then
				return prefix .. "$" .. convertToPriceFormat(p) .. suffix
			end
		end
		return prefix .. num .. suffix
	end
	
	text = text:gsub("(\t%s*)" .. pattern_normal .. "(%s*\n)", formatBare)
	text = text:gsub("(\t%s*)" .. pattern_normal .. "(%s*)$", formatBare)
	text = text:gsub("(\n%s*)" .. pattern_normal .. "(%s*\n)", formatBare)
	text = text:gsub("(\n%s*)" .. pattern_normal .. "(%s*)$", formatBare)
	
	return text
end

local cefNotifyCounter = 0
function showCefNotification(text, isAuction)
    cefNotifyCounter = cefNotifyCounter + 1
    local currentId = cefNotifyCounter

    lua_thread.create(function()
        wait(0)
		
		-- ��������� ����� � ������� ���
		local chatText = text:gsub("<b>", "{FFD700}"):gsub("</b>", "{EEEEEE}"):gsub("<br>", " | "):gsub("<[^>]+>", "")
		sampAddChatMessage("[���������] {EEEEEE}" .. chatText, 0x2ECC71)

        if cefNotifyCounter ~= currentId then return end

		local function emulCef(str)
			local bs = raknetNewBitStream()
			raknetBitStreamWriteInt8(bs, 17)
			raknetBitStreamWriteInt32(bs, 0)
			raknetBitStreamWriteInt16(bs, #str)
			raknetBitStreamWriteInt8(bs, 0)
			raknetBitStreamWriteString(bs, str)
			raknetEmulPacketReceiveBitStream(220, bs)
			raknetDeleteBitStream(bs)
		end

        local closeJs = "window.executeEvent('cef.modals.closeModal', '[\"dialogTip\"]');"
        emulCef(closeJs)

        wait(50)
        if cefNotifyCounter ~= currentId then return end

        local iconColor = isAuction and "#FFD700" or "#2ECC71"
        local highlightColor = isAuction and "#FFA500" or "#5FC6FF"
        
        local safeText = text:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '<br>')
        local js = string.format("window.executeEvent('cef.modals.showModal', '[\"dialogTip\",{\"position\":\"rightBottom\",\"backgroundImage\":\"bank_notify_add.webp\",\"icon\":\"icon-info\",\"iconColor\":\"%s\",\"highlightColor\":\"%s\",\"text\":\"%s\"}]');", iconColor, highlightColor, safeText)

        emulCef(js)

        if auto_update.sound_enabled then
            addOneOffSound(0.0, 0.0, 0.0, 1058)
        end

        wait(isAuction and 8000 or 4500)
        if cefNotifyCounter == currentId then
			emulCef(closeJs)
        end
    end)
end

local dlstatus = require("moonloader").download_status
function fetchUrl(url)
	local temp_file = DIR .. "\\temp_" .. tostring(os.clock()):gsub('%.', '') .. tostring(math.random(1000, 9999)) .. ".txt"
	local result = nil
	local is_done = false
	
	downloadUrlToFile(url, temp_file, function(id, status, p1, p2)
		if status == dlstatus.STATUS_ENDDOWNLOADDATA then
			local f = io.open(temp_file, "r")
			if f then
				result = f:read("*a")
				f:close()
			end
			os.remove(temp_file)
			is_done = true
		elseif status == dlstatus.STATUSEX_ERROR then
			os.remove(temp_file)
			is_done = true
		end
	end)
	
	local timer = os.clock()
	while not is_done do
		wait(10)
		if os.clock() - timer > 15.0 then -- 15 ������ �������
			os.remove(temp_file)
			break
		end
	end
	
	return result
end

function updatePricesFromWebsite()
	if auto_update.attempting then
		return
	end
	
	auto_update.attempting = true
	
	lua_thread.create(function()
		wait(0)
		chatMessage("�������� ��� � ������ �����...")
		local response = fetchUrl(auto_update.website)
		if response and response ~= "" then
			local oldCount = VCount()
			parsePage(response)
			save_prices()
			local newCount = VCount()
			
			if newCount > 0 then
				chatMessage("�������������� ��� ���������. ����: {FF6640}%d{EEEEEE}, ������: {FF6640}%d", oldCount, newCount)
				auto_update.last_update = os.time()
			else
				chatMessage("���� ��������, �� �� �������� ���������� ������ � �����")
			end
		else
			chatMessage("�� ������� ��������� ���� � ������ �����. ��������� ������ � ������.")
		end
		
		auto_update.attempting = false
	end)
end

function findListInDialog(text, style, search)
	local t_text = text:split("\n")
	if style == 5 then
		table.remove(t_text, 1)
	end

	for i, line in ipairs(t_text) do
		if line:find(search, 1, true) then
			return (i - 1)
		end
	end
	return nil
end

function isViceCity()
	local ip, port = sampGetCurrentServerAddress()
	local address = ("%s:%s"):format(ip, port)
	return (address == "80.66.82.147:7777")
end

function sampSetRaceCheckpoint(type, x, y, z, radius)
	local bs = raknetNewBitStream()
	raknetBitStreamWriteInt8(bs, type)
	raknetBitStreamWriteFloat(bs, x)
	raknetBitStreamWriteFloat(bs, y)
	raknetBitStreamWriteFloat(bs, z)
	raknetBitStreamWriteFloat(bs, 0)
	raknetBitStreamWriteFloat(bs, 0)
	raknetBitStreamWriteFloat(bs, 0)
	raknetBitStreamWriteFloat(bs, radius)
	raknetEmulRpcReceiveBitStream(38, bs)
	raknetDeleteBitStream(bs)
end

function sampDisableRaceCheckpoint()
	local bs = raknetNewBitStream()
	raknetEmulRpcReceiveBitStream(39, bs)
	raknetDeleteBitStream(bs)
end

function parsePage(text)
	local changed = false
	local clean_text = text:gsub("{%x+}", "")
	for line in string.gmatch(clean_text, "[^\n]+") do
		local model, price_str = string.match(line, "^([^\t]+)\t+([^\t]+)")
		if model and price_str then
			model = model:match("^%s*(.-)%s*$")
			if model and model ~= "����� �� ��������" and model ~= "�������������� ����" and model ~= "������" and model ~= "���������" then
				local price = parseAbbreviatedPrice(price_str)
				if price ~= nil and price > 0 then
					if V[model] ~= price then
						V[model] = price
						changed = true
					end
				end
			end
		end
	end
	if changed then RebuildSortedCache() end
end

local function BeginCEFSection(id, title, subtitle, size, scale, custom_rounding)
	scale = scale or 1.0
	local r = custom_rounding or auto_update.rounding
	local acc = auto_update.accent_color
	imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(1, 1, 1, 0.03))
	imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(acc[1], acc[2], acc[3], 0.15))
	imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, r * scale)
	imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(15 * scale, 15 * scale))
	
	local ret = imgui.BeginChild(id, size, true, imgui.WindowFlags.AlwaysUseWindowPadding + imgui.WindowFlags.NoScrollbar)
	
	imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), title)
	if subtitle then
		imgui.SameLine()
		local sub_sz = imgui.CalcTextSize(subtitle)
		imgui.SetCursorPosX(imgui.GetWindowWidth() - sub_sz.x - 15 * scale)
		imgui.TextColored(imgui.ImVec4(1, 1, 1, 0.48), subtitle)
	end
	imgui.Separator()
	imgui.Dummy(imgui.ImVec2(0, 2 * scale))
	
	return ret
end

local function EndCEFSection()
	imgui.EndChild()
	imgui.PopStyleVar(2)
	imgui.PopStyleColor(2)
end

imgui.OnInitialize(function()
	local io = imgui.GetIO()
	io.Fonts:Clear()
	
	-- �������� ����� � ���������� (������ ���� ����� ��������)
	local font_path = getFolderPath(0x14) .. '\\trebucbd.ttf'
	if doesFileExist(font_path) then
		io.Fonts:AddFontFromFileTTF(font_path, 14.0, nil, io.Fonts:GetGlyphRangesCyrillic())
	else
		io.Fonts:AddFontDefault()
	end
	
	-- ��������� ����� (FontAwesome) ��� ������ 32-������ ������
	local fa_path = getWorkingDirectory() .. '\\resource\\fonts\\fa-solid-900.ttf'
	if doesFileExist(fa_path) then
		local config = imgui.ImFontConfig()
		config.MergeMode = true
		config.PixelSnapH = true
		io.Fonts:AddFontFromFileTTF(fa_path, 14.0, config, fa_glyph_ranges)
	end

	local style = imgui.GetStyle()
	local colors = style.Colors
	local clr = imgui.Col
	local ImVec4 = imgui.ImVec4

	style.ScrollbarRounding = 8.0
	style.ItemSpacing = imgui.ImVec2(8, 8)
	
	colors[clr.Text]                   = ImVec4(0.96, 0.96, 0.96, 1.00)
	colors[clr.TextDisabled]           = ImVec4(0.62, 0.62, 0.62, 1.00)
	colors[clr.ScrollbarBg]            = ImVec4(0.00, 0.00, 0.00, 0.15)
	colors[clr.ScrollbarGrab]          = ImVec4(1.00, 1.00, 1.00, 0.15)
	colors[clr.ScrollbarGrabHovered]   = ImVec4(1.00, 1.00, 1.00, 0.20)
	colors[clr.ScrollbarGrabActive]    = ImVec4(1.00, 1.00, 1.00, 0.25)
	colors[clr.CheckMark]              = ImVec4(0.43, 0.72, 1.00, 1.00)
end)

local function DrawHighlightedText(text, search)
	if search == "" then
		imgui.TextColored(imgui.ImVec4(0.96, 0.97, 1.0, 1.0), u8(text))
		return
	end
	local start_idx, end_idx = text:lower():find(search, 1, true)
	if not start_idx then
		imgui.TextColored(imgui.ImVec4(0.96, 0.97, 1.0, 1.0), u8(text))
		return
	end
	
	local p1 = text:sub(1, start_idx - 1)
	local p2 = text:sub(start_idx, end_idx)
	local p3 = text:sub(end_idx + 1)
	
	if p1 ~= "" then
		imgui.TextColored(imgui.ImVec4(0.96, 0.97, 1.0, 1.0), u8(p1))
		imgui.SameLine(0, 0)
	end
	imgui.TextColored(imgui.ImVec4(1.0, 0.84, 0.0, 1.0), u8(p2)) -- ������� ��������� ����������
	if p3 ~= "" then
		imgui.SameLine(0, 0)
		imgui.TextColored(imgui.ImVec4(0.96, 0.97, 1.0, 1.0), u8(p3))
	end
end

imgui.OnFrame(function() return renderWindow[0] end, function(player)
	local current_scale_val = scaleValues[uiScaleIndex[0] + 1]
	local initial_scale = prevScale / 100.0
	if current_scale_val ~= prevScale then
		local new_scale = current_scale_val / 100.0
		imgui.SetNextWindowSize(imgui.ImVec2(880 * new_scale, 620 * new_scale), imgui.Cond.Always)
		prevScale = current_scale_val
	end

	imgui.SetNextWindowPos(imgui.ImVec2(500, 500), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
	imgui.SetNextWindowSize(imgui.ImVec2(880 * initial_scale, 620 * initial_scale), imgui.Cond.FirstUseEver)
	
	imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
	imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0, 0, 0, 0))
	imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, (auto_update.rounding * 1.33) * initial_scale)
	imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
	imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, uiAlpha)
	
	local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
	
	uiAlpha = math.min(1.0, uiAlpha + imgui.GetIO().DeltaTime * 8.0)
	
	local acc = auto_update.accent_color
	local style = imgui.GetStyle()
	style.Colors[imgui.Col.CheckMark] = imgui.ImVec4(acc[1], acc[2], acc[3], 1.00)
	style.Colors[imgui.Col.SliderGrab] = imgui.ImVec4(acc[1], acc[2], acc[3], 0.80)
	style.Colors[imgui.Col.SliderGrabActive] = imgui.ImVec4(acc[1], acc[2], acc[3], 1.00)
	style.Colors[imgui.Col.TextSelectedBg] = imgui.ImVec4(acc[1], acc[2], acc[3], 0.35)
	
	if imgui.Begin("##���������CEF", renderWindow, flags) then
		if imgui.IsKeyPressed(27, false) then renderWindow[0] = false end
		
		local scale = current_scale_val / 100.0
		imgui.SetWindowFontScale(scale)

		local p = imgui.GetWindowPos()
		local s = imgui.GetWindowSize()
		local draw_list = imgui.GetWindowDrawList()
		
		local c_bg = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.05, 0.055, 0.07, 0.96))
		draw_list:AddRectFilled(p, imgui.ImVec2(p.x + s.x, p.y + s.y), c_bg, (auto_update.rounding * 1.33) * scale)
		draw_list:AddRect(p, imgui.ImVec2(p.x + s.x, p.y + s.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(acc[1], acc[2], acc[3], 0.40)), (auto_update.rounding * 1.33) * scale, 15, 1.0)
		
		-- ������� ������� ��� �������������� (CEF topbar)
		local top_h = 60 * scale
		imgui.SetCursorPos(imgui.ImVec2(0, 0))
		imgui.InvisibleButton("##drag", imgui.ImVec2(s.x - 440 * scale, top_h))
		if imgui.IsItemActive() then
			local delta = imgui.GetIO().MouseDelta
			imgui.SetWindowPosVec2(imgui.ImVec2(p.x + delta.x, p.y + delta.y))
		end
		draw_list:AddLine(imgui.ImVec2(p.x, p.y + top_h), imgui.ImVec2(p.x + s.x, p.y + top_h), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(acc[1], acc[2], acc[3], 0.25)), 1.0)
		
		-- CEF ���������
		imgui.SetCursorPos(imgui.ImVec2(22 * scale, 22 * scale))
		imgui.SetCursorPos(imgui.ImVec2(14 * scale, 22 * scale))
		imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), u8"���������� ����������")
		imgui.SameLine(0, 8 * scale)
		imgui.TextColored(imgui.ImVec4(1, 1, 1, 0.4), fa.ICON_FA_INFO_CIRCLE)
		if imgui.IsItemHovered() then
			imgui.SetTooltip(u8"����� �������: Haribo\n������: 4.0")
		end
		
		-- ����� ��� CEF "Pill" ������
		local function DrawPill(text, pos_x, pos_y, bg_col, border_col, text_col, scale)
			scale = scale or 1.0
			local r = auto_update.rounding * 0.77 * scale
			local t_sz = imgui.CalcTextSize(text)
			local pad_x, pad_y = 13 * scale, 7 * scale
			local rect_w, rect_h = t_sz.x + pad_x * 2, t_sz.y + pad_y * 2
			local c_bg = imgui.ColorConvertFloat4ToU32(bg_col)
			local c_border = imgui.ColorConvertFloat4ToU32(border_col)
			
			draw_list:AddRectFilled(imgui.ImVec2(p.x + pos_x, p.y + pos_y), imgui.ImVec2(p.x + pos_x + rect_w, p.y + pos_y + rect_h), c_bg, r)
			draw_list:AddRect(imgui.ImVec2(p.x + pos_x, p.y + pos_y), imgui.ImVec2(p.x + pos_x + rect_w, p.y + pos_y + rect_h), c_border, r, 15, 1.0)
			
			imgui.SetCursorPos(imgui.ImVec2(pos_x + pad_x, pos_y + pad_y))
			imgui.TextColored(text_col, text)
			return rect_w
		end
		
		local px = s.x - 22 * scale
		local px = s.x - 14 * scale
		
		-- ������ ��������
		px = px - 38 * scale
		imgui.SetCursorPos(imgui.ImVec2(px, 11 * scale))
		imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(1,1,1,0.055))
		imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1,1,1,0.10))
		imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1,1,1,0.15))
		imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(acc[1], acc[2], acc[3], 0.25))
		imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.77 * scale)
		imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)
		if imgui.Button("X", imgui.ImVec2(38 * scale, 38 * scale)) then renderWindow[0] = false end
		
		-- ������ �����������
		local rst_text = fa.ICON_FA_SYNC .. " " .. u8"����������"
		local rst_w = imgui.CalcTextSize(rst_text).x + 20 * scale
		px = px - rst_w - 8 * scale
		imgui.SetCursorPos(imgui.ImVec2(px, 11 * scale))
		if imgui.Button(rst_text, imgui.ImVec2(rst_w, 38 * scale)) then
			need_reload = true
		end
		
		-- ������ �����
		local logs_label = fa.ICON_FA_HISTORY .. " " .. (uiShowLogs[0] and u8"�����" or u8"����")
		local logs_w = imgui.CalcTextSize(logs_label).x + 20 * scale
		px = px - logs_w - 8 * scale
		imgui.SetCursorPos(imgui.ImVec2(px, 11 * scale))
		if imgui.Button(logs_label .. "##btn_logs", imgui.ImVec2(logs_w, 38 * scale)) then
			uiShowLogs[0] = not uiShowLogs[0]
			if uiShowLogs[0] then uiShowUpdates[0] = false end
		end
		if imgui.IsItemHovered() then
			imgui.SetTooltip(uiShowLogs[0] and u8"��������� � ������" or u8"������� ������� ����� ������")
		end
		
		-- ������ ����������
		local updates_label = fa.ICON_FA_LIST .. " " .. (uiShowUpdates[0] and u8"�����" or u8"����������")
		local updates_w = imgui.CalcTextSize(updates_label).x + 20 * scale
		px = px - updates_w - 8 * scale
		imgui.SetCursorPos(imgui.ImVec2(px, 11 * scale))
		if imgui.Button(updates_label .. "##btn_upd", imgui.ImVec2(updates_w, 38 * scale)) then
			uiShowUpdates[0] = not uiShowUpdates[0]
			if uiShowUpdates[0] then uiShowLogs[0] = false end
		end
		if imgui.IsItemHovered() then
			imgui.SetTooltip(uiShowUpdates[0] and u8"��������� � ������" or u8"���������� ������ ��������� �������")
		end
		imgui.PopStyleVar(2)
		imgui.PopStyleColor(4)
		
		px = px - 10 * scale
		if auto_update.attempting then
			local statusText = u8"����������..."
			local statusColor = imgui.ImVec4(0.4, 0.8, 0.4, 0.1)
			local statusColorBorder = imgui.ImVec4(0.4, 0.8, 0.4, 0.2)
			local pill_w = DrawPill(statusText, px - imgui.CalcTextSize(statusText).x - 26 * scale, 13 * scale, statusColor, statusColorBorder, imgui.ImVec4(1,1,1,0.88), scale)
			px = px - pill_w - 10 * scale
		end
		
		local timeText = os.date("%H:%M:%S")
		local time_w = DrawPill(timeText, px - imgui.CalcTextSize(timeText).x - 26 * scale, 13 * scale, imgui.ImVec4(1, 1, 1, 0.055), imgui.ImVec4(1, 1, 1, 0.08), imgui.ImVec4(1,1,1,0.88), scale)
		px = px - time_w - 10 * scale

		imgui.SetCursorPos(imgui.ImVec2(22 * scale, top_h + 18 * scale))
		imgui.SetCursorPos(imgui.ImVec2(14 * scale, top_h + 18 * scale))
		
		-- ������� ����������
		local content_h = s.y - 115 * scale
		local right_w = 320 * scale
		local left_w = s.x - right_w - 65 * scale
		local left_w = s.x - right_w - 42 * scale
		
		local function DrawMetric(id, title, value, color_accent, width, scale)
			scale = scale or 1.0
			imgui.PushStyleColor(imgui.Col.ChildBg, color_accent)
			imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(1,1,1,0.08))
			imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, auto_update.rounding * 0.9 * scale)
			imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(15 * scale, 15 * scale))
			
			imgui.BeginChild(id, imgui.ImVec2(width, 75 * scale), true, imgui.WindowFlags.AlwaysUseWindowPadding + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
			
			imgui.TextColored(imgui.ImVec4(1,1,1,0.50), title)
			imgui.Dummy(imgui.ImVec2(0, 2 * scale))
			imgui.TextColored(imgui.ImVec4(1,1,1,1), value)
			
			imgui.EndChild()
			
			imgui.PopStyleVar(2)
			imgui.PopStyleColor(2)
		end
		
		imgui.BeginGroup()
		if not uiShowLogs[0] and not uiShowUpdates[0] then
		if BeginCEFSection("##Search", u8"����� ����������", u8"����", imgui.ImVec2(left_w, 105 * scale), scale) then
			local cursor_y = imgui.GetCursorPosY()
			local win_h = imgui.GetWindowHeight()
			local item_h = imgui.CalcTextSize("A").y + 24 * scale
			if win_h - cursor_y > item_h then
				imgui.SetCursorPosY(cursor_y + (win_h - cursor_y - item_h) / 2.0)
			end
			
			imgui.PushItemWidth(-1)
			imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0,0,0,0.2))
			imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(acc[1], acc[2], acc[3], 0.20))
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.6 * scale)
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)
			imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(32 * scale, 9 * scale))
			imgui.InputTextWithHint("##search", u8"������� ��������...", searchBuffer, 256)
			
			local item_min = imgui.GetItemRectMin()
			local item_max = imgui.GetItemRectMax()
			local icon_sz = imgui.CalcTextSize(fa.ICON_FA_SEARCH)
			draw_list:AddText(imgui.ImVec2(item_min.x + 12 * scale, item_min.y + (item_max.y - item_min.y - icon_sz.y) / 2.0), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.4)), fa.ICON_FA_SEARCH)
			
			imgui.PopStyleVar(3)
			imgui.PopStyleColor(2)
			imgui.PopItemWidth()
		end
		EndCEFSection()
		
		imgui.Dummy(imgui.ImVec2(0, 5 * scale))
		
		if BeginCEFSection("##Prices", u8"������ ���", tostring(VCount()) .. u8" ����", imgui.ImVec2(left_w, content_h - 110 * scale), scale, 0.0) then
			imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1,1,1,0.62))
			imgui.Text(u8"������")
			imgui.SameLine()
			imgui.SetCursorPosX(left_w - 120 * scale)
			imgui.Text(u8"������� ����")
			imgui.PopStyleColor()
			imgui.Separator()
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			
			imgui.BeginChild("##PriceListScroll", imgui.ImVec2(0, 0), false)
			local searchStr = u8:decode(ffi.string(searchBuffer)):lower()
			local list_draw_list = imgui.GetWindowDrawList()
			local scroll_w = imgui.GetWindowWidth()
			
			for _, model in ipairs(sorted_models_cache) do
				local price = V[model]
				if searchStr == "" or model:lower():find(searchStr, 1, true) then
					imgui.BeginGroup()
					DrawHighlightedText(model, searchStr)
					imgui.EndGroup()
					if imgui.IsItemHovered() then
						imgui.SetTooltip(u8"�������, ����� ����������� ��������")
					end
					if imgui.IsItemClicked() then
						setClipboardText(model)
						showCefNotification(string.format("�������� <b>%s</b> �����������!", model), false)
					end
					
					imgui.SameLine()
					imgui.SetCursorPosX(scroll_w - 120 * scale)
					local price_str = "$" .. convertToPriceFormat(price)
					imgui.TextColored(imgui.ImVec4(0.58, 0.95, 0.66, 1.0), price_str)
					if imgui.IsItemHovered() then
						imgui.SetTooltip(u8"�������, ����� ����������� ����")
					end
					if imgui.IsItemClicked() then
						setClipboardText(tostring(price))
						showCefNotification(string.format("���� <b>%s</b> �����������!", price_str), false)
					end
					
					imgui.Dummy(imgui.ImVec2(0, 2 * scale))
					local line_p = imgui.GetCursorScreenPos()
					list_draw_list:AddLine(line_p, imgui.ImVec2(line_p.x + scroll_w, line_p.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1,1,1,0.05)), 1.0)
					list_draw_list:AddLine(line_p, imgui.ImVec2(line_p.x + scroll_w - 30 * scale, line_p.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1,1,1,0.05)), 1.0)
					imgui.Dummy(imgui.ImVec2(0, 2 * scale))
				end
			end
			imgui.EndChild()
		end
		EndCEFSection()
		imgui.EndGroup()
		
		imgui.SameLine(s.x - right_w - 14 * scale)
		imgui.BeginGroup()
		
		local time_str = auto_update.last_update > 0 and os.date("%H:%M:%S", auto_update.last_update) or u8"12.04.2026"
		local acc = auto_update.accent_color
		DrawMetric("##m1", u8"��������� ����������", time_str, imgui.ImVec4(acc[1], acc[2], acc[3], 0.14), right_w, scale)
		
		imgui.Dummy(imgui.ImVec2(0, 5 * scale))
		
		if BeginCEFSection("##Help", u8"�������", u8"�������", imgui.ImVec2(right_w, 150 * scale), scale) then
			imgui.TextColored(imgui.ImVec4(1,1,1,0.62), u8"/ab [��������] - ����� ����")
			
			imgui.Dummy(imgui.ImVec2(0, 10 * scale))
			imgui.TextColored(imgui.ImVec4(1, 1, 1, 0.62), u8"����������� ��������:")
			
			local bh_text = fa.ICON_FA_CAR .. " BlastHack: threads/253058"
			local bh_size = imgui.CalcTextSize(bh_text)
			local p_link = imgui.GetCursorScreenPos()
			local hovered = imgui.IsMouseHoveringRect(p_link, imgui.ImVec2(p_link.x + bh_size.x, p_link.y + bh_size.y))
			
			if hovered then
				imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(acc[1], acc[2], acc[3], 1.0))
			else
				imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 1.0, 1.0, 1.0))
			end
			
			if imgui.Selectable(bh_text, false, 0, bh_size) then
				os.execute('explorer "https://www.blast.hk/threads/253058/"')
			end
			if imgui.IsItemHovered() then imgui.SetTooltip(u8"�������, ����� ������� � ��������") end
			imgui.PopStyleColor()
		end
		EndCEFSection()
		
		imgui.Dummy(imgui.ImVec2(0, 5 * scale))
		
		if BeginCEFSection("##Settings", u8"���������", u8"���������", imgui.ImVec2(right_w, content_h - 305 * scale), scale) then
			imgui.TextColored(imgui.ImVec4(1,1,1,0.62), u8"������� ���� (%):")
			imgui.PushItemWidth(-1)
			imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0,0,0,0.2))
			imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(acc[1], acc[2], acc[3], 0.20))
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.44 * scale)
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)
			if imgui.BeginCombo("##scale", scaleOptions[uiScaleIndex[0] + 1]) then
				for i, opt in ipairs(scaleOptions) do
					local is_selected = (uiScaleIndex[0] == (i - 1))
					if imgui.Selectable(opt, is_selected) then
						uiScaleIndex[0] = i - 1
						auto_update.ui_scale = scaleValues[i]
						save_autoupdate_config()
					end
					if is_selected then imgui.SetItemDefaultFocus() end
				end
				imgui.EndCombo()
			end
			imgui.PopStyleVar(2)
			imgui.PopStyleColor(2)
			imgui.PopItemWidth()
			
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			imgui.TextColored(imgui.ImVec4(1, 1, 1, 0.62), u8"�������� �������:")
			
			local presets = {
				{name = "����������� (�����)", col = {0.31, 0.67, 1.00}},
				{name = "����������", col = {0.18, 0.80, 0.44}},
				{name = "���������", col = {0.90, 0.49, 0.13}},
				{name = "���������", col = {0.90, 0.29, 0.23}},
				{name = "�������", col = {0.60, 0.33, 0.73}},
			}
			
			local current_preset_name = "���� ����"
			for _, preset in ipairs(presets) do
				if math.abs(uiAccentColor[0] - preset.col[1]) < 0.01 and math.abs(uiAccentColor[1] - preset.col[2]) < 0.01 and math.abs(uiAccentColor[2] - preset.col[3]) < 0.01 then
					current_preset_name = preset.name
					break
				end
			end
			
			imgui.PushItemWidth(-1)
			imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0,0,0,0.2))
			imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(acc[1], acc[2], acc[3], 0.20))
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.44 * scale)
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)
			if imgui.BeginCombo("##presetCombo", u8(current_preset_name)) then
				for i, preset in ipairs(presets) do
					local is_selected = (current_preset_name == preset.name)
					if imgui.Selectable(u8(preset.name), is_selected) then
						uiAccentColor[0], uiAccentColor[1], uiAccentColor[2] = preset.col[1], preset.col[2], preset.col[3]
						auto_update.accent_color = {preset.col[1], preset.col[2], preset.col[3]}
						save_autoupdate_config()
					end
					if is_selected then imgui.SetItemDefaultFocus() end
				end
				imgui.EndCombo()
			end
			imgui.PopStyleVar(2)
			imgui.PopStyleColor(2)
			imgui.PopItemWidth()
			
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			imgui.PushItemWidth(100 * scale)
			if imgui.ColorEdit3(u8"���� ����", uiAccentColor, imgui.ColorEditFlags.NoInputs) then
				auto_update.accent_color = {uiAccentColor[0], uiAccentColor[1], uiAccentColor[2]}
				save_autoupdate_config()
			end
			imgui.PopItemWidth()
			imgui.SameLine(0, 10 * scale)
			if imgui.Button(u8"��������", imgui.ImVec2(100 * scale, 0)) then
				uiAccentColor[0], uiAccentColor[1], uiAccentColor[2] = 0.31, 0.67, 1.0
				auto_update.accent_color = {0.31, 0.67, 1.0}
				save_autoupdate_config()
			end
			
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			imgui.PushItemWidth(-1)
			if imgui.SliderFloat("##rounding", uiRounding, 0.0, 36.0, u8"����������: %.1f") then
				auto_update.rounding = uiRounding[0]
				save_autoupdate_config()
			end
			imgui.PopItemWidth()
			
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			if imgui.Checkbox(u8"���� CEF-�����������", uiSoundEnabled) then
				auto_update.sound_enabled = uiSoundEnabled[0]
				save_autoupdate_config()
			end
		end
		EndCEFSection()
		
		elseif uiShowLogs[0] then
			-- === ���� ����� (������� ������) ===
			if BeginCEFSection("##LogsHistory", u8"������� ������", tostring(#my_logs) .. u8" �������", imgui.ImVec2(left_w, content_h), scale, 0.0) then
				imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1,1,1,0.62))
				imgui.Text(u8"����")
				imgui.SameLine(100 * scale)
				imgui.Text(u8"��������")
				imgui.SameLine(190 * scale)
				imgui.Text(u8"���������")
				imgui.SameLine(left_w - 195 * scale)
				imgui.Text(u8"�����")
				imgui.PopStyleColor()
				imgui.Separator()
				imgui.Dummy(imgui.ImVec2(0, 5 * scale))
				
				imgui.BeginChild("##LogsScroll", imgui.ImVec2(0, 0), false)
				local list_draw_list = imgui.GetWindowDrawList()
				local scroll_w = imgui.GetWindowWidth()
				
				if #my_logs == 0 then
					imgui.Dummy(imgui.ImVec2(0, 20 * scale))
					imgui.TextColored(imgui.ImVec4(1, 1, 1, 0.4), u8"� ��� ���� ��� ������� � ������� ��� ������� ����������.")
				end
				
				for i = #my_logs, 1, -1 do
					local log = my_logs[i]
					local date_str = os.date("%d.%m.%y %H:%M", log.time)
					local action_str, action_color
					if log.action == "buy" then
						action_str = fa.ICON_FA_MINUS .. " " .. u8"�������"
						action_color = imgui.ImVec4(0.95, 0.4, 0.4, 1.0)
					else
						action_str = fa.ICON_FA_PLUS .. " " .. u8"�������"
						action_color = imgui.ImVec4(0.4, 0.95, 0.4, 1.0)
					end
					
					imgui.AlignTextToFramePadding()
					imgui.TextColored(imgui.ImVec4(0.7, 0.7, 0.7, 1.0), date_str)
					imgui.SameLine(100 * scale)
					imgui.TextColored(action_color, action_str)
					
					if editingLogIndex[0] == i then
						imgui.SameLine(190 * scale)
						imgui.PushItemWidth(130 * scale)
						imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(5 * scale, 2 * scale))
						imgui.InputText("##editModel" .. i, editLogModel, 256)
						imgui.PopItemWidth()
						
						imgui.SameLine(scroll_w - 230 * scale)
						imgui.PushItemWidth(90 * scale)
						imgui.InputText("##editPrice" .. i, editLogPrice, 256)
						imgui.PopStyleVar()
						imgui.PopItemWidth()
						
						imgui.SameLine(scroll_w - 125 * scale)
						imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.9, 0.7, 0.3, 0.8))
						if imgui.Selectable(fa.ICON_FA_UNDO .. "##zero" .. i, false, 0, imgui.CalcTextSize(fa.ICON_FA_UNDO)) then
							ffi.copy(editLogPrice, "0")
						end
						if imgui.IsItemHovered() then imgui.SetTooltip(u8"�������� ����") end
						imgui.PopStyleColor()
						
						imgui.SameLine(scroll_w - 90 * scale)
						imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.4, 0.9, 0.4, 0.8))
						if imgui.Selectable(fa.ICON_FA_CHECK .. "##save" .. i, false, 0, imgui.CalcTextSize(fa.ICON_FA_CHECK)) then
							local newModel = u8:decode(ffi.string(editLogModel))
							local newPrice = tonumber((ffi.string(editLogPrice):gsub("[%.,%s]", "")))
							if newModel ~= "" and newPrice then
								my_logs[i].model = newModel
								my_logs[i].price = newPrice
								save_logs()
							end
							editingLogIndex[0] = -1
						end
						if imgui.IsItemHovered() then imgui.SetTooltip(u8"���������") end
						imgui.PopStyleColor()
						
						imgui.SameLine(scroll_w - 60 * scale)
						imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.8, 0.3, 0.3, 0.6))
						if imgui.Selectable(fa.ICON_FA_TIMES .. "##cancel" .. i, false, 0, imgui.CalcTextSize(fa.ICON_FA_TIMES)) then
							editingLogIndex[0] = -1
						end
						if imgui.IsItemHovered() then imgui.SetTooltip(u8"������") end
						imgui.PopStyleColor()
					else
						imgui.SameLine(190 * scale)
						imgui.Text(u8(log.model))
						imgui.SameLine(scroll_w - 195 * scale)
						imgui.TextColored(action_color, "$" .. convertToPriceFormat(log.price))
						
						imgui.SameLine(scroll_w - 85 * scale)
						imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.5, 0.7, 1.0, 0.6))
						if imgui.Selectable(fa.ICON_FA_PEN .. "##edit" .. i, false, 0, imgui.CalcTextSize(fa.ICON_FA_PEN)) then
							editingLogIndex[0] = i
							ffi.copy(editLogModel, u8(log.model))
							ffi.copy(editLogPrice, tostring(log.price))
						end
						if imgui.IsItemHovered() then imgui.SetTooltip(u8"������������� ������") end
						imgui.PopStyleColor()
						
						imgui.SameLine(scroll_w - 60 * scale)
						imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.8, 0.3, 0.3, 0.6))
						if imgui.Selectable(fa.ICON_FA_TRASH .. "##del" .. i, false, 0, imgui.CalcTextSize(fa.ICON_FA_TRASH)) then
							table.remove(my_logs, i)
							save_logs()
						end
						if imgui.IsItemHovered() then imgui.SetTooltip(u8"������� ������") end
						imgui.PopStyleColor()
					end
					
					imgui.Dummy(imgui.ImVec2(0, 2 * scale))
					local line_p = imgui.GetCursorScreenPos()
					list_draw_list:AddLine(line_p, imgui.ImVec2(line_p.x + scroll_w, line_p.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1,1,1,0.05)), 1.0)
					list_draw_list:AddLine(line_p, imgui.ImVec2(line_p.x + scroll_w - 30 * scale, line_p.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1,1,1,0.05)), 1.0)
					imgui.Dummy(imgui.ImVec2(0, 2 * scale))
				end
				imgui.EndChild()
			end
			EndCEFSection()
			imgui.EndGroup()
			
			imgui.SameLine(s.x - right_w - 14 * scale)
			imgui.BeginGroup()
			
			local spent, earned = 0, 0
			local profit_today = 0
			local current_date = os.date("%d.%m.%y")
			
			for _, log in ipairs(my_logs) do
				local is_today = os.date("%d.%m.%y", log.time) == current_date
				if log.action == "buy" then 
					spent = spent + log.price
					if is_today then profit_today = profit_today - log.price end
				elseif log.action == "sell" then 
					earned = earned + log.price 
					if is_today then profit_today = profit_today + log.price end
				end
			end
			local profit_all = earned - spent
			
			DrawMetric("##log_spent", u8"���������", "$" .. convertToPriceFormat(spent), imgui.ImVec4(0.9, 0.3, 0.3, 0.14), right_w, scale)
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			DrawMetric("##log_earned", u8"����������", "$" .. convertToPriceFormat(earned), imgui.ImVec4(0.3, 0.9, 0.3, 0.14), right_w, scale)
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			
			local half_w = (right_w - 8 * scale) / 2
			local prof_today_col = profit_today >= 0 and imgui.ImVec4(0.3, 0.9, 0.3, 0.14) or imgui.ImVec4(0.9, 0.3, 0.3, 0.14)
			local prof_today_str = (profit_today >= 0 and "+$" or "-$") .. convertToPriceFormat(math.abs(profit_today))
			
			local prof_all_col = profit_all >= 0 and imgui.ImVec4(0.3, 0.9, 0.3, 0.14) or imgui.ImVec4(0.9, 0.3, 0.3, 0.14)
			local prof_all_str = (profit_all >= 0 and "+$" or "-$") .. convertToPriceFormat(math.abs(profit_all))
			
			imgui.BeginGroup()
			DrawMetric("##log_profit_today", u8"������� (�������)", prof_today_str, prof_today_col, half_w, scale)
			imgui.SameLine(0, 8 * scale)
			DrawMetric("##log_profit_all", u8"������� (�����)", prof_all_str, prof_all_col, half_w, scale)
			imgui.EndGroup()
			
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			
			if BeginCEFSection("##AddManualLog", u8"�������� ������", u8"������ ����", imgui.ImVec2(right_w, 255 * scale), scale) then
				imgui.PushItemWidth(-1)
				imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0,0,0,0.2))
				imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(acc[1], acc[2], acc[3], 0.20))
				imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.44 * scale)
				imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)
				
				if imgui.BeginCombo("##logAction", logAddAction[0] == 0 and u8"������� (-)" or u8"������� (+)") then
					if imgui.Selectable(u8"������� (-)", logAddAction[0] == 0) then logAddAction[0] = 0 end
					if imgui.Selectable(u8"������� (+)", logAddAction[0] == 1) then logAddAction[0] = 1 end
					imgui.EndCombo()
				end
				
				imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(32 * scale, 9 * scale))
				
				imgui.Dummy(imgui.ImVec2(0, 3 * scale))
				imgui.InputTextWithHint("##logModel", u8"������ ����������...", logAddModel, 256)
				local m_min = imgui.GetItemRectMin()
				local m_max = imgui.GetItemRectMax()
				local m_icon_sz = imgui.CalcTextSize(fa.ICON_FA_CAR)
				imgui.GetWindowDrawList():AddText(imgui.ImVec2(m_min.x + 12 * scale, m_min.y + (m_max.y - m_min.y - m_icon_sz.y) / 2.0), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.4)), fa.ICON_FA_CAR)
				
				imgui.Dummy(imgui.ImVec2(0, 3 * scale))
				imgui.InputTextWithHint("##logPrice", u8"�����...", logAddPrice, 256)
				local p_min = imgui.GetItemRectMin()
				local p_max = imgui.GetItemRectMax()
				local p_icon_sz = imgui.CalcTextSize("$")
				imgui.GetWindowDrawList():AddText(imgui.ImVec2(p_min.x + 14 * scale, p_min.y + (p_max.y - p_min.y - p_icon_sz.y) / 2.0), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.4)), "$")
				
				imgui.PopStyleVar()
				
				imgui.PopStyleVar(2)
				imgui.PopStyleColor(2)
				imgui.PopItemWidth()
				
				imgui.Dummy(imgui.ImVec2(0, 6 * scale))
				imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(acc[1], acc[2], acc[3], 0.4))
				imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(acc[1], acc[2], acc[3], 0.6))
				imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(acc[1], acc[2], acc[3], 0.8))
				imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.6 * scale)
				if imgui.Button(u8"�������� � �������", imgui.ImVec2(-1, 32 * scale)) then
					local m = u8:decode(ffi.string(logAddModel))
					local p = parseAbbreviatedPrice(ffi.string(logAddPrice))
					if m ~= "" and p then
						if p >= 10000 then
							table.insert(my_logs, {
								action = logAddAction[0] == 0 and "buy" or "sell",
								model = m,
								price = p,
								time = os.time()
							})
							save_logs()
							logAddModel[0] = 0
							logAddPrice[0] = 0
						else
							showCefNotification("������! ����� ������ ���� �� ����� $10.000", true)
						end
					end
				end
				imgui.PopStyleVar()
				imgui.PopStyleColor(3)
			end
			EndCEFSection()
			
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			
			imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.8, 0.3, 0.3, 0.4))
			imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.9, 0.3, 0.3, 0.6))
			imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1.0, 0.3, 0.3, 0.8))
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.6 * scale)
			if imgui.Button(u8"�������� ������� ������", imgui.ImVec2(right_w, 35 * scale)) then
				my_logs = {}
				save_logs()
			end
			imgui.PopStyleVar()
			imgui.PopStyleColor(3)
		elseif uiShowUpdates[0] then
			-- === ���� ���������� ===
			if BeginCEFSection("##UpdateLogs", u8"������ ���������", u8"������ " .. thisScript().version, imgui.ImVec2(left_w, content_h), scale, 0.0) then
				imgui.BeginChild("##UpdatesScroll", imgui.ImVec2(0, 0), false)
				local list_draw_list = imgui.GetWindowDrawList()
				
				imgui.Dummy(imgui.ImVec2(0, 5 * scale))
				imgui.TextColored(imgui.ImVec4(0.4, 0.8, 0.4, 1.0), fa.ICON_FA_CHECK_CIRCLE .. " " .. u8"������ " .. thisScript().version .. u8" (�������)")
				imgui.Dummy(imgui.ImVec2(0, 2 * scale))
				imgui.TextWrapped(u8"- ��������� �������� �� ������� ����������.\n- ������� ������ ��������: ��������������� (UI Scale) � �������� �������.\n- ��������� �������������� ���������� ������ (�������/�������) � ����.\n- ��������� ����������� ������������� ������ ����� � ������� ������.\n- ��������� ����������� ��������� ��� ��������� ����������.\n- ���������� �������� � ���������� ��� ������ � ����� �� ������� �����.\n- ��������� ������ �� ����������� ���� BlastHack.")
				
				imgui.Dummy(imgui.ImVec2(0, 10 * scale))
				local line_p = imgui.GetCursorScreenPos()
				list_draw_list:AddLine(line_p, imgui.ImVec2(line_p.x + left_w, line_p.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1,1,1,0.05)), 1.0)
				list_draw_list:AddLine(line_p, imgui.ImVec2(line_p.x + left_w - 30 * scale, line_p.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1,1,1,0.05)), 1.0)
				imgui.Dummy(imgui.ImVec2(0, 10 * scale))
				
				imgui.TextColored(imgui.ImVec4(0.8, 0.6, 0.2, 1.0), fa.ICON_FA_INFO_CIRCLE .. " " .. u8"������ 3.0")
				imgui.Dummy(imgui.ImVec2(0, 2 * scale))
				imgui.TextWrapped(u8"- ����������� ����� ������� �������� CEF-����������� ��� ������ ���������� �� �����.\n- ������������� ������� ��� � �������� ����������.\n- ��������� ������������ ���������� ����� � ��������� � ������ ����������� � ���.\n- ������ ����������� ����� � ��������� ����� ������������ ������ �������.")
				
				imgui.EndChild()
			end
			EndCEFSection()
			imgui.EndGroup()
			
			imgui.SameLine(s.x - right_w - 14 * scale)
			imgui.BeginGroup()
			
			DrawMetric("##upd_ver", u8"������� ������", thisScript().version, imgui.ImVec4(acc[1], acc[2], acc[3], 0.14), right_w, scale)
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			
			imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(acc[1], acc[2], acc[3], 0.4))
			imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(acc[1], acc[2], acc[3], 0.6))
			imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(acc[1], acc[2], acc[3], 0.8))
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.6 * scale)
			if imgui.Button(isUpdating and u8"��������..." or u8"��������� ����������", imgui.ImVec2(right_w, 35 * scale)) then
				if not isUpdating then
					checkAndDownloadUpdate()
				end
			end
			imgui.PopStyleVar()
			imgui.PopStyleColor(3)
			
			imgui.Dummy(imgui.ImVec2(0, 5 * scale))
			
			if BeginCEFSection("##UpdInfo", u8"����������", u8"��������", imgui.ImVec2(right_w, content_h - 125 * scale), scale) then
				imgui.TextWrapped(u8"������� �� ������������, ����� ���� � ����� ����� ������� � ���������.\n\n����������� ������� ������������ ������, �������� �� ������ � ����������� ������������� BlastHack.")
			end
			EndCEFSection()
		end
		imgui.EndGroup()
	end
	imgui.End()
	imgui.PopStyleVar(3)
	imgui.PopStyleColor(2)
end)


function main()
	assert(isSampLoaded(), "SA:MP is required!")
	repeat wait(0) until isSampAvailable()

	-- �������� ������� ����� ������ �� Sunshinek ��� Likyor
	lua_thread.create(function()
		local response = fetchUrl(UPDATE_JSON_URL)
		if response and response ~= "" then
			local status, data = pcall(decodeJson, response)
			if status and type(data) == "table" and data.version and data.author then
				local current_ver = tonumber(thisScript().version) or 5.0
				local new_ver = tonumber(data.version)
				if new_ver and new_ver > current_ver then
					if data.author == "Sunshinek" or data.author == "Likyor" then
						-- ��� ���� ������������ ����� ������� �����������
						wait(3000)
						showCefNotification(string.format("�������� ����� ������ <b>%s</b> �� <b>%s</b>! ��������� BlastHack.", data.version, data.author), false)
						chatMessage("�������� ���������� ������� �� ������ {FF6640}%s{EEEEEE} �� ������ {FF6640}%s{EEEEEE}!", data.version, data.author)
					end
				end
			end
		end
	end)

	sampRegisterChatCommand("ab", function(arg)
		if VCount() == 0 then
			chatMessage("������� ���� �� ���������� �� ���������!")
			if isViceCity() then
				chatMessage("��������� �� ����� �� ����������� ������ ����������")
			else
				chatMessage("��������� �� ����� �� ����������� ������ (�������� �� �����)")
				sampSetRaceCheckpoint(2, -2131.36, -745.71, 32.02, 1)   
				CHECKPOINT = { -2131.36, -745.71 }
			end
			return nil
		elseif string.find(arg, "^[%s%c]*$") then
			renderWindow[0] = not renderWindow[0]
			if renderWindow[0] then uiAlpha = 0.0 end
			return nil
		end

		local results = {}

		arg = string.lower(arg)
		for model, price in pairs(V) do
			if string.find(string.lower(model), arg, 1, true) then
				table.insert(results, {
					model = model,
					price = price
				})
			end
		end

		if #results == 0 then
			chatMessage("�� ������� �� ������ ���������� � ������� ���������")
		else
			if #results > 10 then
				chatMessage("�������� 10 �������� ������� ������� ����������:")
			end
			for i, v in ipairs(results) do
				local price = convertToPriceFormat(v.price)
				chatMessage("%s - {FF6640}$%s", v.model, price)
				if i >= 10 then break end
			end
		end
	end)

	sampRegisterChatCommand("abhelp", function(arg)
		renderWindow[0] = true
		uiAlpha = 0.0
	end)

	while true do
		wait(0)
		if need_reload then
			thisScript():reload()
		end
		
		if CHECKPOINT ~= nil then
			local x, y, z = getCharCoordinates(PLAYER_PED)
			local dist = getDistanceBetweenCoords2d(CHECKPOINT[1], CHECKPOINT[2], x, y)
			if dist <= 3.00 then
				sampDisableRaceCheckpoint()
				CHECKPOINT = nil
			end
		end

		if parsing.active and os.clock() - parsing.timer > 5.00 then
			showCefNotification("������! ��������� ����� �������� ������ �� �������.", true)
			parsing.active = false
		end
	end
end

function onScriptTerminate(scr, is_quit)
	if scr == thisScript() then
		if CHECKPOINT ~= nil then
			sampDisableRaceCheckpoint()
			CHECKPOINT = nil
		end

		for handle, _ in pairs(MARKERS) do
			removeUser3dMarker(handle)
			MARKERS[handle] = nil
		end
	end
end

function se.onSetRaceCheckpoint(type, pos_1, pos_2, size)
	CHECKPOINT = nil
end

function se.onShowDialog(id, style, header, but_1, but_2, body)
	-- \\ ������� ���� ������� ��� �� ���������
	if style == 5 and header:find("������� ���� ����������� ��� �������") then
		if parsing.active then
			if body == parsing.last_body then
				parsing.active = false
				save_prices()
				showCefNotification(string.format("������������ ���������! ���������� � ����: <b>%d</b>", VCount()), false)
				sampSendDialogResponse(id, 0, 0, "")
				return false
			end

			parsePage(body)
			parsing.last_body = body
			parsing.timer = os.clock()

			local list = findListInDialog(body, style, "��������� ��������")
			if list then
				sampSendDialogResponse(id, 1, list, "")
				return false
			end

			-- ���� ������ "��������� ��������" ���, ������ ��� ����� ������
			parsing.active = false
			save_prices()
			showCefNotification(string.format("������������ ���������! ���������� � ����: <b>%d</b>", VCount()), false)
			sampSendDialogResponse(id, 0, 0, "")
			return false
		end

		-- ���� ������������ ���������
		body = body:gsub("(����� �� ��������\t \n)", "%1{70FF70}�������������� ����\t \n", 1)

		if VCount() > 0 then
			parsePage(body)
			save_prices()
		end

		body = reformatPrices(body)
	end

	-- \\ ���� ������� ��� �� ���������, ��������� ����� ����� � ������
	if style == 5 and string.find(header, "������� ���� ������� ����") then
		parsePage(body)
		save_prices()

		body = reformatPrices(body)
	end

	-- \\ ���� ��������� ���������� ������ ������������� ��������
	if style == 5 and string.find(header, "������� ���������� \'.-\' �� ��������� %d+ ����") then
		body = reformatPrices(body)
	end

	-- \\ ���� ��������� ������������ �������� ����������
	if style == 0 and header:find("����������� ������� ����������") then
		local model = body:match("���������:%s*{%x+}(.-)%s*%[%d+%]")
		if not model then model = body:match("���������:%s*{%x+}(.-)\n") end
		if not model then model = body:match("���������:%s*(.-)\n") end
		if model then model = model:gsub("{%x+}", ""):gsub("%s+$", "") end
		
		local average_price
		if model and V[model] then
			average_price = ("\n\n{FFFFFF}������� ���� �� �����: {73B461}$%s"):format(convertToPriceFormat(V[model]))
		else
			average_price = "\n\n{AAAAAA}������� �������� ���� ����������"
		end

		body = body .. average_price
		body = reformatPrices(body)
	end

	-- \\ ���� ������������� ������� ������������� ��������
	if style == 0 and header:find("������������� �������") then
		-- ���� ����� � �������� � ����� ����� ������, ��� ���� $X + $Y (��������� "��������" � "���������")
		local chars = "kK��mM��lL��nN��tT��yY��sS��bB��rR��dD��"
		local price, comm = body:match("[%$]?%s*([%d%.%,%s" .. chars .. "]+)%s*%+.-[%$]?%s*([%d%.%,%s" .. chars .. "]+)")
		
		-- ���� �������� ����
		local model = body:match("���������:%s*{%x+}(.-)%s*%[%d+%]")
		if not model then model = body:match("���������:%s*{%x+}(.-)\n") end
		if not model then model = body:match("���������:%s*(.-)\n") end
		if model then model = model:gsub("{%x+}", ""):gsub("%s+$", "") end
		
		if price and comm then
			-- ������� ��������� ����� � �������, ����� Lua ���� �� �������
			local clean_price = parseAbbreviatedPrice(price) or 0
			local clean_comm = parseAbbreviatedPrice(comm) or 0
			local sum = clean_price + clean_comm
			body = body .. ("\n\n{FFFFFF}�������� ���� (� ���������): {FF6640}$%s"):format(convertToPriceFormat(sum))
			
			pending_buy.active = true
			pending_buy.model = model or "���������"
			pending_buy.price = sum
			pending_buy.time = os.clock()
		end

		body = reformatPrices(body)
	end

	-- \\ ���� ����������� ���������� �� �������/������� (��� ������� �������� ����)
	if header:find("�������") or header:find("�������") or header:find("�������") then
		local model = body:match("���������:%s*{%x+}(.-)%s*%[%d+%]")
		if not model then model = body:match("���������:%s*{%x+}(.-)\n") end
		if not model then model = body:match("���������:%s*(.-)\n") end
		if model then 
			model = model:gsub("{%x+}", ""):gsub("%s+$", "") 
			pending_sell.model = model
		end
	end

	-- \\ ���� ����� ������ ��� ���������� �� ��������
	if style == 1 and string.find(header, "��������� ������") and string.find(body, "��������� ���������") then
		body = reformatPrices(body)
	end

	return { id, style, header, but_1, but_2, body }
end

function se.onServerMessage(color, text)
	local clean_text = text:gsub("{%x+}", "")

	-- ������� � ������ ��� � ����
	local bought_model, bought_price = clean_text:match("�� ������� ������ ��������� (.-) � ������ .- �� %D*(.+)")
	if not bought_model then
		bought_model, bought_price = clean_text:match("�� ������� ��������� ��������� (.-) �� %D*(.+)")
	end

	if bought_model and bought_price then
		local price = parseAbbreviatedPrice(bought_price)
		if price then
			table.insert(my_logs, { action = "buy", model = bought_model, price = price, time = os.time() })
			save_logs()
			showCefNotification(string.format("������� <b>%s</b> ��������� � ����!", bought_model), false)
		end
	end

	-- ����� �������� �� "����������� � �������������..." (��� / �� ��������)
	if clean_text:find("����������� � ������������� ������������� ��������") then
		if pending_buy.active and (os.clock() - pending_buy.time < 60) then
			table.insert(my_logs, { action = "buy", model = pending_buy.model, price = pending_buy.price, time = os.time() })
			save_logs()
			showCefNotification(string.format("������� <b>%s</b> ��������� � ����!", pending_buy.model), false)
			pending_buy.active = false
		else
			showCefNotification("��������� ������! �������� ����� � ������ ����� �����.", true)
		end
	end

	-- �������� ��������� � ����������� �� ������� � ����
	local listed_model, listed_price = clean_text:match("��������� (.-) �� ������� �� %D*(.+)")
	if listed_model and listed_price then
		local parsed_model = listed_model:gsub("^������������ �������� ", ""):gsub("^��������� ", ""):gsub("^���� ��������� ", "")
		pending_sell.active = true
		if parsed_model ~= "��� ���������" then
			pending_sell.model = parsed_model
		end
		pending_sell.price = parseAbbreviatedPrice(listed_price) or 0
		pending_sell.time = os.clock()
	end

	-- ������� ���������� (����� �������� �� ��, ����� � ������ ��� �������� � ����)
	if clean_text:find("����������� � �������� ������������� ��������") then
		if pending_sell.active and pending_sell.price > 0 then
			table.insert(my_logs, { action = "sell", model = pending_sell.model, price = pending_sell.price, time = os.time() })
			save_logs()
			showCefNotification(string.format("������� <b>%s</b> �� <b>$%s</b> ��������� � ����!", pending_sell.model, convertToPriceFormat(pending_sell.price)), false)
			pending_sell.active = false
		else
			table.insert(my_logs, { action = "sell", model = "����������� ���������", price = 0, time = os.time() })
			save_logs()
			showCefNotification("��������� ������! ����� ���������� (0$). �������������� ��� �������.", true)
		end
	end

	-- ������� ���������� ����������� (���� � ���)
	local state_sell_price = clean_text:match("�� ������� ���� ��������� ����������� �� %D*(.+)")
	if state_sell_price then
		local price = parseAbbreviatedPrice(state_sell_price)
		if price then
			table.insert(my_logs, { action = "sell", model = "���� � ���", price = price, time = os.time() })
			save_logs()
			showCefNotification("������� � ��� ��������� � ����!", false)
		end
	end

	-- ������ � ��������
	local auc_model, auc_price = clean_text:match("�� ������� �������� ��������� (.-) � �������� �� %D*(.+)")
	if auc_model and auc_price then
		local price = parseAbbreviatedPrice(auc_price)
		if price then
			table.insert(my_logs, { action = "buy", model = auc_model, price = price, time = os.time() })
			save_logs()
			showCefNotification(string.format("������ � ��������: <b>%s</b>", auc_model), false)
		end
	end

	-- ������� ������ (����� ������� ��� ��������)
	local sold_model, sold_price = clean_text:match("�� ������� ��������� (.-) ������ .- �� %D*(.+)")
	if not sold_model then
		local player; player, sold_model, sold_price = clean_text:match("����� (.-) ����� � ��� ��������� (.-) �� %D*(.+)")
	end

	if sold_model and sold_price then
		local price = parseAbbreviatedPrice(sold_price)
		if price then
			table.insert(my_logs, { action = "sell", model = sold_model, price = price, time = os.time() })
			save_logs()
			showCefNotification(string.format("������� <b>%s</b> ��������� � ����!", sold_model), false)
		end
	end
end

function se.onSendCommand(cmd)
	local price = cmd:match("^/sellcarto %d+ (.+)")
	if price then
		pending_sell.active = true
		pending_sell.model = "��������� (������)"
		pending_sell.price = parseAbbreviatedPrice(price) or 0
		pending_sell.time = os.clock()
	end
end

function se.onSendDialogResponse(id, button, list, input)
	if not parsing.active and button == 1 then
		local header = sampGetDialogCaption()
		local style = sampGetCurrentDialogType()
		local body = sampGetDialogText()

		-- \\ ������ ������������ ������� ���
		if style == 5 and string.find(header, "������� ���� ����������� ��� �������") then
			local list_go = findListInDialog(body, style, "�������������� ����")
			if list_go ~= nil then
				if list == list_go then
					showCefNotification("��� ������������ ������� ���... �� ���������� ����!", false)
					
					V = {}
					parsePage(body)

					parsing.active = true
					parsing.last_body = nil
					parsing.timer = os.clock()
					return { id, button, list + 1, input }
				elseif list > list_go then
					return { id, button, list - 1, input }
				end
			end
		end

		-- \\ ������ ��������� ���� ��� ����������� �� �������/�������
		local parsed_input = parseAbbreviatedPrice(input)
		if input and parsed_input then
			local header = sampGetDialogCaption()
			if header and (header:find("�������") or header:find("�������") or header:find("�������")) then
				pending_sell.active = true
				pending_sell.price = parsed_input
				pending_sell.time = os.clock()
			end
		end
	end
end

function se.onSetObjectMaterialText(id, data)
	local clean_data = data.text:gsub("{%x+}", "")
	
	do -- \\ ������� ������� ����������
		local model, price_str
		if clean_data:find("������� ����������", 1, true) then
			model, price_str = clean_data:match("������� ����������\n([^\n]+)\n����:%s*([^\n]+)")
		elseif clean_data:find("�������[��]:") or clean_data:find("���������:") then
			model, price_str = clean_data:match("^([^\n]+)\n([^\n]+)")
		end
		
		if model and price_str then
			local price = parseAbbreviatedPrice(price_str) or 0
			if price > 0 then
				local str_i = tostring(id)
				local str_v = string.format("%s/%s", model, price)
				if PLATES[str_i] ~= str_v then
					PLATES[str_i] = str_v
					
					local formatted_price = convertToPriceFormat(price)
					local cefText = string.format("�� ������� ���������: <b>%s</b> �� <b>$%s</b><br>", model, formatted_price)
					if V[model] ~= nil then
						local average = convertToPriceFormat(V[model])
						cefText = cefText .. string.format("������� ����: <b>$%s</b>", average)
					else
						cefText = cefText .. "������� ���� <b>����������</b>"
					end
					showCefNotification(cefText, false)

					lua_thread.create(function()
						local obj = sampGetObjectHandleBySampId(id)
						local wait_limit = 50
						while not doesObjectExist(obj) and wait_limit > 0 do
							wait(100)
							obj = sampGetObjectHandleBySampId(id)
							wait_limit = wait_limit - 1
						end
						if doesObjectExist(obj) then
							local _, x, y, z = getObjectCoordinates(obj)
							local marker = createUser3dMarker(x, y, z + 2, 0)
							MARKERS[marker] = true
							wait(10000)
							removeUser3dMarker(marker)
							MARKERS[marker] = nil
						end
					end)
				end
			end
		end
	end

	do -- \\ ����������� ���������� �� �������
		local auc_model = string.match(clean_data, "^������� �%d+\n([^\n]+)")
		if auc_model then
			local str_i = tostring(id)
			local str_v = "AUC/" .. auc_model
			if PLATES[str_i] ~= str_v then
				PLATES[str_i] = str_v
				showCefNotification(string.format("����� ��������� �� ��������: <b>%s</b>", auc_model), true)
				
				lua_thread.create(function()
					local obj = sampGetObjectHandleBySampId(id)
					local wait_limit = 50
					while not doesObjectExist(obj) and wait_limit > 0 do
						wait(100)
						obj = sampGetObjectHandleBySampId(id)
						wait_limit = wait_limit - 1
					end
					if doesObjectExist(obj) then
						local _, x, y, z = getObjectCoordinates(obj)
						local marker = createUser3dMarker(x, y, z + 2, 0)
						MARKERS[marker] = true
						wait(10000)
						removeUser3dMarker(marker)
						MARKERS[marker] = nil
					end
				end)
			end
		end
	end

	-- \\ ���������� ���� � ����� �� ���������
	data.text = reformatPrices(data.text)

	return { id, data }
end

function se.onCreate3DText(id, color, position, distance, testLOS, attachedPlayerId, attachedVehicleId, text)
	local clean_text = text:gsub("{%x+}", "")
	
	local model, price_str
	if clean_text:find("������� ����������", 1, true) then
		model, price_str = clean_text:match("������� ����������\n([^\n]+)\n����:%s*([^\n]+)")
	elseif clean_text:find("�������[��]:") or clean_text:find("���������:") then
		model, price_str = clean_text:match("^([^\n]+)\n([^\n]+)")
	end
	
	if model and price_str then
		local price = parseAbbreviatedPrice(price_str) or 0
		if price > 0 and price > 5000 then
			local str_i = "3d_" .. tostring(id)
			local str_v = string.format("%s/%s", model, price)
			if PLATES[str_i] ~= str_v then
				PLATES[str_i] = str_v
				
				local formatted_price = convertToPriceFormat(price)
				local cefText = string.format("�� ������� ���������: <b>%s</b> �� <b>$%s</b><br>", model, formatted_price)
				if V[model] ~= nil then
					local average = convertToPriceFormat(V[model])
					cefText = cefText .. string.format("������� ����: <b>$%s</b>", average)
				else
					cefText = cefText .. "������� ���� <b>����������</b>"
				end
				showCefNotification(cefText, false)

				local marker = createUser3dMarker(position.x, position.y, position.z + 2, 0)
				MARKERS[marker] = true
				lua_thread.create(function()
					wait(10000)
					removeUser3dMarker(marker)
					MARKERS[marker] = nil
				end)
			end
		end
	end
	
	local auc_model = string.match(clean_text, "^������� �%d+\n([^\n]+)")
	if auc_model then
		local str_i = "3d_" .. tostring(id)
		local str_v = "AUC/" .. auc_model
		if PLATES[str_i] ~= str_v then
			PLATES[str_i] = str_v
			showCefNotification(string.format("����� ��������� �� ��������: <b>%s</b>", auc_model), true)
			
			local marker = createUser3dMarker(position.x, position.y, position.z + 2, 0)
			MARKERS[marker] = true
			lua_thread.create(function()
				wait(10000)
				removeUser3dMarker(marker)
				MARKERS[marker] = nil
			end)
		end
	end
	
	text = reformatPrices(text)
	return {id, color, position, distance, testLOS, attachedPlayerId, attachedVehicleId, text}
end
