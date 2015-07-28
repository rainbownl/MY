--------------------------------------------------------------------------
-- 开发者工具
-- by 茗伊 @ 双梦镇 @ 荻花宫
-- Build 20140730
--------------------------------------------------------------------------
local tostring, string2byte = tostring, string.byte
local srep, tconcat, tinsert = string.rep, table.concat, table.insert
local type, next, print, pairs, ipairs = type, next, print, pairs, ipairs
local _L = MY.LoadLangPack(MY.GetAddonInfo().szRoot.."Dev_Snaplines/lang/")
--------------------------------------------------------------------------
-- 数据存储
--------------------------------------------------------------------------
MYDev_Snaplines = {}
MYDev_Snaplines.bEnable = false
RegisterCustomData('MYDev_Snaplines.bEnable')
MYDev_Snaplines.bDetectBox = true
RegisterCustomData('MYDev_Snaplines.bDetectBox')
MYDev_Snaplines.bShowWndSnaplines = true
RegisterCustomData('MYDev_Snaplines.bShowWndSnaplines')
MYDev_Snaplines.bShowItemSnaplines = true
RegisterCustomData('MYDev_Snaplines.bShowItemSnaplines')
MYDev_Snaplines.bShowTip = true
RegisterCustomData('MYDev_Snaplines.bShowTip')
MYDev_Snaplines.bShowData = true
RegisterCustomData('MYDev_Snaplines.bShowData')
MYDev_Snaplines.rgbWndSnaplines = {0, 0, 0}
RegisterCustomData('MYDev_Snaplines.rgbWndSnaplines')
MYDev_Snaplines.rgbItemSnaplines = {0, 255, 0}
RegisterCustomData('MYDev_Snaplines.rgbItemSnaplines')
MYDev_Snaplines.rgbTip = {255, 255, 0}
RegisterCustomData('MYDev_Snaplines.rgbTip')
MYDev_Snaplines.nTipFont = 40
RegisterCustomData('MYDev_Snaplines.nTipFont')
MYDev_Snaplines.bAutoScale = true
RegisterCustomData('MYDev_Snaplines.bAutoScale')
--------------------------------------------------------------------------
-- 本地函数
--------------------------------------------------------------------------
local function var2str(var, indent, level)
	local function table_r(var, level, indent)
		local t = {}
		local szType = type(var)
		if szType == "nil" then
			tinsert(t, "nil")
		elseif szType == "number" then
			tinsert(t, tostring(var))
		elseif szType == "string" then
			tinsert(t, string.format("%q", var))
		-- elseif szType == "function" then
			-- local s = string.dump(var)
			-- tinsert(t, 'loadstring("')
			-- -- "string slice too long"
			-- for i = 1, #s, 2000 do
			--	 tinsert(t, tconcat({'', string2byte(s, i, i + 2000 - 1)}, "\\"))
			-- end
			-- tinsert(t, '")')
		elseif szType == "boolean" then
			tinsert(t, tostring(var))
		elseif szType == "table" then
			tinsert(t, "{")
			local s_tab_equ = "]="
			if indent then
				s_tab_equ = "] = "
				if not empty(var) then
					tinsert(t, "\n")
				end
			end
			for key, val in pairs(var) do
				if indent then
					tinsert(t, srep(indent, level + 1))
				end
				tinsert(t, "[")
				tinsert(t, table_r(key, level + 1, indent))
				tinsert(t, s_tab_equ) --"] = "
				tinsert(t, table_r(val, level + 1, indent))
				tinsert(t, ",")
				if indent then
					tinsert(t, "\n")
				end
			end
			if indent and not empty(var) then
				tinsert(t, srep(indent, level))
			end
			tinsert(t, "}")
		else --if (szType == "userdata") then
			tinsert(t, '"')
			tinsert(t, tostring(var))
			tinsert(t, '"')
		end
		return tconcat(t)
	end
	return table_r(var, level or 0, indent)
end

