-----------------------------------------------
-- @Desc  : 茗伊插件
-- @Author: 茗伊 @双梦镇 @追风蹑影
-- @Date  : 2018-4-19 23:59:25
-- @Email : admin@derzh.com
-- @Last modified by:   tinymins
-- @Last modified time: 2018-4-20 0:28:38
-- @Ref: 借鉴大量海鳗源码 @haimanchajian.com
-----------------------------------------------
-----------------------------------------------------------------------------------------
-- these global functions are accessed all the time by the event handler
-- so caching them is worth the effort
-----------------------------------------------------------------------------------------
local setmetatable = setmetatable
local ipairs, pairs, next, pcall = ipairs, pairs, next, pcall
local sub, len, format, rep = string.sub, string.len, string.format, string.rep
local find, byte, char, gsub = string.find, string.byte, string.char, string.gsub
local type, tonumber, tostring = type, tonumber, tostring
local floor, min, max, ceil = math.floor, math.min, math.max, math.ceil
local huge, pi, sin, cos, tan = math.huge, math.pi, math.sin, math.cos, math.tan
local insert, remove, concat, sort = table.insert, table.remove, table.concat, table.sort
local pack, unpack = table.pack or function(...) return {...} end, table.unpack or unpack
-- jx3 apis caching
local wsub, wlen, wfind = wstring.sub, wstring.len, wstring.find
local GetTime, GetLogicFrameCount = GetTime, GetLogicFrameCount
local GetClientPlayer, GetPlayer, GetNpc = GetClientPlayer, GetPlayer, GetNpc
local GetClientTeam, UI_GetClientPlayerID = GetClientTeam, UI_GetClientPlayerID
local IsNil, IsNumber, IsFunction = MY.IsNil, MY.IsNumber, MY.IsFunction
local IsBoolean, IsString, IsTable = MY.IsBoolean, MY.IsString, MY.IsTable
-----------------------------------------------------------------------------------------
local _L = MY.LoadLangPack()

local function UploadSerendipity(szName, szSerendipity, nMethod, bFinish, dwTime)
	if MY.IsInDevMode() then
		return
	end
	MY.Ajax({
		type = "post/json",
		url = 'http://data.jx3.derzh.com/api/serendipities',
		data = {
			data = MY.SimpleEncrypt(MY.JsonEncode({
				n = szName, S = MY.GetRealServer(1), s = MY.GetRealServer(2),
				N = szSerendipity, f = bFinish, t = dwTime, m = nMethod,
			})),
			lang = MY.GetLang(),
		},
		success = function(html, status) end,
	})
	MY.Ajax({
		type = "get",
		url = 'http://data.jx3.derzh.com/serendipity/?l=' .. MY.GetLang() .. "&m=" .. nMethod
		.. "&data=" .. MY.SimpleEncrypt(MY.JsonEncode({
			n = szName, S = MY.GetRealServer(1), s = MY.GetRealServer(2),
			a = szSerendipity, f = bFinish, t = dwTime,
		})),
		success = function(html, status) end,
	})
	local szKey = szName .. "_" .. szSerendipity .. "_" .. dwTime
	local szText = szName == GetClientPlayer().szName
		and _L(bFinish
			and "You finished %s, would you like to share?"
			or "You got %s, would you like to share?", szSerendipity)
		or _L(bFinish
			and "[%s] finished %s, would you like to share?"
			or "[%s] got %s, would you like to share?", szName, szSerendipity)
	local function fnAction()
		local szName = szName
		local szNameU = AnsiToUTF8(szName)
		local szNameCRC = ("%x%x%x"):format(szNameU:byte(), GetStringCRC(szNameU), szNameU:byte(-1))
		local szReporter = MY.LoadLUAData({"config/realname.jx3dat", MY_DATA_PATH.ROLE}) or GetClientPlayer().szName:gsub("@.-$", "")
		GetUserInput(_L["Please input your realname, left blank for anonymous report:"], function(szText)
			if szText ~= szReporter then
				MY.SaveLUAData({"config/realname.jx3dat", MY_DATA_PATH.ROLE}, szText)
			end
			if szText == '' and nMethod == 1 then
				szName = ''
			end
			XGUI.CreateFrame("MY_Serendipity#" .. szKey, {
				w = 300, h = 400, close = true, text = "",
			}):append("WndWebCef", {
				x = 0, y = 0, w = 300, h = 400,
				navigate = 'https://jx3.derzh.com/serendipity/?l='
				.. MY.GetLang() .. "&m=" .. nMethod
				.. "&data=" .. MY.SimpleEncrypt(MY.JsonEncode({
					n = szName, N = szNameCRC, R = szText,
					S = MY.GetRealServer(1), s = MY.GetRealServer(2),
					a = szSerendipity, f = bFinish, t = dwTime,
				})),
			})
			MY.DismissNotify(szKey)
		end, nil, nil, nil, szReporter, 6)
	end
	MY.CreateNotify(szKey, GetFormatText(szText), fnAction)
