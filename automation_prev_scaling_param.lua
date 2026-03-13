-- AutomationPrevScalingParam: reads/writes the scaling of the previous automation point.
--
-- Config:
--   get_automation_and_prev_point  (function)  (param) -> automation, prev_point

local AutomationPrevScalingParam = {}

function AutomationPrevScalingParam.new(config)
    local get_prev = config.get_automation_and_prev_point

    return {
        getter = function(automation_parameter)
            local automation, prev_point = get_prev(automation_parameter)
            if not automation or not prev_point then
                return 64
            end

            local scaling = prev_point.scaling
            local normalized_scaling = (scaling + 1.0) / 2.0
            return math.floor(math.max(0, math.min(1, normalized_scaling)) * 127 + 0.5)
        end,

        setter = function(automation_parameter, value, _)
            if not automation_parameter then
                return
            end

            local automation, prev_point = get_prev(automation_parameter)
            if not automation or not prev_point then
                return
            end

            local normalized_value = value / 127
            local scaling_value = (normalized_value * 2.0) - 1.0

            local prev_time = prev_point.time
            local prev_value = prev_point.value
            automation:remove_point_at(prev_time)
            automation:add_point_at(prev_time, prev_value, scaling_value)
        end,

        min_value     = function(_) return 0   end,
        max_value     = function(_) return 127 end,
        is_absent     = function(_) return false end,
        default_value = function(_) return 64  end,
    }
end

return AutomationPrevScalingParam
