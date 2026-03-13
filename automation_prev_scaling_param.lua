-- AutomationPrevScalingParam: reads/writes the scaling of the previous automation point.
--
-- Config:
--   get_automation_and_prev_point  (function)  (param) -> automation, prev_point
local AutomationPrevScalingParam = {}
AutomationPrevScalingParam.__index = AutomationPrevScalingParam

local AutomationHelpers = require("automation_helpers")

function AutomationPrevScalingParam.new()
    local self = setmetatable({}, AutomationPrevScalingParam)
    return self
end

function AutomationPrevScalingParam:getter(automation_parameter)
    local automation, prev_point = AutomationHelpers.get_automation_and_prev_point(automation_parameter)
    if not automation or not prev_point then
        return 64
    end

    local scaling = prev_point.scaling
    local normalized_scaling = (scaling + 1.0) / 2.0
    return math.floor(math.max(0, math.min(1, normalized_scaling)) * 127 + 0.5)
end

function AutomationPrevScalingParam:setter(automation_parameter, value, _)
    if not automation_parameter then
        return
    end

    local automation, prev_point = AutomationHelpers.get_automation_and_prev_point(automation_parameter)
    if not automation or not prev_point then
        return
    end

    local normalized_value = value / 127
    local scaling_value = (normalized_value * 2.0) - 1.0

    local prev_time = prev_point.time
    local prev_value = prev_point.value
    automation:remove_point_at(prev_time)
    automation:add_point_at(prev_time, prev_value, scaling_value)
end

function AutomationPrevScalingParam:min_value()
    return 0
end

function AutomationPrevScalingParam:max_value()
    return 127
end

function AutomationPrevScalingParam:is_absent()
    return false
end

function AutomationPrevScalingParam:default_value()
    return 64
end

return AutomationPrevScalingParam