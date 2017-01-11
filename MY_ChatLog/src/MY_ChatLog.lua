--
-- 聊天记录
-- 记录团队/好友/帮会/密聊 供日后查询
-- 作者：翟一鸣 @ tinymins
-- 网站：ZhaiYiMing.CoM
--

-- these global functions are accessed all the time by the event handler
-- so caching them is worth the effort
local XML_LINE_BREAKER = XML_LINE_BREAKER
local ipairs, pairs, next, pcall = ipairs, pairs, next, pcall
local tinsert, tremove, tconcat = table.insert, table.remove, table.concat
local ssub, slen, schar, srep, sbyte, sformat, sgsub =
	  string.sub, string.len, string.char, string.rep, string.byte, string.format, string.gsub
local type, tonumber, tostring = type, tonumber, tostring
local GetTime, GetLogicFrameCount = GetTime, GetLogicFrameCount
local floor, mmin, mmax, mceil = math.floor, math.min, math.max, math.ceil
local GetClientPlayer, GetPlayer, GetNpc, GetClientTeam, UI_GetClientPlayerID = GetClientPlayer, GetPlayer, GetNpc, GetClientTeam, UI_GetClientPlayerID
local setmetatable = setmetatable

local _L = MY.LoadLangPack(MY.GetAddonInfo().szRoot .. "MY_ChatLog/lang/")
MY_ChatLog = MY_ChatLog or {}
MY_ChatLog.bIgnoreTongOnlineMsg    = true -- 帮会上线通知
MY_ChatLog.bIgnoreTongMemberLogMsg = true -- 帮会成员上线下线提示
MY_ChatLog.tUncheckedChannel = {}
RegisterCustomData('MY_ChatLog.bIgnoreTongOnlineMsg')
RegisterCustomData('MY_ChatLog.bIgnoreTongMemberLogMsg')
RegisterCustomData('MY_ChatLog.tUncheckedChannel')

------------------------------------------------------------------------------------------------------
-- 数据采集
------------------------------------------------------------------------------------------------------
local TONG_ONLINE_MSG        = '^' .. MY.String.PatternEscape(g_tStrings.STR_TALK_HEAD_TONG .. g_tStrings.STR_GUILD_ONLINE_MSG)
local TONG_MEMBER_LOGIN_MSG  = '^' .. MY.String.PatternEscape(g_tStrings.STR_GUILD_MEMBER_LOGIN):gsub('<link 0>', '.-') .. '$'
local TONG_MEMBER_LOGOUT_MSG = '^' .. MY.String.PatternEscape(g_tStrings.STR_GUILD_MEMBER_LOGOUT):gsub('<link 0>', '.-') .. '$'

------------------------------------------------------------------------------------------------------
-- 数据库核心
------------------------------------------------------------------------------------------------------
local PAGE_AMOUNT = 150
local EXPORT_SLICE = 100
local PAGE_DISPLAY = 14
local DIVIDE_TABLE_AMOUNT = 30000 -- 如果某张表大小超过30000
local SINGLE_TABLE_AMOUNT = 20000 -- 则将最久远的20000条消息独立成表
local SZ_INI = MY.GetAddonInfo().szRoot .. "MY_ChatLog/ui/MY_ChatLog.ini"
local LOG_TYPE = {
	{id = "whisper", title = g_tStrings.tChannelName["MSG_WHISPER"       ], channels = {"MSG_WHISPER"       }},
	{id = "party"  , title = g_tStrings.tChannelName["MSG_PARTY"         ], channels = {"MSG_PARTY"         }},
	{id = "team"   , title = g_tStrings.tChannelName["MSG_TEAM"          ], channels = {"MSG_TEAM"          }},
	{id = "friend" , title = g_tStrings.tChannelName["MSG_FRIEND"        ], channels = {"MSG_FRIEND"        }},
	{id = "guild"  , title = g_tStrings.tChannelName["MSG_GUILD"         ], channels = {"MSG_GUILD"         }},
	{id = "guild_a", title = g_tStrings.tChannelName["MSG_GUILD_ALLIANCE"], channels = {"MSG_GUILD_ALLIANCE"}},
	{id = "death"  , title = _L["Death Log"], channels = {"MSG_SELF_DEATH", "MSG_SELF_KILL", "MSG_PARTY_DEATH", "MSG_PARTY_KILL"}},
	{id = "journal", title = _L["Journal Log"], channels = {
		"MSG_MONEY", "MSG_ITEM", --"MSG_EXP", "MSG_REPUTATION", "MSG_CONTRIBUTE", "MSG_ATTRACTION", "MSG_PRESTIGE",
		-- "MSG_TRAIN", "MSG_MENTOR_VALUE", "MSG_THEW_STAMINA", "MSG_TONG_FUND"
	}},
}
-- 频道对应数据库中数值 可添加 但不可随意修改
local CHANNELS = {
	[1] = "MSG_WHISPER",
	[2] = "MSG_PARTY",
	[3] = "MSG_TEAM",
	[4] = "MSG_FRIEND",
	[5] = "MSG_GUILD",
	[6] = "MSG_GUILD_ALLIANCE",
	[7] = "MSG_SELF_DEATH",
	[8] = "MSG_SELF_KILL",
	[9] = "MSG_PARTY_DEATH",
	[10] = "MSG_PARTY_KILL",
	[11] = "MSG_MONEY",
	[12] = "MSG_EXP",
	[13] = "MSG_ITEM",
	[14] = "MSG_REPUTATION",
	[15] = "MSG_CONTRIBUTE",
	[16] = "MSG_ATTRACTION",
	[17] = "MSG_PRESTIGE",
	[18] = "MSG_TRAIN",
	[19] = "MSG_MENTOR_VALUE",
	[20] = "MSG_THEW_STAMINA",
	[21] = "MSG_TONG_FUND",
}
local CHANNELS_R = (function() local t = {} for k, v in pairs(CHANNELS) do t[v] = k end return t end)()
local DB, InsertMsg, DeleteMsg, PushDB, GetChatLogCount, GetChatLog, OptimizeDB