end

MY.RegisterMsgMonitor("QIYU", function(szMsg, nFont, bRich, r, g, b, szChannel)
	-- 战斗中移动中免打扰
	local me = GetClientPlayer()
	if not me then
		return
	end
	-- if not me or me.bFightState
	-- or (
	-- 	me.nMoveState ~= MOVE_STATE.ON_STAND    and
	-- 	me.nMoveState ~= MOVE_STATE.ON_FLOAT    and
	-- 	me.nMoveState ~= MOVE_STATE.ON_SIT      and
	-- 	me.nMoveState ~= MOVE_STATE.ON_FREEZE   and
	-- 	me.nMoveState ~= MOVE_STATE.ON_ENTRAP   and
	-- 	me.nMoveState ~= MOVE_STATE.ON_DEATH    and
	-- 	me.nMoveState ~= MOVE_STATE.ON_AUTO_FLY and
	-- 	me.nMoveState ~= MOVE_STATE.ON_START_AUTO_FLY
	-- ) then
	-- 	return
	-- end
	-- local hWnd = Station.GetFocusWindow()
	-- if hWnd and hWnd:GetType() == "WndEdit" then
	-- 	return
	-- end
	-- 跨服中免打扰
	if IsRemotePlayer(me.dwID) then
		return
	end
	-- 确认是真实系统消息
	if not StringLowerW(szMsg):find("ui/image/minimap/minimap.uitex") then
		return
	end
	-- “醉戈止战”侠士福缘非浅，触发奇遇【阴阳两界】，此千古奇缘将开启怎样的奇妙际遇，令人神往！
	if bRich then
		szMsg = GetPureText(szMsg)
	end
	szMsg:gsub(_L.ADVENTURE_PATT, function(szName, szSerendipity)
		local dwTime = GetCurrentTime()
		local function Upload()
			UploadSerendipity(szName, szSerendipity, 1, 0, dwTime)
		end
		MY.DelayCall(math.random(0, 5000), Upload)
	end)
end, {"MSG_SYS"})

do
local function GetSerendipityName(nID)
	for i = 2, g_tTable.Adventure:GetRowCount() do
		local tLine = g_tTable.Adventure:GetRow(i)
		if tLine.dwID == nID then
			return tLine.szName
		end
	end
end

MY.RegisterEvent("ON_SERENDIPITY_TRIGGER.QIYU", function()
	local me = GetClientPlayer()
	if not me then
		return
	end
	UploadSerendipity(me.szName, GetSerendipityName(arg0), 2, arg1, GetCurrentTime())
end)
end

do
local l_serendipities
local function GetSerendipityInfo(dwTabType, dwIndex)
	if not l_serendipities then
		l_serendipities = MY.LoadLUAData(MY.GetAddonInfo().szFrameworkRoot .. 'data/serendipities.jx3dat')
	end
	local serendipity = l_serendipities[dwTabType] and l_serendipities[dwTabType][dwIndex]
	if serendipity then
		local iteminfo = GetItemInfo(serendipity[1], serendipity[2])
		if iteminfo then
			return iteminfo.szName, serendipity[3] == 1
		end
	end
end

MY.RegisterEvent('LOOT_ITEM', function()
	local player = GetPlayer(arg0)
	local item = GetItem(arg1)
	if not player or not item then
		return
	end
	local szSerendipity, bFinish = GetSerendipityInfo(item.dwTabType, item.dwIndex)
	if szSerendipity then
		UploadSerendipity(player.szName, szSerendipity, 3, bFinish, GetCurrentTime())
	end
end)

MY.RegisterEvent('QUEST_FINISHED', function()
	local me = GetClientPlayer()
	if not me then
		return
	end
	local szSerendipity, bFinish = GetSerendipityInfo('quest', arg0)
	if szSerendipity then
		UploadSerendipity(me.szName, szSerendipity, 4, bFinish, GetCurrentTime())
	end
end)
end
