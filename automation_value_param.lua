-- AutomationValueParam: reads/writes the automation point value at the current line.
--
-- Config:
--   get_automation_and_point  (function)  (param) -> automation, point
--   create_or_get_automation  (function)  (param) -> automation

local AutomationValueParam = {}

function AutomationValueParam.new(config)
    local get_point = config.get_automation_and_point
    local get_or_create = config.create_or_get_automation

    return {
        getter = function(automation_parameter)
            local automation, point = get_point(automation_parameter)
            if not automation or not point then
                return 0
            end

            local normalized_value = point.value
            return math.floor(normalized_value * 127 + 0.5) -- Scale to 0-127 range
        end,

        setter = function(automation_parameter, value, _)
            if not automation_parameter then
                return
            end

            -- Convert 0-127 value back to parameter range
            local normalized_value = value / 127

            -- Create or get automation
            local automation = get_or_create(automation_parameter)
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
        end,

        min_value     = function(_) return 0   end,
        max_value     = function(_) return 127 end,
        is_absent     = function(_) return false end,
        default_value = function(_) return 64  end, -- Middle value
    }
end

return AutomationValueParam