do
local STMT = {}
local aInsQueue = {}
local aDelQueue = {}
-- ===== 性能测试 =====
-- local msg  = AnsiToUTF8(g_tStrings.STR_TONG_BAO_DESC)
-- local text = AnsiToUTF8(GetPureText(g_tStrings.STR_TONG_BAO_DESC))
-- local hash = GetStringCRC(msg)
-- local channel = CHANNELS_R["MSG_WORLD"]
-- for i = 1, 60000 do
-- 	table.insert(aInsQueue, {hash, channel, GetCurrentTime() - i * 30, "tester", text, msg})
-- end

local function RenameTable(oldname, newname)
	DB:Execute("DROP INDEX IF EXISTS " .. oldname .. "_channel_idx")
	DB:Execute("DROP INDEX IF EXISTS " .. oldname .. "_text_idx")
	DB:Execute("ALTER TABLE " .. oldname .. " RENAME TO " .. newname)
	DB:Execute("CREATE INDEX IF NOT EXISTS " .. newname .. "_channel_idx ON " .. newname .. "(channel)")
	DB:Execute("CREATE INDEX IF NOT EXISTS " .. newname .. "_text_idx ON " .. newname .. "(text)")
end

local function CreateTable(name)
	DB:Execute("CREATE TABLE IF NOT EXISTS " .. name .. " (hash INTEGER, channel INTEGER, time INTEGER, talker NVARCHAR(20), text NVARCHAR(400) NOT NULL, msg NVARCHAR(4000) NOT NULL, PRIMARY KEY (hash, time))")
	DB:Execute("CREATE INDEX IF NOT EXISTS " .. name .. "_channel_idx ON " .. name .. "(channel)")
	DB:Execute("CREATE INDEX IF NOT EXISTS " .. name .. "_text_idx ON " .. name .. "(text)")
end

local function UpdateSTMTCountCache(stmt, filter)
	if not filter then
		filter = ""
	end
	if filter == "" then
		stmt.count.all = 0
	end
	local utf8filter = AnsiToUTF8("%" .. filter .. "%")
	stmt.count.filter[filter] = {}
	stmt.Q:ClearBindings()
	stmt.Q:BindAll(utf8filter, utf8filter)
	for _, rec in ipairs(stmt.Q:GetAll()) do
		if filter == "" then
			stmt.count.all = stmt.count.all + rec.count
		end
		stmt.count.filter[filter][rec.channel] = rec.count
	end
	return stmt
end

local function CreateSTMT(name)
	local stmt = {
		name  = name,
		count = {all = 0, filter = {[""] = {}}},
		stime = name == "ChatLog" and  0 or tonumber((name:sub(9):gsub("_.*", ""))),
		etime = name == "ChatLog" and -1 or tonumber((name:sub(9):gsub(".*_", ""))),
		Q = DB:Prepare("SELECT channel, count(*) AS count FROM " .. name .. " WHERE talker LIKE ? OR text LIKE ? GROUP BY channel"),
		W = DB:Prepare("REPLACE INTO " .. name .. " (hash, channel, time, talker, text, msg) VALUES (?, ?, ?, ?, ?, ?)"),
		D = DB:Prepare("DELETE FROM " .. name .. " WHERE hash = ? AND time = ?"),
	}
	UpdateSTMTCountCache(stmt, "")
	if not (stmt.Q and stmt.D and stmt.W and stmt.stime and stmt.etime) then
		return MY.Debug({"Wrong table detected on CreateSTMT: " .. name}, "MY_ChatLog", MY_DEBUG.WARNING) and nil
	end
	return stmt
end

