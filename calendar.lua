-- GLOBALS: CalendarDB
if not LibStub then return end

local icon = LibStub('LibDBIcon-1.0')
local tip = LibStub('LibQTip-1.0')
local AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")

-- upvalues
local CloseEvent = C_Calendar.CloseEvent
local GetDate = C_Calendar.GetDate
local EventCanEdit = C_Calendar.EventCanEdit
local GetNumDayEvents = C_Calendar.GetNumDayEvents
local OpenEvent = C_Calendar.OpenEvent
local SetAbsMonth = C_Calendar.SetAbsMonth
local EasyMenu = EasyMenu
local OpenCalendar = OpenCalendar
local format = format

local _
local addonName, addonTable = ...
local L = addonTable.L

-- cache for events
local todaysEvents = {}
local upcomingEvents = {}
local tooltip

local obj = LibStub:GetLibrary('LibDataBroker-1.1'):NewDataObject('Broker_Calendar', {
  type = 'data source',
  icon = 'Interface\\AddOns\\Broker_Calendar\\icon',
})
local options
local calendar_events = {["CALENDAR_UPDATE_EVENT"]=1,["CALENDAR_NEW_EVENT"]=1,["CALENDAR_UPDATE_EVENT_LIST"]=1,["CALENDAR_UPDATE_INVITE_LIST"]=1}
local frame = CreateFrame('Frame')
frame:SetScript('OnEvent', function(self, event, ...)
	if calendar_events[event] then
		return self["CALENDAR_EVENTS"](event,...)
	elseif self[event] then
		return self[event](...)
	end
end)
frame:RegisterEvent('PLAYER_LOGIN')

local function formatDate(month, day, year)
  if not CalendarDB.format then
    CalendarDB.format = "D/M/Y"
  end
  local dateString = CalendarDB.format:gsub('D', format('%02d', day))
  dateString = dateString:gsub('M', format('%02d', month))

  if year ~= nil then
    dateString = dateString:gsub('Y', year)
  else
    dateString = dateString:gsub('Y', ''):gsub('^%W*(.*)', '%1'):gsub('(.-)%W*$', '%1')
  end
  return dateString
end

local function GetDate()
  local _, month, day, year = C_Calendar.GetDate();
  return formatDate(month, day, year)
end

local function populateOptions()
  options = {
    order = 1,
      type  = "group",
      name  = "Broker_Calendar",
      args  = {
        general = {
          order	= 1,
          type	= "group",
          name	= "global",
          args	= {
            divider1 = {
              order	= 1,
              type	= "description",
              name	= "",
            },
            format = {
              order	= 2,
              type 	= "input",
              name 	= L["DATE_FORMAT"],
              desc 	= L["DATE_FORMAT_DESC"],
              get 	= function() return CalendarDB.format end,
              set 	= function(info, value)
                CalendarDB.format = value
                obj.text = C_Calendar.GetDate()
              end,
            },
            divider2 = {
              order	= 3,
              type	= "description",
              name	= "",
            },
            minimap = {
              order = 4,
              type  = "toggle",
              name  = L["ATT_MINIMAP"],
              desc  = "",
              get 	= function() return not CalendarDB.minimap.hide end,
              set 	= function()
                local hide = not CalendarDB.minimap.hide
                CalendarDB.minimap.hide = hide
                if hide then
                  icon:Hide('Broker_Calendar')
                else
                  icon:Show('Broker_Calendar')
                end
              end,
            }
          }
        }
      }
  }
end

local function getStatus(status)
  if status == CALENDAR_INVITESTATUS_INVITED then
    return CALENDAR_STATUS_INVITED
  elseif status == CALENDAR_INVITESTATUS_ACCEPTED then
    return CALENDAR_STATUS_ACCEPTED
  elseif status == CALENDAR_INVITESTATUS_DECLINED then
    return CALENDAR_STATUS_DECLINED
  elseif status == CALENDAR_INVITESTATUS_CONFIRMED then
    return CALENDAR_STATUS_CONFIRMED
  elseif status == CALENDAR_INVITESTATUS_OUT then
    return CALENDAR_STATUS_OUT
  elseif status == CALENDAR_INVITESTATUS_STANDBY then
    return CALENDAR_STATUS_STANDBY
  elseif status == CALENDAR_INVITESTATUS_SIGNEDUP then
    return CALENDAR_STATUS_SIGNEDUP
  elseif status == CALENDAR_INVITESTATUS_NOT_SIGNEDUP then
    return CALENDAR_STATUS_NOT_SIGNEDUP
  elseif status == CALENDAR_INVITESTATUS_TENTATIVE then
    return CALENDAR_STATUS_TENTATIVE
  else
    return ''
  end
