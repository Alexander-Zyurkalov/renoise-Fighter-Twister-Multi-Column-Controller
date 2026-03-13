-- AutomationScalingParam: reads/writes the scaling of the automation point at the current line.
--
-- Config:
--   get_automation_and_point  (function)  (param) -> automation, point
--   create_or_get_automation  (function)  (param) -> automation

local AutomationScalingParam = {}
AutomationScalingParam.__index = AutomationScalingParam

function AutomationScalingParam.new(config)
    local self = setmetatable({}, AutomationScalingParam)
    self.get_automation_and_point = config.get_automation_and_point
    self.create_or_get_automation = config.create_or_get_automation
    return self
end

function AutomationScalingParam:getter(automation_parameter)
    local automation, point = self.get_automation_and_point(automation_parameter)
    if not automation or not point then
        return 0
    end

    local scaling = point.scaling
    local normalized_scaling = (scaling + 1.0) / 2.0
    return math.floor(math.max(0, math.min(1, normalized_scaling)) * 127 + 0.5)
end

function AutomationScalingParam:setter(automation_parameter, value, _)
    if not automation_parameter then
        return
    end

    local automation = self.create_or_get_automation(automation_parameter)
    if not automation then
        return
    end

    local song = renoise.song()
    local line = song.selected_line_index

    local normalized_value = value / 127
    local scaling_value = (normalized_value * 2.0) - 1.0

    local current_point_value = 0.5
    if automation:has_point_at(line) then
        for _, point in ipairs(automation.points) do
            if point.time == line then
                current_point_value = point.value
                break
            end
        end
        automation:remove_point_at(line)
    end

    automation:add_point_at(line, current_point_value, scaling_value)
end

function AutomationScalingParam:min_value()
    return 0
end

function AutomationScalingParam:max_value()
    return 127
end

function AutomationScalingParam:is_absent()
    return false
end

function AutomationScalingParam:default_value()
    return 64
end

return AutomationScalingParam