local function UpdateSTMTs()
	if not DB then
		return
	end
	STMT = {}
	
	local result = DB:Execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'ChatLog/_%/_%' ESCAPE '/' ORDER BY name")
	for _, rec in ipairs(result) do
		local stmt = CreateSTMT(rec.name)
		if stmt then
			tinsert(STMT, stmt)
		end
	end
	table.sort(STMT, function(a, b) return a.stime < b.stime end)
	
	CreateTable("ChatLog")
	local stmt = CreateSTMT("ChatLog")
	if #STMT > 0 then
		stmt.stime = STMT[#STMT].etime + 1
	end
	tinsert(STMT, stmt)
end

function InsertMsg(channel, text, msg, talker, time)
	local hash
	msg    = AnsiToUTF8(msg)
	text   = AnsiToUTF8(text) or ""
	hash   = GetStringCRC(msg)
	talker = talker and AnsiToUTF8(talker) or ""
	if not channel or not time or empty(msg) or not text or empty(hash) then
		return
	end
	table.insert(aInsQueue, {hash, channel, time, talker, text, msg})
end

function DeleteMsg(hash, time)
	if not time or empty(hash) then
		return
	end
	table.insert(aDelQueue, {hash, time})
end

function OptimizeDB(deep)
	if not DB then
		return
	end
	local tables = {}
	local result = DB:Execute("SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'ChatLog/_%/_%' ESCAPE '/' ORDER BY name")
	for _, rec in ipairs(result) do
		tinsert(tables, {
			name  = rec.name,
			stime = tonumber((rec.name:sub(9):gsub("_.*", ""))),
 			etime = tonumber((rec.name:sub(9):gsub(".*_", ""))),
			count = DB:Execute("SELECT count(*) AS count FROM " .. rec.name)[1].count,
		})
	end
	table.sort(tables, function(a, b) return a.stime < b.stime end)
	
	DB:Execute("BEGIN TRANSACTION")
	-- 拆历史记录中的大表（如果存在）
	if deep then
		for i, info in ipairs(tables) do
			if info.count > DIVIDE_TABLE_AMOUNT then
				local etime = DB:Execute("SELECT time FROM " .. info.name .. " ORDER BY time ASC LIMIT 1 OFFSET " .. (SINGLE_TABLE_AMOUNT - 1))[1].time
				local newinfo = {
					name  = "ChatLog_" .. info.stime .. "_" .. etime,
					stime = info.stime,
		 			etime = etime,
				}
				tinsert(tables, i, newinfo)
				CreateTable(newinfo.name)
				DB:Execute("REPLACE INTO " .. newinfo.name .. " SELECT * FROM " .. info.name .. " WHERE time <= " .. etime)
				DB:Execute("DELETE FROM " .. info.name .. " WHERE time <= " .. etime)
				newinfo.count = DB:Execute("SELECT count(*) AS count FROM " .. newinfo.name)[1].count
				info.count = DB:Execute("SELECT count(*) AS count FROM " .. info.name)[1].count
				
				local oldname = info.name
				info.name = "ChatLog_" .. (etime + 1) .. "_" .. info.etime
				RenameTable(oldname, info.name)
			end
		end
	end
	
	-- 拆当前记录的ChatLog表（如果超长）
	local count = DB:Execute("SELECT count(*) AS count FROM ChatLog")[1].count
	if count > DIVIDE_TABLE_AMOUNT then
		local stime, etime = #tables > 0 and (tables[#tables].etime + 1) or 0, 0
		local index = SINGLE_TABLE_AMOUNT
		while index < count do
			etime = DB:Execute("SELECT time FROM ChatLog ORDER BY time ASC LIMIT 1 OFFSET " .. (index - 1))[1].time
			local name = "ChatLog_" .. stime .. "_" .. etime
			CreateTable(name)
			DB:Execute("REPLACE INTO " .. name .. " SELECT * FROM ChatLog WHERE time <= " .. etime .. " AND time >= " .. stime)
			
			stime = etime + 1
			index = index + SINGLE_TABLE_AMOUNT
		end
		DB:Execute("DELETE FROM ChatLog WHERE time <= " .. etime)
	end
	DB:Execute("END TRANSACTION")
	
	if deep then
		DB:Execute("VACUUM")
	end
	UpdateSTMTs()
end

function PushDB()
	if #aInsQueue == 0 and #aDelQueue == 0 then
		return
	elseif not DB then
		return MY.Debug({"Database has not been initialized yet, PushDB failed."}, "MY_ChatLog", MY_DEBUG.ERROR)
	end
	DB:Execute("BEGIN TRANSACTION")
	for _, data in ipairs(aInsQueue) do
		for _, stmt in ipairs_r(STMT) do
			if data[3] >= stmt.stime then
				stmt.W:ClearBindings()
				stmt.W:BindAll(unpack(data))
				stmt.W:Execute()
				break
			end
		end
	end
	aInsQueue = {}
	for _, data in ipairs(aDelQueue) do
		for _, stmt in ipairs_r(STMT) do
			if data[2] >= stmt.stime then
				stmt.D:ClearBindings()
				stmt.D:BindAll(unpack(data))
				stmt.D:Execute()
				break
			end
		end
	end
	aDelQueue = {}
	DB:Execute("END TRANSACTION")
	-- 重建缓存记录 自动分表
	OptimizeDB(false)
end

function GetChatLogCount(channels, keyword)
	local count = 0
	for _, stmt in ipairs(STMT) do
		if not stmt.count.filter[keyword] then
			UpdateSTMTCountCache(stmt, keyword)
		end
		for _, channel in ipairs(channels) do
			if stmt.count.filter[keyword][channel] then
				count = count + stmt.count.filter[keyword][channel]
			end
		end
	end
	return count
end

function GetChatLog(channels, search, offset, limit)
	local DB_R, wheres, values = nil, {}, {}
	for _, channel in ipairs(channels) do
		tinsert(wheres, "channel = ?")
		tinsert(values, channel)
	end
	local sql  = ""
	local where = ""
	if #wheres > 0 then
		where = where .. " (" .. tconcat(wheres, " OR ") .. ")"
	else
		where = " 1 = 0"
	end
	if search ~= "" then
		if #where > 0 then
			where = where .. " AND"
		end
		where = where .. " (talker LIKE ? OR text LIKE ?)"
		tinsert(values, AnsiToUTF8("%" .. search .. "%"))
		tinsert(values, AnsiToUTF8("%" .. search .. "%"))
	end
	if #where > 0 then
		sql  = sql .. " WHERE" .. where
	end
	tinsert(values, limit)
	tinsert(values, offset)
	sql = sql .. " ORDER BY time ASC LIMIT ? OFFSET ?"
	
	local index, count, result, data = 0, 0, {}, nil
	for _, stmt in ipairs(STMT) do
		if limit == 0 then
			break
		end
		if not stmt.count.filter[search] then
			UpdateSTMTCountCache(stmt, search)
		end
		count = 0
		for _, channel in ipairs(channels) do
			if stmt.count.filter[search][channel] then
				count = count + stmt.count.filter[search][channel]
			end
		end
		if index <= offset and index + count > offset then
			DB_R = DB:Prepare("SELECT * FROM " .. stmt.name .. sql)
			DB_R:ClearBindings()
			values[#values - 1] = limit
			values[#values] = mmax(offset - index, 0)
			DB_R:BindAll(unpack(values))
			data = DB_R:GetAll()
			for _, rec in ipairs(data) do
				tinsert(result, rec)
			end
			limit = limit - #data
		end
		index = index + count
	end
	
	return result
end

local function InitDB()
	local DB_PATH = MY.FormatPath('$uid@$lang/userdata/chat_log.db')
	local SZ_OLD_PATH = MY.FormatPath('userdata/CHAT_LOG/$uid.db')
	if IsLocalFileExist(SZ_OLD_PATH) then
		CPath.Move(SZ_OLD_PATH, DB_PATH)
	end
	DB = SQLite3_Open(DB_PATH)
	if not DB then
		return MY.Debug({"Cannot connect to database!!!"}, "MY_ChatLog", MY_DEBUG.ERROR)
	end
	UpdateSTMTs()
	local me = GetClientPlayer()
	DB:Execute("CREATE TABLE IF NOT EXISTS ChatLogUser (userguid INTEGER, PRIMARY KEY (userguid))")
	DB:Execute("REPLACE INTO ChatLogUser (userguid) VALUES (" .. me.GetGlobalID() .. ")")
	
	local SZ_OLD_PATH = MY.FormatPath('userdata/CHAT_LOG/$uid/') -- %s/%s.$lang.jx3dat
	if IsLocalFileExist(SZ_OLD_PATH) then
		local nScanDays = 365 * 3
		local nDailySec = 24 * 3600
		local date = TimeToDate(GetCurrentTime())
		local dwEndedTime = GetCurrentTime() - date.hour * 3600 - date.minute * 60 - date.second
		local dwStartTime = dwEndedTime - nScanDays * nDailySec
		local nHour, nMin, nSec
		local function regexp(...)
			nHour, nMin, nSec = ...
			return ""
		end
		local szTalker
		local function regexpN(...)
			szTalker = ...
		end
		for _, szChannel in ipairs({"MSG_WHISPER", "MSG_PARTY", "MSG_TEAM", "MSG_FRIEND", "MSG_GUILD", "MSG_GUILD_ALLIANCE"}) do
			local SZ_CHANNEL_PATH = SZ_OLD_PATH .. szChannel .. "/"
			if IsLocalFileExist(SZ_CHANNEL_PATH) then
				for dwTime = dwStartTime, dwEndedTime, nDailySec do
					local szDate = MY.FormatTime("yyyyMMdd", dwTime)
					local data = MY.LoadLUAData(SZ_CHANNEL_PATH .. szDate .. '.$lang.jx3dat')
					if data then
						for _, szMsg in ipairs(data) do
							nHour, nMin, nSec, szTalker = nil
							szMsg = szMsg:gsub('<text>text="%[(%d+):(%d+):(%d+)%]".-</text>', regexp)
							szMsg:gsub('text="%[([^"<>]-)%]"[^<>]-name="namelink_', regexpN)
							if nHour and nMin and nSec and szTalker then
								InsertMsg(CHANNELS_R[szChannel], GetPureText(szMsg), szMsg, szTalker, dwTime + nHour * 3600 + nMin * 60 + nSec)
							end
						end
					end
				end
			end
		end
		PushDB()
		CPath.DelDir(SZ_OLD_PATH)
	end
	
	do
		local t = {}
		for nChannel, szChannel in pairs(CHANNELS) do
			tinsert(t, szChannel)
		end
		local function OnMsg(szMsg, nFont, bRich, r, g, b, szChannel, dwTalkerID, szTalker)
			local szText = szMsg
			if bRich then
				szText = GetPureText(szMsg)
			else
				szMsg = GetFormatText(szMsg, nFont, r, g, b)
			end
			-- filters
			if szChannel == "MSG_GUILD" then
				if MY_ChatLog.bIgnoreTongOnlineMsg and szText:find(TONG_ONLINE_MSG) then
					return
				end
				if MY_ChatLog.bIgnoreTongMemberLogMsg and (
					szText:find(TONG_MEMBER_LOGIN_MSG) or szText:find(TONG_MEMBER_LOGOUT_MSG)
				) then
					return
				end
			end
			InsertMsg(CHANNELS_R[szChannel], szText, szMsg, szTalker, GetCurrentTime())
		end
		MY.RegisterMsgMonitor('MY_ChatLog', OnMsg, t)
	end
	MY.RegisterEvent("LOADING_ENDING.MY_ChatLog_Save", PushDB)
end
MY.RegisterInit("MY_ChatLog_Init", InitDB)

local function ReleaseDB()
	if not DB then
		return
	end
	PushDB()
	DB:Release()
end
MY.RegisterExit("MY_Chat_Release", ReleaseDB)
end

function MY_ChatLog.Open()
	if not DB then
		return MY.Sysmsg({_L['Cannot connect to database!!!'], r = 255, g = 0, b = 0}, _L['MY_ChatLog'])
	end
	Wnd.OpenWindow(SZ_INI, "MY_ChatLog"):BringToTop()
end

function MY_ChatLog.Close()
	Wnd.CloseWindow("MY_ChatLog")
end

function MY_ChatLog.IsOpened()
	return Station.Lookup("Normal/MY_ChatLog")
end

function MY_ChatLog.Toggle()
	if MY_ChatLog.IsOpened() then
		MY_ChatLog.Close()
	else
		MY_ChatLog.Open()
	end
end

function MY_ChatLog.OnFrameCreate()
	if type(MY_ChatLog.tUncheckedChannel) ~= "table" then
		MY_ChatLog.tUncheckedChannel = {}
	end
	local container = this:Lookup("Window_Main/WndScroll_ChatChanel/WndContainer_ChatChanel")
	container:Clear()
	for _, info in pairs(LOG_TYPE) do
		local wnd = container:AppendContentFromIni(SZ_INI, "Wnd_ChatChannel")
		wnd.id = info.id
		wnd.aChannels = info.channels
		wnd:Lookup("CheckBox_ChatChannel"):Check(not MY_ChatLog.tUncheckedChannel[info.id], WNDEVENT_FIRETYPE.PREVENT)
		wnd:Lookup("CheckBox_ChatChannel", "Text_ChatChannel"):SetText(info.title)
		wnd:Lookup("CheckBox_ChatChannel", "Text_ChatChannel"):SetFontColor(GetMsgFontColor(info.channels[1]))
	end
	container:FormatAllContentPos()
	
	local handle = this:Lookup("Window_Main/Wnd_Index", "Handle_IndexesOuter/Handle_Indexes")
	handle:Clear()
	for i = 1, PAGE_DISPLAY do
		handle:AppendItemFromIni(SZ_INI, "Handle_Index")
	end
	handle:FormatAllItemPos()
	
	local handle = this:Lookup("Window_Main/WndScroll_ChatLog", "Handle_ChatLogs")
	handle:Clear()
	for i = 1, PAGE_AMOUNT do
		handle:AppendItemFromIni(SZ_INI, "Handle_ChatLog")
	end
	handle:FormatAllItemPos()
	
	this:Lookup("", "Text_Title"):SetText(_L['MY - MY_ChatLog'])
	this:Lookup("Window_Main/Wnd_Search/Edit_Search"):SetPlaceholderText(_L['press enter to search ...'])
	
	MY_ChatLog.UpdatePage(this)
	this:RegisterEvent("ON_MY_MOSAICS_RESET")
	
	this:SetPoint("CENTER", 0, 0, "CENTER", 0, 0)
end

function MY_ChatLog.OnEvent(event)
	if event == "ON_MY_MOSAICS_RESET" then
		MY_ChatLog.UpdatePage(this, true)
	end
end

function MY_ChatLog.OnLButtonClick()
	local name = this:GetName()
	if name == "Btn_Close" then
		MY_ChatLog.Close()
	elseif name == "Btn_Only" then
		local wnd = this:GetParent()
		local parent = wnd:GetParent()
		for i = 0, parent:GetAllContentCount() - 1 do
			local wnd = parent:LookupContent(i)
			wnd:Lookup("CheckBox_ChatChannel"):Check(false, WNDEVENT_FIRETYPE.PREVENT)
		end
		wnd:Lookup("CheckBox_ChatChannel"):Check(true)
	end
end

function MY_ChatLog.OnCheckBoxCheck()
	this:GetRoot().nCurrentPage = nil
	MY_ChatLog.UpdatePage(this:GetRoot())
end

function MY_ChatLog.OnCheckBoxUncheck()
	this:GetRoot().nCurrentPage = nil
	MY_ChatLog.UpdatePage(this:GetRoot())
end

function MY_ChatLog.OnItemLButtonClick()
	local name = this:GetName()
	if name == "Handle_Index" then
		this:GetRoot().nCurrentPage = this.nPage
		MY_ChatLog.UpdatePage(this:GetRoot())
	end
end

function MY_ChatLog.OnEditSpecialKeyDown()
	local name = this:GetName()
	local frame = this:GetRoot()
	local szKey = GetKeyName(Station.GetMessageKey())
	if szKey == "Enter" then
		if name == "WndEdit_Index" then
			frame.nCurrentPage = tonumber(this:GetText()) or frame.nCurrentPage
		end
		MY_ChatLog.UpdatePage(this:GetRoot())
		return 1
	end
end

function MY_ChatLog.OnItemRButtonClick()
	local this = this
	local name = this:GetName()
	if name == "Handle_ChatLog" then
		local menu = {
			{
				szOption = _L["delete record"],
				fnAction = function()
					DeleteMsg(this.hash, this.time)
					MY_ChatLog.UpdatePage(this:GetRoot(), true)
				end,
			}, {
				szOption = _L["copy this record"],
				fnAction = function()
					MY.Chat.CopyChatLine(this:Lookup("Handle_ChatLog_Msg"):Lookup(0), true)
				end,
			}
		}
		PopupMenu(menu)
	end
end

function MY_ChatLog.UpdatePage(frame, noscroll)
	PushDB()
	
	local container = frame:Lookup("Window_Main/WndScroll_ChatChanel/WndContainer_ChatChanel")
	local channels = {}
	for i = 0, container:GetAllContentCount() - 1 do
		local wnd = container:LookupContent(i)
		if wnd:Lookup("CheckBox_ChatChannel"):IsCheckBoxChecked() then
			for _, szChannel in ipairs(wnd.aChannels) do
				tinsert(channels, CHANNELS_R[szChannel])
			end
			MY_ChatLog.tUncheckedChannel[wnd.id] = nil
		else
			MY_ChatLog.tUncheckedChannel[wnd.id] = true
		end
	end
	local search = frame:Lookup("Window_Main/Wnd_Search/Edit_Search"):GetText()
	
	local nCount = GetChatLogCount(channels, search)
	local nPageCount = mceil(nCount / PAGE_AMOUNT)
	local bInit = not frame.nCurrentPage
	if bInit then
		frame.nCurrentPage = nPageCount
	else
		frame.nCurrentPage = mmin(mmax(frame.nCurrentPage, 1), nPageCount)
	end
	frame:Lookup("Window_Main/Wnd_Index/Wnd_IndexEdit/WndEdit_Index"):SetText(frame.nCurrentPage)
	frame:Lookup("Window_Main/Wnd_Index", "Handle_IndexCount/Text_IndexCount"):SprintfText(_L["total %d pages"], nPageCount)
	
	local hOuter = frame:Lookup("Window_Main/Wnd_Index", "Handle_IndexesOuter")
	local handle = hOuter:Lookup("Handle_Indexes")
	if nPageCount <= PAGE_DISPLAY then
		for i = 0, PAGE_DISPLAY - 1 do
			local hItem = handle:Lookup(i)
			hItem.nPage = i + 1
			hItem:Lookup("Text_Index"):SetText(i + 1)
			hItem:Lookup("Text_IndexUnderline"):SetVisible(i + 1 == frame.nCurrentPage)
			hItem:SetVisible(i < nPageCount)
		end
	else
		local hItem = handle:Lookup(0)
		hItem.nPage = 1
		hItem:Lookup("Text_Index"):SetText(1)
		hItem:Lookup("Text_IndexUnderline"):SetVisible(1 == frame.nCurrentPage)
		hItem:Show()
		
		local hItem = handle:Lookup(PAGE_DISPLAY - 1)
		hItem.nPage = nPageCount
		hItem:Lookup("Text_Index"):SetText(nPageCount)
		hItem:Lookup("Text_IndexUnderline"):SetVisible(nPageCount == frame.nCurrentPage)
		hItem:Show()
		
		local nStartPage
		if frame.nCurrentPage + mceil((PAGE_DISPLAY - 2) / 2) > nPageCount then
			nStartPage = nPageCount - (PAGE_DISPLAY - 2)
		elseif frame.nCurrentPage - mceil((PAGE_DISPLAY - 2) / 2) < 2 then
			nStartPage = 2
		else
			nStartPage = frame.nCurrentPage - mceil((PAGE_DISPLAY - 2) / 2)
		end
		for i = 1, PAGE_DISPLAY - 2 do
			local hItem = handle:Lookup(i)
			hItem.nPage = nStartPage + i - 1
			hItem:Lookup("Text_Index"):SetText(nStartPage + i - 1)
			hItem:Lookup("Text_IndexUnderline"):SetVisible(nStartPage + i - 1 == frame.nCurrentPage)
			hItem:SetVisible(true)
		end
	end
	handle:SetSize(hOuter:GetSize())
	handle:FormatAllItemPos()
	handle:SetSizeByAllItemSize()
	hOuter:FormatAllItemPos()
	
	local data = GetChatLog(channels, search, (frame.nCurrentPage - 1) * PAGE_AMOUNT, PAGE_AMOUNT)
	local scroll = frame:Lookup("Window_Main/WndScroll_ChatLog/Scroll_ChatLog")
	local handle = frame:Lookup("Window_Main/WndScroll_ChatLog", "Handle_ChatLogs")
	for i = 1, PAGE_AMOUNT do
		local rec = data[i]
		local hItem = handle:Lookup(i - 1)
		if rec then
			local f = GetMsgFont(CHANNELS[rec.channel])
			local r, g, b = GetMsgFontColor(CHANNELS[rec.channel])
			local h = hItem:Lookup("Handle_ChatLog_Msg")
			h:Clear()
			h:AppendItemFromString(MY.GetTimeLinkText({r=r, g=g, b=b, f=f, s='[yyyy/MM/dd][hh:mm:ss]'}, rec.time))
			local nCount = h:GetItemCount()
			h:AppendItemFromString(UTF8ToAnsi(rec.msg))
			for i = nCount, h:GetItemCount() - 1 do
				MY.RenderChatLink(h:Lookup(i))
			end
			if MY_Farbnamen and MY_Farbnamen.Render then
				for i = nCount, h:GetItemCount() - 1 do
					MY_Farbnamen.Render(h:Lookup(i))
				end
			end
			if MY_ChatMosaics and MY_ChatMosaics.Mosaics then
				MY_ChatMosaics.Mosaics(h)
			end
			h:FormatAllItemPos()
			local nW, nH = h:GetAllItemSize()
			h:SetH(nH)
			hItem:Lookup("Shadow_ChatLogBg"):SetH(nH + 3)
			hItem:SetH(nH + 3)
			hItem.hash = rec.hash
			hItem.time = rec.time
			hItem.text = rec.text
			hItem:Show()
		else
			hItem:Hide()
		end
	end
	handle:FormatAllItemPos()
	
	if not noscroll then
		scroll:SetScrollPos(bInit and scroll:GetStepCount() or 0)
	end
end

------------------------------------------------------------------------------------------------------
-- 数据导出
------------------------------------------------------------------------------------------------------
local function htmlEncode(html)
	return html
	:gsub("&", "&amp;")
	:gsub(" ", "&ensp;")
	:gsub("<", "&lt;")
	:gsub(">", "&gt;")
	:gsub('"', "&quot;")
	:gsub("\n", "<br>")
end

local function getHeader()
	local szHeader = [[<!DOCTYPE html>
<html>
<head><meta http-equiv="Content-Type" content="text/html; charset=]]
	.. ((MY.GetLang() == "zhcn" and "GBK") or "UTF-8") .. [[" />
<style>
*{font-size: 12px}
a{line-height: 16px}
input, button, select, textarea {outline: none}
body{background-color: #000; margin: 8px 8px 45px 8px}
#browserWarning{background-color: #f00; font-weight: 800; color:#fff; padding: 8px; position: fixed; opacity: 0.92; top: 0; left: 0; right: 0}
.channel{color: #fff; font-weight: 800; font-size: 32px; padding: 0; margin: 30px 0 0 0}
.date{color: #fff; font-weight: 800; font-size: 24px; padding: 0; margin: 0}
a.content{font-family: cursive}
span.emotion_44{width:21px; height: 21px; display: inline-block; background-image: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAABUAAAAVCAYAAACpF6WWAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAO/SURBVDhPnZT7U4xRGMfff4GftEVKYsLutkVETKmsdrtY9QMNuTRDpVZS2Fw2utjcL1NSYaaUa5gRFSK5mzFukzHGYAbjOmTC7tv79vWcs2+bS7k9M985u+c953PO85zneYS+zBQThYChKvj7ejg1zDnqfN1hipkKZdnfmXFKKLRD3aHXecMyPQh1q+PRVr4Qj2qycKZkAfLmRyJitA80tCaa1irb+rZR3m4I9huIgsQQvKxKxZemXEgNuZAvrIPcWoSuqzbYH5bhcZMV6fHjETjcA6OGuPUNHuk9AJM1g3E4IxId9TnwcuvHJV0phHQuD9L5fODFPtf8mwcV2JIVg4kab6h9VL+Co/VhGOOrQlnSBHQcWeyE3SqG1JKHzoaVkC4WQr68HniyGUAb6QFf86FtC0qzTRhL3kVPCfsRrKGTUsNH4lX5PDiOLoZ0yQrpzCoOlW9uoLGAu4/2cgK2kC6QGiG9rsCr5gKkm8ZBTTFWcIIQH2dAyHAV7q+d5nLNJVV/Psq3NkO+RNC3lb+s8VHWBNFtE4jFJGgolsmhfnheZKTTfzS2WL6/3XlTcr/r3iYC71S+Oo2teXfdhjlTAzDCawCXwNJnx8xgvC9Jgrg7EfZ98yAeSoGjLt3p+lkrZHp1+cp6GosJbkPXnXwuudWKLjpUvJiPvctMPM2YBH9K5pZsPeyls2HfkwzHQTPE49nobFrNX12+pgC/1zUGL+r5T6G5uyfNVSgcejs3CvYSgu4laFUKxBM5Lih3/Xtgb2otxNOaJdBR1TFxaIM5nG6ahK9lc+HYnwbxSCbE+hWQmtf+GcpCQ/FuLp7dc9MAHzdYo3X4vG0m7LuSYK+cD8eBDIinLehsZGn1E5QgbI6L8pd707gS62ZNhD+xmARTrAF69SA8sSX0hKA6tee2lJ+uh6L4MggrCHYgP5QOf1ebAUPgEGo0UVw8V1kGbEoYg090WwcVAH+wbvApBawAxZPLac7CH1Oi2H+py8LGWZN4E+KwbouibhOh8UR9Wjjat82Ao8IJ7jyYDrF6AaRTOUplkavHsyAezaRvZnRUL8KxpQZM8POAobeOFUClatB5oSY5BB+2Unx3z4FtSZyrcrply4ylmC/CRwoVaz562qP+XafS0MfgYSqsMGjxzGbiEPshCkMtpVkNSzUzn3tJYcqbFohJIzzA+oayvW8zUsdiVRHq5w6LUYvalDDcsBhxb00c6s2RyE8Igl7ryWPYq8u/s+nUGNTUF/xpM8tlLvqtJW9MscoL/6v9P1QQvgHonm5Hx/sAiwAAAABJRU5ErkJggg==")}
#controls{background-color: #fff; height: 25px; position: fixed; opacity: 0.92; bottom: 0; left: 0; right: 0}
#mosaics{width: 200px;height: 20px}
]]
	
	if MY_Farbnamen and MY_Farbnamen.GetForceRgb then
		for k, v in pairs(g_tStrings.tForceTitle) do
			szHeader = szHeader .. (".force-%s{color:#%02X%02X%02X}"):format(k, unpack(MY_Farbnamen.GetForceRgb(k)))
		end
	end

	szHeader = szHeader .. [[
</style></head>
<body>
<div id="browserWarning">Please allow running JavaScript on this page!</div>
<div id="controls" style="display:none">
	<input type="range" id="mosaics" min="0" max="200" value="0">
	<script type="text/javascript">
	(function() {
		var timerid, blurRadius;
		var setMosaicHandler = function() {
			var filter = "blur(" + blurRadius + ")";console.log(filter);
			var eles = document.getElementsByClassName("namelink");
			for(i = eles.length - 1; i >= 0; i--) {
				eles[i].style["filter"] = filter;
				eles[i].style["-o-filter"] = filter;
				eles[i].style["-ms-filter"] = filter;
				eles[i].style["-moz-filter"] = filter;
				eles[i].style["-webkit-filter"] = filter;
			}
			timerid = null;
		}
		var setMosaic = function(radius) {
			if (timerid)
				clearTimeout(timerid);
			blurRadius = radius;
			timerid = setTimeout(setMosaicHandler, 50);
		}
		document.getElementById("mosaics").oninput = function() {
			setMosaic((this.value / 100 + 0.5) + "px");
		}
	})();
	</script>
</div>
<script type="text/javascript">
	(function () {
		var Sys = {};
		var ua = navigator.userAgent.toLowerCase();
		var s;
		(s = ua.match(/rv:([\d.]+)\) like gecko/)) ? Sys.ie = s[1] :
		(s = ua.match(/msie ([\d.]+)/)) ? Sys.ie = s[1] :
		(s = ua.match(/firefox\/([\d.]+)/)) ? Sys.firefox = s[1] :
		(s = ua.match(/chrome\/([\d.]+)/)) ? Sys.chrome = s[1] :
		(s = ua.match(/opera.([\d.]+)/)) ? Sys.opera = s[1] :
		(s = ua.match(/version\/([\d.]+).*safari/)) ? Sys.safari = s[1] : 0;
		
		// if (Sys.ie) document.write('IE: ' + Sys.ie);
		// if (Sys.firefox) document.write('Firefox: ' + Sys.firefox);
		// if (Sys.chrome) document.write('Chrome: ' + Sys.chrome);
		// if (Sys.opera) document.write('Opera: ' + Sys.opera);
		// if (Sys.safari) document.write('Safari: ' + Sys.safari);
		
		if (!Sys.chrome && !Sys.firefox) {
			document.getElementById("browserWarning").innerHTML = "<a>WARNING: Please use </a><a href='http://www.google.cn/chrome/browser/desktop/index.html' style='color: yellow;'>Chrome</a></a> to browse this page!!!</a>";
		} else {
			document.getElementById("controls").style["display"] = null;
			document.getElementById("browserWarning").style["display"] = "none";
		}
	})();
</script>
<div>
<a style="color: #fff;margin: 0 10px">]] .. GetClientPlayer().szName .. " @ " .. MY.GetServer() ..
" Exported at " .. MY.FormatTime("yyyyMMdd hh:mm:ss", GetCurrentTime()) .. "</a><hr />"

	return szHeader
end

local function getFooter()
	return [[
</div>
</body>
</html>]]
end

local function getChannelTitle(szChannel)
	return [[<p class="channel">]] .. (g_tStrings.tChannelName[szChannel] or "") .. [[</p><hr />]]
end

local function getDateTitle(szDate)
	return [[<p class="date">]] .. (szDate or "") .. [[</p>]]
end

local function convertXml2Html(szXml)
	local aXml = MY.Xml.Decode(szXml)
	local t = {}
	if aXml then
		local text, name
		for _, xml in ipairs(aXml) do
			text = xml[''].text
			name = xml[''].name
			if text then
				local force
				text = htmlEncode(text)
				tinsert(t, '<a')
				if name and name:sub(1, 9) == "namelink_" then
					tinsert(t, ' class="namelink')
					if MY_Farbnamen and MY_Farbnamen.Get then
						local info = MY_Farbnamen.Get((text:gsub("[%[%]]", "")))
						if info then
							force = info.dwForceID
							tinsert(t, ' force-')
							tinsert(t, info.dwForceID)
						end
					end
					tinsert(t, '"')
				end
				if not force and xml[''].r and xml[''].g and xml[''].b then
					tinsert(t, (' style="color:#%02X%02X%02X"'):format(xml[''].r, xml[''].g, xml[''].b))
				end
				tinsert(t, '>')
				tinsert(t, text)
				tinsert(t, '</a>')
			elseif name and name:sub(1, 8) == "emotion_" then
				tinsert(t, '<span class="')
				tinsert(t, name)
				tinsert(t, '"></span>')
			end
		end
	end
	return tconcat(t)
end

local l_bExporting
function MY_ChatLog.ExportConfirm()
	if l_bExporting then
		return MY.Sysmsg({_L['Already exporting, please wait.']})
	end
	local ui = XGUI.CreateFrame("MY_ChatLog_Export", {
		simple = true, esc = true, close = true, w = 140,
		level = "Normal1", text = _L['export chatlog'], alpha = 233,
	})
	local btnSure
	local tChannels = {}
	local x, y = 10, 10
	for nGroup, info in ipairs(LOG_TYPE) do
		ui:append("WndCheckBox", {
			x = x, y = y, w = 100,
			text = info.title,
			checked = true,
			oncheck = function(checked)
				tChannels[nGroup] = checked
				if checked then
					btnSure:enable(true)
				else
					btnSure:enable(false)
					for nGroup, info in ipairs(LOG_TYPE) do
						if tChannels[nGroup] then
							btnSure:enable(true)
							break
						end
					end
				end
			end,
		})
		y = y + 30
		tChannels[nGroup] = true
	end
	y = y + 10
	
	btnSure = ui:append("WndButton", {
		x = x, y = y, w = 120,
		text = _L['export chatlog'],
		onclick = function()
			local aChannels = {}
			for nGroup, info in ipairs(LOG_TYPE) do
				if tChannels[nGroup] then
					for _, szChannel in ipairs(info.channels) do
						table.insert(aChannels, CHANNELS_R[szChannel])
					end
				end
			end
			MY_ChatLog.Export(
				MY.FormatPath({"export/ChatLog/$name@$server@" .. MY.FormatTime("yyyyMMddhhmmss") .. ".html", MY_DATA_PATH.ROLE}),
				aChannels, 10,
				function(title, progress)
					OutputMessage("MSG_ANNOUNCE_YELLOW", _L("Exporting chatlog: %s, %.2f%%.", title, progress * 100))
				end
			)
			ui:remove()
		end,
	}, true)
	y = y + 30
	ui:height(y + 50)
	ui:anchor({s = "CENTER", r = "CENTER", x = 0, y = 0})
end

function MY_ChatLog.Export(szExportFile, aChannels, nPerSec, onProgress)
	if l_bExporting then
		return MY.Sysmsg({_L['Already exporting, please wait.']})
	end
	if not DB then
		return MY.Sysmsg({_L['Cannot connect to database!!!']})
	end
	if onProgress then
		onProgress(_L["preparing"], 0)
	end
	local status =  Log(szExportFile, getHeader(), "clear")
	if status ~= "SUCCEED" then
		return MY.Sysmsg({_L("Error: open file error %s [%s]", szExportFile, status)})
	end
	l_bExporting = true
	
	local sql  = "SELECT * FROM ChatLog"
	local sqlc = "SELECT count(*) AS count FROM ChatLog"
	local wheres = {}
	local values = {}
	for _, nChannel in ipairs(aChannels) do
		tinsert(wheres, "channel = ?")
		tinsert(values, nChannel)
	end
	if #wheres > 0 then
		sql  = sql  .. " WHERE (" .. tconcat(wheres, " OR ") .. ")"
		sqlc = sqlc .. " WHERE (" .. tconcat(wheres, " OR ") .. ")"
	end
	sql  = sql  .. " ORDER BY time ASC"
	sqlc = sqlc .. " ORDER BY time ASC"
	local DB_RC = DB:Prepare(sqlc)
	DB_RC:BindAll(unpack(values))
	local data = DB_RC:GetNext()
	local nPageCount = mceil(data.count / EXPORT_SLICE)
	
	sql = sql .. " LIMIT " .. EXPORT_SLICE .. " OFFSET ?"
	local nIndex = #values + 1
	local DB_R = DB:Prepare(sql)
	local i = 0
	local function Export()
		if i > nPageCount then
			l_bExporting = false
			Log(szExportFile, getFooter(), "close")
			if onProgress then
				onProgress(_L['Export succeed'], 1)
			end
			local szFile = GetRootPath() .. szExportFile:gsub("/", "\\")
			MY.Alert(_L('Chatlog export succeed, file saved as %s', szFile))
			MY.Sysmsg({_L('Chatlog export succeed, file saved as %s', szFile)})
			return 0
		end
		values[nIndex] = i * EXPORT_SLICE
		DB_R:ClearBindings()
		DB_R:BindAll(unpack(values))
		local data = DB_R:GetAll()
		for i, rec in ipairs(data) do
			local f = GetMsgFont(CHANNELS[rec.channel])
			local r, g, b = GetMsgFontColor(CHANNELS[rec.channel])
			Log(szExportFile, convertXml2Html(MY.GetTimeLinkText({r=r, g=g, b=b, f=f, s='[yyyy/MM/dd][hh:mm:ss]'}, rec.time)))
			Log(szExportFile, convertXml2Html(UTF8ToAnsi(rec.msg)))
		end
		if onProgress then
			onProgress(_L['exporting'], i / nPageCount)
		end
		i = i + 1
	end
	MY.BreatheCall("MY_ChatLog_Export", Export)
end

------------------------------------------------------------------------------------------------------
-- 设置界面绘制
------------------------------------------------------------------------------------------------------
do
local menu = {
	szOption = _L["chat log"],
	fnAction = function() MY_ChatLog.Toggle() end,
}
MY.RegisterPlayerAddonMenu('MY_CHATLOG_MENU', menu)
MY.RegisterTraceButtonMenu('MY_CHATLOG_MENU', menu)
MY.Game.AddHotKey("MY_ChatLog", _L['chat log'], MY_ChatLog.Toggle, nil)
end

local PS = {}
function PS.OnPanelActive(wnd)
	local ui = MY.UI(wnd)
	local w, h = ui:size()
	local x, y = 50, 50
	local dy = 40
	local wr = 200
	
	ui:append("WndCheckBox", {
		x = x, y = y, w = wr,
		text = _L['filter tong member log message'],
		checked = MY_ChatLog.bIgnoreTongMemberLogMsg,
		oncheck = function(bChecked)
			MY_ChatLog.bIgnoreTongMemberLogMsg = bChecked
		end
	})
	y = y + dy
	
	ui:append("WndCheckBox", {
		x = x, y = y, w = wr,
		text = _L['filter tong online message'],
		checked = MY_ChatLog.bIgnoreTongOnlineMsg,
		oncheck = function(bChecked)
			MY_ChatLog.bIgnoreTongOnlineMsg = bChecked
		end
	})
	y = y + dy
	
	ui:append("WndButton", {
		x = x, y = y, w = 150,
		text = _L["export chatlog"],
		onclick = function()
			MY_ChatLog.ExportConfirm()
		end,
	})
	y = y + dy
	
	ui:append("WndButton", {
		x = x, y = y, w = 150,
		text = _L["open chatlog"],
		onclick = function()
			MY_ChatLog.Open()
		end,
	})
	y = y + dy
	
	ui:append("WndButton", {
		x = x, y = y, w = 150,
		text = _L["optimize/compress datebase"],
		onclick = function()
			OptimizeDB(true)
		end,
	})
	y = y + dy
end
MY.RegisterPanel( "ChatLog", _L["chat log"], _L['Chat'], "ui/Image/button/SystemButton.UITex|43", {255,127,0,200}, PS)