end

local function toggleEventRegistration(enable)
	if enable then
		for event in pairs(calendar_events) do
			frame:RegisterEvent(event)
		end
	else
		for event in pairs(calendar_events) do
			frame:UnregisterEvent(event)
		end
	end
end

local function populateEvents(day, month)
  -- today
  local numEvents = C_Calendar.GetNumDayEvents(0, day);
  if numEvents > 0 then
    local title, hour, minute, calendarType, sequenceType, inviteStatus, invitedBy
    for eventIndex = 1, numEvents do
      title, hour, minute, calendarType, sequenceType, _, _, _, inviteStatus, invitedBy = C_Calendar.GetDayEvent(0, day, eventIndex)

      if calendarType ~= 'RAID_LOCKOUT' and calendarType ~= 'RAID_RESET' and not (calendarType == 'HOLIDAY' and sequenceType == 'ONGOING') then
      	if calendarType == 'HOLIDAY' then
      		if sequenceType == 'START' then
      			inviteStatus = L['STARTS']
      		elseif sequenceType == 'END' then
      			inviteStatus = L['ENDS']
      		else
      			inviteStatus = getStatus(inviteStatus)
      		end
      	else
      		inviteStatus = getStatus(inviteStatus)
      	end
        todaysEvents[title] = {hour, minute, invitedBy, inviteStatus}
      end
    end
  end

  -- upcoming
  local numEvents, title, days
  local monthOffset = 0
  local daysInMonth = select(3, C_Calendar.GetMonthInfo())
  for dayOffset = 1, 7 do
    if day + dayOffset > daysInMonth then
      monthOffset = monthOffset + 1
      day = 1 - dayOffset
      daysInMonth = select(3, C_Calendar.GetMonthInfo(monthOffset))
    end

    numEvents = C_Calendar.GetNumDayEvents(monthOffset, day + dayOffset)
    if numEvents ~= 0 then
    	local title, hour, minute, calendarType, sequenceType, inviteStatus, invitedBy
      for eventIndex = 1, numEvents do
        title, hour, minute, calendarType, sequenceType, _, _, _, inviteStatus, invitedBy = C_Calendar.GetDayEvent(monthOffset, day + dayOffset, eventIndex)

        if calendarType == 'PLAYER' or
        (not upcomingEvents[title] and not todaysEvents[title] and calendarType ~= 'RAID_LOCKOUT' and calendarType ~= 'RAID_RESET' and not (calendarType == 'HOLIDAY' and sequenceType == 'ONGOING')) then
	        if calendarType == 'HOLIDAY' then
	      		if sequenceType == 'START' then
	      			inviteStatus = L['STARTS']
	      		elseif sequenceType == 'END' then
	      			inviteStatus = L['ENDS']
	      		else
      				inviteStatus = getStatus(inviteStatus)
	      		end
	      	else
	      		inviteStatus = getStatus(inviteStatus)
	      	end
          upcomingEvents[title] = {day + dayOffset, month + monthOffset, invitedBy, inviteStatus}
        end
      end
    end
  end

  local sortedEvents = {}
  for title, time in pairs(todaysEvents) do
    table.insert(sortedEvents, {title = title, hour = time[1], minute = time[2], by = time[3], status = time[4]})
  end

  if #sortedEvents > 1 then
    -- sort by start time
    table.sort(sortedEvents, function(a, b)
      if not a.hour or not b.hour then
        return
      elseif a.hour == b.hour then
        if a.minute == b.minute then
          return a.title < b.title
        else
          return a.minute < b.minute
        end
      else
        return a.hour < b.hour
      end
    end)
  end

  todaysEvents = CopyTable(sortedEvents)

  wipe(sortedEvents)
  for title, start in pairs(upcomingEvents) do
    table.insert(sortedEvents, {title = title, day = start[1], month = start[2], by = start[3], status = start[4]})
  end

  if #sortedEvents > 1 then
    -- sort by start time
    table.sort(sortedEvents, function(a, b)
      if not a.month or not b.month then
        return
      elseif a.month == b.month then
        if a.day == b.day then
          return a.title < b.title
        else
          return a.day < b.day
        end
      else
        return a.month < b.month
      end
    end)
  end

  upcomingEvents = CopyTable(sortedEvents)
  wipe(sortedEvents)
  toggleEventRegistration(true)
end

local function color(text, colorCode)
  local color
  if colorCode == 'y' then
    color = '|cffffd100'
  elseif colorCode == 'o' then
    color = '|cffe59933'
  end

  return format("%s%s|r",color,text)
end

