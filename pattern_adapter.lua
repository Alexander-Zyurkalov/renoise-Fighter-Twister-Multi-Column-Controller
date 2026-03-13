-- Pattern Adapter
-- Adapts renoise.song() pattern-editing API for use by ColumnControls
-- Uses __index metatable pattern for OOP

local PatternAdapter = {}
PatternAdapter.__index = PatternAdapter

--- Create a new PatternAdapter
-- @param config table with:
--   automation_helpers - AutomationHelpers module (with get_all_track_automations, get_automation_and_prev_point)
function PatternAdapter.new(config)
    local self = setmetatable({}, PatternAdapter)
    self.automation_helpers = config.automation_helpers
    return self
end

function PatternAdapter:get_track()
    return renoise.song().selected_track
end

function PatternAdapter:get_selected_line()
    return renoise.song().selected_line
end

function PatternAdapter:get_selected_line_index()
    return renoise.song().selected_line_index
end

function PatternAdapter:set_selected_line_index(idx)
    renoise.song().selected_line_index = idx
end

function PatternAdapter:get_number_of_lines()
    return renoise.song().selected_pattern.number_of_lines
end

function PatternAdapter:is_edit_mode()
    return renoise.song().transport.edit_mode
end

function PatternAdapter:set_note_column_index(idx)
    renoise.song().selected_note_column_index = idx
end

function PatternAdapter:set_effect_column_index(idx)
    renoise.song().selected_effect_column_index = idx
end

function PatternAdapter:set_selection(line_index, column_index)
    local song = renoise.song()
    song.selection_in_pattern = {
        start_line = line_index,
        end_line = line_index,
        start_track = song.selected_track_index,
        end_track = song.selected_track_index,
        start_column = column_index,
        end_column = column_index,
    }
end

function PatternAdapter:supports_automation()
    return true
end

function PatternAdapter:enter_automation_view(param)
    if renoise.app().window.active_lower_frame ~= renoise.ApplicationWindow.LOWER_FRAME_TRACK_AUTOMATION then
        renoise.app().window.active_lower_frame = renoise.ApplicationWindow.LOWER_FRAME_TRACK_AUTOMATION
    end
    if param then
        renoise.song().selected_automation_parameter = param
    end
end

function PatternAdapter:get_all_automations()
    return self.automation_helpers.get_all_track_automations()
end

function PatternAdapter:get_automation_and_prev_point(param)
    return self.automation_helpers.get_automation_and_prev_point(param)
end

return PatternAdapter
