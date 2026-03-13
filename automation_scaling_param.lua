-- AutomationScalingParam: reads/writes the scaling of the automation point at the current line.
--
-- Config:
--   get_automation_and_point  (function)  (param) -> automation, point
--   create_or_get_automation  (function)  (param) -> automation

local AutomationScalingParam = {}

function AutomationScalingParam.new(config)
    local get_point = config.get_automation_and_point
    local get_or_create = config.create_or_get_automation

    return {
        getter = function(automation_parameter)
            local automation, point = get_point(automation_parameter)
            if not automation or not point then
                return 0
            end

            local scaling = point.scaling
            local normalized_scaling = (scaling + 1.0) / 2.0
            return math.floor(math.max(0, math.min(1, normalized_scaling)) * 127 + 0.5)
        end,

        setter = function(automation_parameter, value, _)
            if not automation_parameter then
                return
            end

            local automation = get_or_create(automation_parameter)
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
        end,

        min_value     = function(_) return 0   end,
        max_value     = function(_) return 127 end,
        is_absent     = function(_) return false end,
        default_value = function(_) return 64  end,
    }
end

return AutomationScalingParam