local function showTodaysEvents()
  if #todaysEvents == 0 then
    tooltip:AddLine(L['NO_EVENTS_TODAY'])
  else
    tooltip:AddLine(
      color(L['TODAY'], 'y'),
      '',
      color(L['TIMES'], 'y')
    )

    for i = 1, #todaysEvents do
      if todaysEvents[i].hour then
      	local by = todaysEvents[i].by ~= '' and format(" (%s %s)",L['BY'],todaysEvents[i].by) or ''
      	local status = todaysEvents[i].status ~= '' and color(format(" - %s",todaysEvents[i].status),'o') or ''
        tooltip:AddLine(
          format("%s%s%s",todaysEvents[i].title,by,status),
          '',
          format("%02d:%02d",todaysEvents[i].hour,todaysEvents[i].minute)
        )
      end
    end
  end
end

local function showUpcomingEvents()
  if #upcomingEvents > 0 then
    tooltip:AddLine(' ')
    tooltip:AddLine(
      color(L['COMMING_SOON'], 'y'),
      '',
      color(L['DATES'], 'y')
    )

    for i = 1, #upcomingEvents do
      if upcomingEvents[i].day then
      	local by = upcomingEvents[i].by ~= '' and format(" (%s %s)",L['BY'],upcomingEvents[i].by) or ''
      	local status = upcomingEvents[i].status ~= '' and color(format(" - %s",upcomingEvents[i].status),'o') or ''
        tooltip:AddLine(
          format("%s%s%s",upcomingEvents[i].title,by,status),
          '',
          formatDate(upcomingEvents[i].month, upcomingEvents[i].day, nil)
        )
      end
    end
  end
end

local function toggleMinimap()
  local hide = not CalendarDB.minimap.hide
  CalendarDB.minimap.hide = hide
  if hide then
    icon:Hide('Broker_Calendar')
  else
    icon:Show('Broker_Calendar')
  end
end

function frame:ADDON_LOADED(addon)
	if addon == "Blizzard_Calendar" or addon == "Blizzard_GuildUI" then
		frame:UnregisterEvent("ADDON_LOADED")
		obj.text = C_Calendar.GetDate()
  	frame:CALENDAR_EVENTS()
	end
end

function frame:PLAYER_LOGIN()
  if not CalendarDB then
    CalendarDB = {}
    CalendarDB.minimap = {}
    CalendarDB.minimap.hide = false
    CalendarDB.version = 1
    CalendarDB.format = 'D/M/Y'
  end

  if icon then
    icon:Register('Broker_Calendar', obj, CalendarDB.minimap)
  end

  frame:UnregisterEvent('PLAYER_LOGIN')
	if IsAddOnLoaded("Blizzard_Calendar") or IsAddOnLoaded("Blizzard_GuildUI") then
  	obj.text = C_Calendar.GetDate()
  	frame:CALENDAR_EVENTS()
  else
  	local date_fmt = gsub(CalendarDB.format,'D','%%d')
  	date_fmt = gsub(date_fmt,'M','%%m')
  	date_fmt = gsub(date_fmt,'Y','%%Y')
  	obj.text = date(date_fmt)
  	frame:RegisterEvent("ADDON_LOADED")
  end

  populateOptions()
  AceConfigRegistry:RegisterOptionsTable("Broker_Calendar", options)
  AceConfigDialog:AddToBlizOptions("Broker_Calendar", nil, nil, "general")
end

-- fake cumulative event since they would all run the reload event code
function frame:CALENDAR_EVENTS(event,...)
  toggleEventRegistration(false)
	wipe(todaysEvents)
  wipe(upcomingEvents)

  local date = C_Calendar.GetDate();
  local wd,m,d,y = date.weekday, date.month, date.monthDay, date.year
  populateEvents(day, month)
end

function obj.OnClick(self, button)
  GameTooltip:Hide()
  GameTimeFrame_OnClick(GameTimeFrame)
end

function obj.OnLeave()
  tip:Release(tooltip)
end

function obj.OnEnter(self)
	if not IsAddOnLoaded("Blizzard_Calendar") then
		UIParentLoadAddOn("Blizzard_Calendar")
	end

  if #todaysEvents == 0 and #upcomingEvents == 0 then
    frame:CALENDAR_EVENTS()
  end

  tooltip = tip:Acquire('BrokerCalendarTooltip', 4, 'LEFT', 'RIGHT', 'RIGHT')
  local weekday, month, day, year = C_Calendar.GetDate()

  tooltip:AddHeader(
    color('Calendar', 'y'),
    '',
    color(C_Calendar.GetDate(), 'y'),
    ''
  )
  tooltip:AddLine(' ')

  showTodaysEvents()
  showUpcomingEvents()

  tooltip:SmartAnchorTo(self)
  tooltip:Show()
end