local function InsertElementBasicTip(hElem, tTip)
	local X, Y = hElem:GetAbsPos()
	local x, y = hElem:GetRelPos()
	local w, h = hElem:GetSize()
	
	tinsert(tTip, _L('Name: %s', hElem:GetName()))
	tinsert(tTip, _L('Type: %s', hElem:GetType()))
	tinsert(tTip, _L('Path: %s', MY.UI.GetTreePath(hElem)))
	tinsert(tTip, _L('X: %s, %s', x, X))
	tinsert(tTip, _L('Y: %s, %s', y, Y))
	tinsert(tTip, _L('W: %s', w))
	tinsert(tTip, _L('H: %s', h))
end

local function InsertElementDetailTip(hElem, tTip)
	local szType = hElem:GetType()
	if szType == 'Text' then
		tinsert(tTip, _L('FontScheme: %s', hElem:GetFontScheme()))
		tinsert(tTip, _L('Text: %s', hElem:GetText()))
		tinsert(tTip, _L('TextLen: %s', hElem:GetTextLen()))
		tinsert(tTip, _L('VAlign: %s', hElem:GetVAlign()))
		tinsert(tTip, _L('HAlign: %s', hElem:GetHAlign()))
		tinsert(tTip, _L('RowSpacing: %s', hElem:GetRowSpacing()))
		tinsert(tTip, _L('IsMultiLine: %s', tostring(hElem:IsMultiLine())))
		tinsert(tTip, _L('IsCenterEachLine: %s', tostring(hElem:IsCenterEachLine())))
		tinsert(tTip, _L('FontSpacing: %s', hElem:GetFontSpacing()))
		tinsert(tTip, _L('IsRichText: %s', tostring(hElem:IsRichText())))
		tinsert(tTip, _L('FontScale: %s', hElem:GetFontScale()))
		tinsert(tTip, _L('FontID: %s', hElem:GetFontID()))
		tinsert(tTip, _L('FontColor: %s', hElem:GetFontColor()))
		tinsert(tTip, _L('FontBoder: %s', hElem:GetFontBoder()))
		tinsert(tTip, _L('FontProjection: %s', hElem:GetFontProjection()))
		tinsert(tTip, _L('TextExtent: %s', hElem:GetTextExtent()))
		tinsert(tTip, _L('TextPosExtent: %s', hElem:GetTextPosExtent()))
		tinsert(tTip, _L('Index: %s', hElem:GetIndex()))
	elseif szType == 'Image' then
		tinsert(tTip, _L('Frame: %s', hElem:GetFrame()))
		tinsert(tTip, _L('ImageType: %s', hElem:GetImageType()))
		tinsert(tTip, _L('ImageID: %s', hElem:GetImageID()))
		tinsert(tTip, _L('Index: %s', hElem:GetIndex()))
	elseif szType == 'Shadow' then
		tinsert(tTip, _L('ShadowColor: %s', hElem:GetShadowColor()))
		tinsert(tTip, _L('ColorRGB: %s, %s, %s', hElem:GetColorRGB()))
		tinsert(tTip, _L('IsTriangleFan: %s', tostring(hElem:IsTriangleFan())))
		tinsert(tTip, _L('Index: %s', hElem:GetIndex()))
	elseif szType == 'Animate' then
		tinsert(tTip, _L('IsFinished: %s', tostring(hElem:IsFinished())))
		tinsert(tTip, _L('Index: %s', hElem:GetIndex()))
	elseif szType == 'Box' then
		tinsert(tTip, _L('BoxIndex: %s', hElem:GetBoxIndex()))
		-- tinsert(tTip, _L('Object: %s', hElem:GetObject()))
		tinsert(tTip, _L('ObjectType: %s', hElem:GetObjectType()))
		tinsert(tTip, _L('ObjectData: %s', tconcat({hElem:GetObjectData()}, ", ")))
		tinsert(tTip, _L('IsEmpty: %s', tostring(hElem:IsEmpty())))
		if not hElem:IsEmpty() then
			tinsert(tTip, _L('IsObjectEnable: %s', tostring(hElem:IsObjectEnable())))
			tinsert(tTip, _L('IsObjectCoolDown: %s', tostring(hElem:IsObjectCoolDown())))
			tinsert(tTip, _L('IsObjectSelected: %s', tostring(hElem:IsObjectSelected())))
			tinsert(tTip, _L('IsObjectMouseOver: %s', tostring(hElem:IsObjectMouseOver())))
			tinsert(tTip, _L('IsObjectPressed: %s', tostring(hElem:IsObjectPressed())))
			tinsert(tTip, _L('CoolDownPercentage: %s', hElem:GetCoolDownPercentage()))
			tinsert(tTip, _L('ObjectIcon: %s', hElem:GetObjectIcon()))
			tinsert(tTip, _L('OverText1: %s', hElem:GetOverText(0)))
			tinsert(tTip, _L('OverTextFontScheme1: %s', hElem:GetOverTextFontScheme(0)))
			tinsert(tTip, _L('OverTextPosition1: %s', hElem:GetOverTextPosition(0)))
			tinsert(tTip, _L('OverText1: %s', hElem:GetOverText(1)))
			tinsert(tTip, _L('OverTextFontScheme1: %s', hElem:GetOverTextFontScheme(1)))
			tinsert(tTip, _L('OverTextPosition1: %s', hElem:GetOverTextPosition(1)))
			tinsert(tTip, _L('OverText2: %s', hElem:GetOverText(2)))
			tinsert(tTip, _L('OverTextFontScheme2: %s', hElem:GetOverTextFontScheme(2)))
			tinsert(tTip, _L('OverTextPosition2: %s', hElem:GetOverTextPosition(2)))
			tinsert(tTip, _L('OverText3: %s', hElem:GetOverText(3)))
			tinsert(tTip, _L('OverTextFontScheme3: %s', hElem:GetOverTextFontScheme(3)))
			tinsert(tTip, _L('OverTextPosition3: %s', hElem:GetOverTextPosition(3)))
			tinsert(tTip, _L('OverText4: %s', hElem:GetOverText(4)))
			tinsert(tTip, _L('OverTextFontScheme4: %s', hElem:GetOverTextFontScheme(4)))
			tinsert(tTip, _L('OverTextPosition4: %s', hElem:GetOverTextPosition(4)))
		end
		tinsert(tTip, _L('Index: %s', hElem:GetIndex()))
	end
