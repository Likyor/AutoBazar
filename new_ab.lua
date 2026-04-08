script_name("���������")
script_author("Haribo")
script_version("3.0")

local se = require "samp.events"
local imgui = require "mimgui"
local encoding = require "encoding"
local ffi = require "ffi"

encoding.default = "CP1251"
local u8 = encoding.UTF8

DIR = getWorkingDirectory() .. "\\config\\prices"
PATH = DIR .. "\\prices.ab"
AB_AREA = {
	-2154.29, -744.62, -- [A]
	-2113.49, -975.06  -- [B]
}

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

auto_update = {
	ui_scale = 100,
	last_update = 0,
	website = "https://disk.yandex.ru/d/JMMhXOX81azjpA?dl=1", -- URL ������ ����� ��� ��������� ���
	attempting = false,
	sound_enabled = true,
	accent_color = {0.31, 0.67, 1.0},
	rounding = 18.0
}

if doesFileExist(PATH) then
	local file = io.open(PATH, "r")
	V = decodeJson(file:read("*a"))
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
	local config = decodeJson(file:read("*a"))
	file:close()
	
	if type(config) == "table" then
		if config.ui_scale ~= nil then auto_update.ui_scale = config.ui_scale end
		if config.website ~= nil then auto_update.website = config.website end
		if config.sound_enabled ~= nil then auto_update.sound_enabled = config.sound_enabled end
		if config.accent_color ~= nil then auto_update.accent_color = config.accent_color end
		if config.rounding ~= nil then auto_update.rounding = config.rounding end
	end
end

local renderWindow = imgui.new.bool(false)
local searchBuffer = imgui.new.char[256]("")
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

local SCRIPT_UPDATE_URL = "https://disk.yandex.ru/d/eRlSZPtSKLNxXw?dl=1" -- ������ �� ���������� new_ab.lua

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

