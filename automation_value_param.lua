-- AutomationValueParam: reads/writes the automation point value at the current line.
--
-- Config:
--   get_automation_and_point  (function)  (param) -> automation, point
--   create_or_get_automation  (function)  (param) -> automation

local AutomationValueParam = {}
AutomationValueParam.__index = AutomationValueParam

local AutomationHelpers = require("automation_helpers")

function AutomationValueParam.new()
    local self = setmetatable({}, AutomationValueParam)
    return self
end

function AutomationValueParam:getter(automation_parameter)
    local automation, point = AutomationHelpers.get_automation_and_point(automation_parameter)
    if not automation or not point then
        return 0
    end

    local normalized_value = point.value
    return math.floor(normalized_value * 127 + 0.5) -- Scale to 0-127 range
end

function AutomationValueParam:setter(automation_parameter, value, _)
    if not automation_parameter then
        return
    end

    -- Convert 0-127 value back to parameter range
    local normalized_value = value / 127

    -- Create or get automation
    local automation = AutomationHelpers.create_or_get_automation(automation_parameter)
    if not automation then
        return
    end

    -- Add automation point at current line
    local song = renoise.song()
    local line = song.selected_line_index
    if automation:has_point_at(line) then
        automation:remove_point_at(line)
    end
    automation:add_point_at(line, normalized_value)
end

function AutomationValueParam:min_value(_)
    return 0
end

function AutomationValueParam:max_value(_)
    return 127
end

function AutomationValueParam:is_absent(_)
    return false
end

function AutomationValueParam:default_value(_)
    return 64 -- Middle value
end

return AutomationValueParam