end

local function InsertElementDataTip(hElem, tTip)
	local data = {}
	for k, v in pairs(hElem) do
		if type(v) ~= "function" then
			data[k] = v
		end
	end
	tinsert(tTip, _L('data: %s', var2str(data, "  ")))
end

local function InsertElementTip(hElem, tTip)
	if MYDev_Snaplines.bShowTip
	or MYDev_Snaplines.bShowData then
		InsertElementBasicTip(hElem, tTip)
	end
	if MYDev_Snaplines.bShowTip then
		InsertElementDetailTip(hElem, tTip)
	end
	if MYDev_Snaplines.bShowData then
		InsertElementDataTip(hElem, tTip)
	end
end

--------------------------------------------------------------------------
-- 界面事件响应
--------------------------------------------------------------------------
function MYDev_Snaplines.OnFrameCreate()
	local W, H = Station.GetClientSize()
	-- Wnd辅助线
	if MYDev_Snaplines.bShowWndSnaplines then
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndLeft"  ):SetColorRGB(unpack(MYDev_Snaplines.rgbWndSnaplines))
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndRight" ):SetColorRGB(unpack(MYDev_Snaplines.rgbWndSnaplines))
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndTop"   ):SetColorRGB(unpack(MYDev_Snaplines.rgbWndSnaplines))
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndBottom"):SetColorRGB(unpack(MYDev_Snaplines.rgbWndSnaplines))
	else
		this:Lookup("", "Handle_Snaplines_Wnd"):Hide()
	end
	-- Item辅助线
	if MYDev_Snaplines.bShowItemSnaplines then
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemLeft"  ):SetColorRGB(unpack(MYDev_Snaplines.rgbItemSnaplines))
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemRight" ):SetColorRGB(unpack(MYDev_Snaplines.rgbItemSnaplines))
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemTop"   ):SetColorRGB(unpack(MYDev_Snaplines.rgbItemSnaplines))
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemBottom"):SetColorRGB(unpack(MYDev_Snaplines.rgbItemSnaplines))
	else
		this:Lookup("", "Handle_Snaplines_Item"):Hide()
	end
	-- 文字
	this:Lookup("", "Handle_Tip/Text_HoverTip"):SetFontScheme(MYDev_Snaplines.nTipFont)
	this:Lookup("", "Handle_Tip/Text_HoverTip"):SetFontColor(unpack(MYDev_Snaplines.rgbTip))
	
	MYDev_Snaplines.OnEvent("UI_SCALED")