local cefNotifyCounter = 0
local function showCefNotification(text, isAuction)
	cefNotifyCounter = cefNotifyCounter + 1
	local currentId = cefNotifyCounter
	
	lua_thread.create(function()
		-- ��� ������� ����, ����� ������� �������� ���� ��� ��������� ��
		wait(0)
		if cefNotifyCounter ~= currentId then return end
		
		-- ��������� ������ �����������, ���� ��� �� ��� �����
		local closeJs = 'window.executeEvent("cef.modals.closeModal", `["dialogTip"]`);'
		local bsClose = raknetNewBitStream()
		raknetBitStreamWriteInt8(bsClose, 17)
		raknetBitStreamWriteInt32(bsClose, 0)
		raknetBitStreamWriteInt16(bsClose, #closeJs)
		raknetBitStreamWriteInt8(bsClose, 0)
		raknetBitStreamWriteString(bsClose, closeJs)
		raknetEmulPacketReceiveBitStream(220, bsClose)
		raknetDeleteBitStream(bsClose)
		
		-- ��� ���� ���� (50 ��), ����� CEF ����� ���������� ��������
		wait(50)
		if cefNotifyCounter ~= currentId then return end
		
		local iconColor = isAuction and "#FFD700" or "#2ECC71"
		local highlightColor = isAuction and "#FFA500" or "#5FC6FF"
		local js = string.format('window.executeEvent("cef.modals.showModal", `["dialogTip",{"position":"rightBottom","backgroundImage":"bank_notify_add.webp","icon":"icon-info","iconColor":"%s","highlightColor":"%s","text":"%s"}]`);', iconColor, highlightColor, text)
		
		local bs = raknetNewBitStream()
		raknetBitStreamWriteInt8(bs, 17)
		raknetBitStreamWriteInt32(bs, 0)
		raknetBitStreamWriteInt16(bs, #js)
		raknetBitStreamWriteInt8(bs, 0)
		raknetBitStreamWriteString(bs, js)
		raknetEmulPacketReceiveBitStream(220, bs)
		raknetDeleteBitStream(bs)
		
		if auto_update.sound_enabled then
			addOneOffSound(0.0, 0.0, 0.0, 1058)
		end
		
		wait(isAuction and 8000 or 4500)
		if cefNotifyCounter == currentId then
			local bsClose = raknetNewBitStream()
			raknetBitStreamWriteInt8(bsClose, 17)
			raknetBitStreamWriteInt32(bsClose, 0)
			raknetBitStreamWriteInt16(bsClose, #closeJs)
			raknetBitStreamWriteInt8(bsClose, 0)
			raknetBitStreamWriteString(bsClose, closeJs)
			raknetEmulPacketReceiveBitStream(220, bsClose)
			raknetDeleteBitStream(bsClose)
		end
	end)
end

function fetchUrl(url)
	-- �������� ������������ ssl.https ��� HTTPS
	local success, response = pcall(function()
		local https = require("ssl.https")
		
		local response_data, status, headers = https.request(url)
		
		if response_data and (status == 200 or status == nil) then
			return response_data
		end
		
		return nil
	end)
	
	if success and response then
		return response
	end
	
	-- ���� ssl.https �� ��������, �������� socket.http
	local success2, response2 = pcall(function()
		local http = require("socket.http")
		
		local response_data, status, headers = http.request(url)
		
		if response_data and (status == 200 or status == nil) then
			return response_data
		end
		
		return nil
	end)
	
	if success2 and response2 then
		return response2
	end
	
	-- ������������ ����� effil
	local success3, response3 = pcall(function()
		if effil and effil.url then
			local data = effil.url.get(url):take()
			return data
		end
		return nil
	end)
	
	if success3 and response3 then
		return response3
	end
	
	return nil
end

function updatePricesFromWebsite()
	if auto_update.attempting then
		return
	end
	
	auto_update.attempting = true
	
	lua_thread.create(function()
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
	for line in string.gmatch(text, "[^\n]+") do
		local model, price = string.match(line, "^(.+)\t%$?([0-9%.,]+)%$?$")
		if model and price then
			price = string.gsub(price, "[%.,]", "")
			price = tonumber(price)
			if price ~= nil then
				if V[model] ~= price then
					V[model] = price
					changed = true
				end
			end
		end
	end
	if changed then RebuildSortedCache() end
end

local function BeginCEFSection(id, title, subtitle, size, scale, custom_rounding)
	scale = scale or 1.0
	local r = custom_rounding or auto_update.rounding
	imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(1, 1, 1, 0.03))
	imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(1, 1, 1, 0.08))
	imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, r * scale)
	imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(15 * scale, 15 * scale))
	
	local ret = imgui.BeginChild(id, size, true, imgui.WindowFlags.AlwaysUseWindowPadding + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse)
	
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
		imgui.SetNextWindowSize(imgui.ImVec2(720 * new_scale, 600 * new_scale), imgui.Cond.Always)
		prevScale = current_scale_val
	end

	imgui.SetNextWindowPos(imgui.ImVec2(500, 500), imgui.Cond.FirstUseEver, imgui.ImVec2(0.5, 0.5))
	imgui.SetNextWindowSize(imgui.ImVec2(720 * initial_scale, 600 * initial_scale), imgui.Cond.FirstUseEver)
	
	imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0, 0, 0, 0))
	imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0, 0, 0, 0))
	imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, (auto_update.rounding * 1.33) * initial_scale)
	imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, imgui.ImVec2(0, 0))
	imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, uiAlpha)
	
	local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
	
	uiAlpha = math.min(1.0, uiAlpha + imgui.GetIO().DeltaTime * 8.0)
	
	if imgui.Begin("##���������CEF", renderWindow, flags) then
		if imgui.IsKeyPressed(27, false) then renderWindow[0] = false end
		
		local scale = current_scale_val / 100.0
		imgui.SetWindowFontScale(scale)

		local p = imgui.GetWindowPos()
		local s = imgui.GetWindowSize()
		local draw_list = imgui.GetWindowDrawList()
		
		local c_bg = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.05, 0.055, 0.07, 0.96))
		draw_list:AddRectFilled(p, imgui.ImVec2(p.x + s.x, p.y + s.y), c_bg, (auto_update.rounding * 1.33) * scale)
		draw_list:AddRect(p, imgui.ImVec2(p.x + s.x, p.y + s.y), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.10)), (auto_update.rounding * 1.33) * scale, 15, 1.0)
		
		-- ������� ������� ��� �������������� (CEF topbar)
		local top_h = 60 * scale
		imgui.SetCursorPos(imgui.ImVec2(0, 0))
		imgui.InvisibleButton("##drag", imgui.ImVec2(s.x - 65 * scale, top_h))
		if imgui.IsItemActive() then
			local delta = imgui.GetIO().MouseDelta
			imgui.SetWindowPosVec2(imgui.ImVec2(p.x + delta.x, p.y + delta.y))
		end
		draw_list:AddLine(imgui.ImVec2(p.x, p.y + top_h), imgui.ImVec2(p.x + s.x, p.y + top_h), imgui.ColorConvertFloat4ToU32(imgui.ImVec4(1, 1, 1, 0.08)), 1.0)
		
		-- CEF ���������
		imgui.SetCursorPos(imgui.ImVec2(22 * scale, 22 * scale))
		imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), u8"���������� ����������")
		
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
		
		-- ������ ��������
		px = px - 38 * scale
		imgui.SetCursorPos(imgui.ImVec2(px, 11 * scale))
		imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(1,1,1,0.055))
		imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(1,1,1,0.10))
		imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(1,1,1,0.15))
		imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(1,1,1,0.08))
		imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.77 * scale)
		imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)
		if imgui.Button("X", imgui.ImVec2(38 * scale, 38 * scale)) then renderWindow[0] = false end
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
		DrawPill(timeText, px - imgui.CalcTextSize(timeText).x - 26 * scale, 13 * scale, imgui.ImVec4(1, 1, 1, 0.055), imgui.ImVec4(1, 1, 1, 0.08), imgui.ImVec4(1,1,1,0.88), scale)
		
		imgui.SetCursorPos(imgui.ImVec2(22 * scale, top_h + 18 * scale))
		
		-- ������� ����������
		local content_h = s.y - 115 * scale
		local right_w = 320 * scale
		local left_w = s.x - right_w - 65 * scale
		
		imgui.BeginGroup()
		if BeginCEFSection("##Search", u8"����� ����������", u8"����", imgui.ImVec2(left_w, 105 * scale), scale) then
			local cursor_y = imgui.GetCursorPosY()
			local win_h = imgui.GetWindowHeight()
			local item_h = imgui.CalcTextSize("A").y + 24 * scale
			if win_h - cursor_y > item_h then
				imgui.SetCursorPosY(cursor_y + (win_h - cursor_y - item_h) / 2.0)
			end
			
			imgui.PushItemWidth(-1)
			imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0,0,0,0.2))
			imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(1,1,1,0.05))
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, auto_update.rounding * 0.6 * scale)
			imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1.0)
			imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, imgui.ImVec2(20 * scale, 9 * scale))
			imgui.InputTextWithHint("##search", u8"������� ��������...", searchBuffer, 240)
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
			local searchStr = ffi.string(searchBuffer):lower()
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
					imgui.Dummy(imgui.ImVec2(0, 2 * scale))
				end
			end
			imgui.EndChild()
		end
		EndCEFSection()
		imgui.EndGroup()
		
		imgui.SameLine(s.x - right_w - 14 * scale)
		imgui.BeginGroup()
		
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
		
		local time_str = auto_update.last_update > 0 and os.date("%H:%M:%S", auto_update.last_update) or u8"07.04.2026"
		local acc = auto_update.accent_color
		DrawMetric("##m1", u8"��������� ����������", time_str, imgui.ImVec4(acc[1], acc[2], acc[3], 0.14), right_w, scale)
		
		imgui.Dummy(imgui.ImVec2(0, 5 * scale))
		
		if BeginCEFSection("##Help", u8"�������", u8"�������", imgui.ImVec2(right_w, 150 * scale), scale) then
			imgui.TextColored(imgui.ImVec4(1,1,1,0.62), u8"/ab [��������] - ����� ����")
		end
		EndCEFSection()
		
		imgui.Dummy(imgui.ImVec2(0, 5 * scale))
		
		if BeginCEFSection("##Settings", u8"���������", u8"���������", imgui.ImVec2(right_w, content_h - 205 * scale), scale) then
			imgui.TextColored(imgui.ImVec4(1,1,1,0.62), u8"������� ���� (%):")
			imgui.PushItemWidth(-1)
			imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0,0,0,0.2))
			imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(1,1,1,0.05))
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
			if imgui.ColorEdit3(u8"���� �������", uiAccentColor, imgui.ColorEditFlags.NoInputs) then
				auto_update.accent_color = {uiAccentColor[0], uiAccentColor[1], uiAccentColor[2]}
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
		
		imgui.EndGroup()
	end
	imgui.End()
	imgui.PopStyleVar(3)
	imgui.PopStyleColor(2)