end

function MYDev_Snaplines.OnFrameBreathe()
	local hWnd, hItem = Station.GetMouseOverWindow()
	if hWnd then
		-- Wnd
		local nClientW, nClientH = Station.GetClientSize()
		local nCursorX, nCursorY = Cursor.GetPos()
		local nWndX   , nWndY    = hWnd:GetAbsPos()
		local nWndW   , nWndH    = hWnd:GetSize()
		local hText = this:Lookup("", "Handle_Tip/Text_HoverTip")
		-- Wnd信息
		local tTip = {}
		tinsert(tTip, _L('CursorX: %s', nCursorX))
		tinsert(tTip, _L('CursorY: %s', nCursorY))
		InsertElementTip(hWnd, tTip)
		-- Wnd辅助线位置
		if MYDev_Snaplines.bShowWndSnaplines then
			this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndLeft"  ):SetAbsPos(nWndX - 2    , 0)
			this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndRight" ):SetAbsPos(nWndX + nWndW, 0)
			this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndTop"   ):SetAbsPos(0, nWndY - 2    )
			this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndBottom"):SetAbsPos(0, nWndY + nWndH)
		end
		-- 检测鼠标所在Box信息
		if MYDev_Snaplines.bDetectBox and not (hItem and hItem:GetType() == 'Box') then
			MY.UI(hWnd):find('.Box'):each(function()
				if this:PtInItem(nCursorX, nCursorY) then
					tinsert(tTip, '---------------------')
					InsertElementTip(this, tTip)
				end
			end)
		end
		-- Item
		if hItem then
			-- Item信息
			local nItemX, nItemY = hItem:GetAbsPos()
			local nItemW, nItemH = hItem:GetSize()
			tinsert(tTip, _L['-------------------'])
			InsertElementTip(hItem, tTip)
			-- Item辅助线位置
			if MYDev_Snaplines.bShowItemSnaplines then
				this:Lookup("", "Handle_Snaplines_Item"):Show()
				this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemLeft"  ):SetAbsPos(nItemX - 2     , 0)
				this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemRight" ):SetAbsPos(nItemX + nItemW, 0)
				this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemTop"   ):SetAbsPos(0, nItemY - 2     )
				this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemBottom"):SetAbsPos(0, nItemY + nItemH)
			end
		else
			this:Lookup("", "Handle_Snaplines_Item"):Hide()
		end
		hText:SetText(table.concat(tTip, '\n'))
		
		-- 缩放
		if MYDev_Snaplines.bAutoScale then
			-- hText:EnableScale(true)
			hText:SetFontScale(1)
			hText:AutoSize()
			local nTextW, nTextH = hText:GetSize()
			local fScale = math.min( nClientW / nTextW, nClientH / nTextH )
			if fScale < 1 then
				hText:SetFontScale(fScale)
				hText:AutoSize()
			end
		end
		
		-- 位置
		local nTextW, nTextH = hText:GetSize()
		local nTextX, nTextY
		nTextX = nWndX + 5
		if nTextX + nTextW > nClientW then
			nTextX = nClientW - nTextW
		elseif nTextX < 0 then
			nTextX = 0
		end
		
		local bReAdjustX
		if nWndY >= nTextH then -- 顶部可以显示的下
			nTextY = nWndY - nTextH
		elseif nWndY + nWndH + 1 + nTextH <= nClientH then -- 底部显示的下
			nTextY = nWndY + nWndH + 1
		elseif nWndY + nTextH <= nClientH then -- 中间开始显示的下
			nTextY = nWndY + 20
			bReAdjustX = true
		else
			nTextY = 5
			bReAdjustX = true
		end
		if bReAdjustX then
			if nWndX >= nTextW + 5 then -- 左侧显示的下
				nTextX = nWndX - nTextW - 5
			elseif nWndX + nWndW + nTextW + 5 <= nClientW then -- 右侧显示的下
				nTextX = nWndX + nWndW + 5
			end
		end
		hText:SetAbsPos(nTextX, nTextY)
	end
	this:BringToTop()
end

function MYDev_Snaplines.OnEvent(event)
	if event == "UI_SCALED" then
		local W, H = Station.GetClientSize()
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndLeft"   ):SetSize(2, H)
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndRight"  ):SetSize(2, H)
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndTop"    ):SetSize(W, 2)
		this:Lookup("", "Handle_Snaplines_Wnd/Shadow_HoverWndBottom" ):SetSize(W, 2)
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemLeft"  ):SetSize(2, H)
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemRight" ):SetSize(2, H)
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemTop"   ):SetSize(W, 2)
		this:Lookup("", "Handle_Snaplines_Item/Shadow_HoverItemBottom"):SetSize(W, 2)
	end
end

--------------------------------------------------------------------------
-- 控制部分
--------------------------------------------------------------------------
-- 重载界面
MYDev_Snaplines.ReloadUI = function()
	Wnd.CloseWindow("MYDev_Snaplines")
	if MYDev_Snaplines.bEnable then
		Wnd.OpenWindow(MY.GetAddonInfo().szRoot .. "Dev_Snaplines/ui/MYDev_Snaplines.ini", "MYDev_Snaplines")
	end
end
MY.RegisterInit('MYDEV_SNAPLINES', MYDev_Snaplines.ReloadUI)

-- 注册面板
MY.RegisterPanel(
	"Dev_Snaplines", _L["Snaplines"], _L['Development'],
	"ui/Image/UICommon/PlugIn.UITex|1", {255,127,0,200}, {
	OnPanelActive = function(wnd)
		local ui = MY.UI(wnd)
		local w, h = ui:size()
		local x, y = 20, 20
		
		ui:append("WndCheckBox", "WndCheckBox_ShowTreePath"):children("#WndCheckBox_ShowTreePath")
		  :pos(x, y):width(300)
		  :text(_L['enable tree path view']):check(MYDev_Snaplines.bEnable or false)
		  :check(function(bCheck)
			MYDev_Snaplines.bEnable = bCheck
			MYDev_Snaplines.ReloadUI()
		end)
		y = y + 40
		
		ui:append("WndCheckBox", "WndCheckBox_ShowTip"):children("#WndCheckBox_ShowTip")
		  :pos(x, y):width(200)
		  :text(_L['show tip']):check(MYDev_Snaplines.bShowTip or false)
		  :check(function(bCheck)
			MYDev_Snaplines.bShowTip = bCheck
			MYDev_Snaplines.ReloadUI()
		end)
		x = x + 200
		ui:append("Shadow", "Shadow_TipColor"):item("#Shadow_TipColor"):pos(x, y)
		  :size(20, 20):color(MYDev_Snaplines.rgbTip or {255,255,255})
		  :click(function()
			local me = this
			MY.UI.OpenColorPicker(function(r, g, b)
				MY.UI(me):color(r, g, b)
				MYDev_Snaplines.rgbTip = { r, g, b }
				MYDev_Snaplines.ReloadUI()
			end)
		  end)
		x = x + 40
		ui:append("WndButton", "WndButton_TipFont"):children("#WndButton_TipFont"):pos(x, y)
		  :width(50):text(_L['font'])
		  :click(function()
			MY.UI.OpenFontPicker(function(f)
				MYDev_Snaplines.nTipFont = f
				MYDev_Snaplines.ReloadUI()
			end)
		  end)
		x = 20
		y = y + 40
		ui:append("WndCheckBox", "WndCheckBox_ShowData"):children("#WndCheckBox_ShowData")
		  :pos(x, y):width(200)
		  :text(_L['show data']):check(MYDev_Snaplines.bShowData or false)
		  :check(function(bCheck)
			MYDev_Snaplines.bShowData = bCheck
			MYDev_Snaplines.ReloadUI()
		end)
		y = y + 40
		
		ui:append("WndCheckBox", "WndCheckBox_ShowWndSnaplines"):children("#WndCheckBox_ShowWndSnaplines")
		  :pos(x, y):width(200)
		  :text(_L['show wnd snaplines']):check(MYDev_Snaplines.bShowWndSnaplines or false)
		  :check(function(bCheck)
			MYDev_Snaplines.bShowWndSnaplines = bCheck
			MYDev_Snaplines.ReloadUI()
		end)
		x = x + 200
		ui:append("Shadow", "Shadow_WndSnaplinesColor"):item("#Shadow_WndSnaplinesColor"):pos(x, y)
		  :size(20, 20):color(MYDev_Snaplines.rgbWndSnaplines or {255,255,255})
		  :click(function()
			local me = this
			MY.UI.OpenColorPicker(function(r, g, b)
				MY.UI(me):color(r, g, b)
				MYDev_Snaplines.rgbWndSnaplines = { r, g, b }
				MYDev_Snaplines.ReloadUI()
			end)
		  end)
		x = 20
		y = y + 40
		
		ui:append("WndCheckBox", "WndCheckBox_ShowItemSnaplines"):children("#WndCheckBox_ShowItemSnaplines")
		  :pos(x, y):width(200)
		  :text(_L['show item snaplines']):check(MYDev_Snaplines.bShowItemSnaplines or false)
		  :check(function(bCheck)
			MYDev_Snaplines.bShowItemSnaplines = bCheck
			MYDev_Snaplines.ReloadUI()
		end)
		x = x + 200
		ui:append("Shadow", "Shadow_ItemSnaplinesColor"):item("#Shadow_ItemSnaplinesColor"):pos(x, y)
		  :size(20, 20):color(MYDev_Snaplines.rgbItemSnaplines or {255,255,255})
		  :click(function()
			local me = this
			MY.UI.OpenColorPicker(function(r, g, b)
				MY.UI(me):color(r, g, b)
				MYDev_Snaplines.rgbItemSnaplines = { r, g, b }
				MYDev_Snaplines.ReloadUI()
			end)
		  end)
		x = 20
		y = y + 40
		
		ui:append("WndCheckBox", "WndCheckBox_AutoDetectBox"):children("#WndCheckBox_AutoDetectBox")
		  :pos(x, y):width(200)
		  :text(_L['auto detect box']):check(MYDev_Snaplines.bDetectBox or false)
		  :check(function(bCheck)
			MYDev_Snaplines.bDetectBox = bCheck
		end)
		y = y + 40
		
		ui:append("WndCheckBox", {
			x = x, y = y, w = 200, text = _L['auto scale'], checked = MYDev_Snaplines.bAutoScale,
			oncheck = function(bCheck) MYDev_Snaplines.bAutoScale = bCheck end
		})
		y = y + 40
		
		ui:append("Text", "Text_SetHotkey"):find("#Text_SetHotkey"):pos(w-140, 20):color(255,255,0)
		  :text(_L['>> set hotkey <<'])
		  :click(function() MY.Game.SetHotKey() end)
	end
})
-- 注册快捷键
MY.Game.AddHotKey("Dev_Snaplines"         , _L["Snaplines"]           , function() MYDev_Snaplines.bEnable   = not MYDev_Snaplines.bEnable   MYDev_Snaplines.ReloadUI() end, nil)
MY.Game.AddHotKey("Dev_Snaplines_ShowTip" , _L["Snaplines - ShowTip"] , function() MYDev_Snaplines.bShowTip  = not MYDev_Snaplines.bShowTip  MYDev_Snaplines.ReloadUI() end, nil)
MY.Game.AddHotKey("Dev_Snaplines_ShowData", _L["Snaplines - ShowData"], function() MYDev_Snaplines.bShowData = not MYDev_Snaplines.bShowData MYDev_Snaplines.ReloadUI() end, nil)
-- For Debug
if IsDebugClient and IsDebugClient() then
	MY.RegisterInit("Dev_Snaplines_Hotkey", function()
		MY.Game.SetHotKey("Dev_Snaplines", 121)
		MY.Game.SetHotKey("Dev_Snaplines_ShowTip", 122)
		MY.Game.SetHotKey("Dev_Snaplines_ShowData", 123)
	end)
end