end)


function main()
	assert(isSampLoaded(), "SA:MP is required!")
	repeat wait(0) until isSampAvailable()

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

		body = body:gsub("%$(%d+)", function(num)
			return "$" .. convertToPriceFormat(num)
		end)
	end

	-- \\ ���� ������� ��� �� ���������, ��������� ����� ����� � ������
	if style == 5 and string.find(header, "������� ���� ������� ����") then
		parsePage(body)
		save_prices()

		body = string.gsub(body, "(%d+)%$", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	-- \\ ���� ��������� ���������� ������ ������������� ��������
	if style == 5 and string.find(header, "������� ���������� \'.-\' �� ��������� %d+ ����") then
		body = string.gsub(body, "%$(%d+)", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	-- \\ ���� ��������� ������������ �������� ����������
	if style == 0 and header:find("����������� ������� ����������") then
		local model = body:match("���������:%s*{%x+}(.-)%s*%[%d+%]")
		
		local average_price
		if model and V[model] then
			average_price = ("\n\n{FFFFFF}������� ���� �� �����: {73B461}$%s"):format(convertToPriceFormat(V[model]))
		else
			average_price = "\n\n{AAAAAA}������� �������� ���� ����������"
		end

		body = body .. average_price
		body = body:gsub("%$(%d+)", function(num)
			return "$" .. convertToPriceFormat(num)
		end)
	end

	-- \\ ���� ������������� ������� ������������� ��������
	if style == 0 and string.find(header, "������������� �������") then
		local price, comm = string.match(body, "��������� ����������: {%x+}%$(%d+) %+ %$(%d+)%( �������� %)")
		if price and comm then
			local sum = tonumber(price) + tonumber(comm)
			body = body .. ("\n\n{FFFFFF}�������� ����: {FF6640}$%s"):format(convertToPriceFormat(sum))
		end

		body = string.gsub(body, "%$(%d+)", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	-- \\ ���� ����� ������ ��� ���������� �� ��������
	if style == 1 and string.find(header, "��������� ������") and string.find(body, "��������� ���������") then
		body = string.gsub(body, "%$(%d+)", function(num)
			local price = convertToPriceFormat(num)
			return "$" .. price
		end)
	end

	return { id, style, header, but_1, but_2, body }
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
	end
end

function se.onSetObjectMaterialText(id, data)
	local object = sampGetObjectHandleBySampId(id)
	if doesObjectExist(object) then
		if getObjectModel(object) == 18663 then
			if isObjectInArea2d(object, AB_AREA[1], AB_AREA[2], AB_AREA[3], AB_AREA[4], false) then
				do -- \\ ������� ������� ����������
				    data.text = string.gsub(data.text, "%.", "")
					local model, price = string.match(data.text, "(.-)\n{%x+}%$(%d+)")
					if model and price then
						local _, x, y, z = getObjectCoordinates(object)
						local str_i = string.format("%d/%d/%d", x, y, z)
						local str_v = string.format("%s/%s", model, price)
						if PLATES[str_i] ~= str_v then
							PLATES[str_i] = str_v
							
							price = convertToPriceFormat(price)

							if isCharInArea2d(PLAYER_PED, AB_AREA[1], AB_AREA[2], AB_AREA[3], AB_AREA[4], false) then
								local cefText = string.format("�� ������� ���������: <b>%s</b> �� <b>$%s</b><br>", model, price)
								if V[model] ~= nil then
									local average = convertToPriceFormat(V[model])
									cefText = cefText .. string.format("������� ����: <b>$%s</b>", average)
								else
									cefText = cefText .. "������� ���� <b>����������</b>"
								end
								showCefNotification(cefText, false)
							end

							local marker = createUser3dMarker(x, y, z + 2, 0)
							MARKERS[marker] = true
							lua_thread.create(function()
								wait(10000)
								removeUser3dMarker(marker)
								MARKERS[marker] = nil
							end)
						end
					end
				end

				do -- \\ ����������� ���������� �� �������
					local model = string.match(data.text, "^������� �%d+\n([^\n]+)")
					if model then
						local _, x, y, z = getObjectCoordinates(object)
						local str_i = string.format("%d/%d/%d", x, y, z)
						local str_v = string.format("%s", model)
						if PLATES[str_i] ~= str_v then
							PLATES[str_i] = str_v

							if isCharInArea2d(PLAYER_PED, AB_AREA[1], AB_AREA[2], AB_AREA[3], AB_AREA[4], false) then
								showCefNotification(string.format("����� ��������� �� ��������: <b>%s</b>", model), true)
							end

							local marker = createUser3dMarker(x, y, z + 2, 0)
							MARKERS[marker] = true
							lua_thread.create(function()
								wait(10000)
								removeUser3dMarker(marker)
								MARKERS[marker] = nil
							end)
						end
					end
				end

				-- \\ ���������� ���� � ����� �� ���������
				data.text = string.gsub(data.text, "%$(%d+)", function(num)
					local price = convertToPriceFormat(num)
					return "$" .. price
				end)
			end
		end
	end
	return { id, data }
end
