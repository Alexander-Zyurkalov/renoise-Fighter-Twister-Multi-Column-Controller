-- Column Controls module
-- Manages dynamic CC-to-column mappings and MIDI controller state
-- Uses __index metatable pattern for OOP

local AutomationHelpers = require("automation_helpers")

local ColumnControls = {}
ColumnControls.__index = ColumnControls

--- Create a new ColumnControls instance
-- @param config table with:
--   available_ccs          - list of CC numbers to allocate
--   number_of_steps        - steps before value change triggers
--   column_params          - COLUMN_PARAMS hash-map
--   color_config           - table of color constants
--   send_midi_feedback     - function(cc, value)
--   send_color_feedback    - function(cc, color)
--   search_backwards       - function(song, is_effect, line_index, col_index, params)
function ColumnControls.new(config)
    local self = setmetatable({}, ColumnControls)

    -- Dependencies
    self.available_ccs = config.available_ccs
    self.number_of_steps = config.number_of_steps
    self.column_params = config.column_params
    self.colors = config.color_config
    self.send_midi_feedback = config.send_midi_feedback
    self.send_color_feedback = config.send_color_feedback
    self.search_backwards = config.search_backwards

    -- State
    self.controls = {}      -- CC -> control_info mapping
    self.last_controls = {} -- CC -> last message state

    return self
end

--- Get the appropriate color for a column type and value state
function ColumnControls:get_column_color(column_type, has_value, automation_parameter)
    local C = self.colors

    if column_type == "cursor" then
        return C.CURSOR_COLOR
    end

    if column_type == "automation" then
        if automation_parameter and automation_parameter.is_automated then
            return C.AUTOMATION_COLOR
        else
            return C.EMPTY_AUTOMATION_COLOR
        end
    elseif column_type == "automation_scaling" then
        if automation_parameter and automation_parameter.is_automated then
            return C.AUTOMATION_SCALING_COLOR
        else
            return C.EMPTY_AUTOMATION_COLOR
        end
    elseif column_type == "automation_prev_scaling" then
        if automation_parameter and automation_parameter.is_automated then
            local _, prev_point = AutomationHelpers.get_automation_and_prev_point(automation_parameter)
            if prev_point then
                return C.AUTOMATION_PREV_SCALING_COLOR
            else
                return C.EMPTY_AUTOMATION_COLOR
            end
        else
            return C.EMPTY_AUTOMATION_COLOR
        end
    end

    -- Note column fx params (red)
    local is_fx_type = column_type == "fx_number_xx" or column_type == "fx_number_yy"
            or column_type == "fx_amount_x" or column_type == "fx_amount_y"

    -- Effect column params (slightly different red)
    local is_effect_type = column_type == "effect_number_xx" or column_type == "effect_number_yy"
            or column_type == "effect_amount_x" or column_type == "effect_amount_y"

    if not has_value then
        if column_type == "note" then
            return C.EMPTY_NOTE_COLOR
        elseif is_fx_type then
            return C.EMPTY_FX_COLOR
        elseif is_effect_type then
            return C.EMPTY_EFFECT_COLOR
        else
            return C.EMPTY_COLOR
        end
    end

    if column_type == "note" then
        return C.NOTE_COLOR
    elseif is_fx_type then
        return C.FX_COLOR
    elseif is_effect_type then
        return C.EFFECT_COLOR
    else
        return C.OTHER_PARAM_COLOR
    end
end

--- Rebuild controls based on current track's visible columns
function ColumnControls:rebuild()
    local song = renoise.song()
    local track = song.selected_track

    -- Store old mappings before clearing
    local old_controls = {}
    for cc, control_info in pairs(self.controls) do
        old_controls[cc] = control_info
    end

    -- Build new mappings in temporary tables
    local new_controls = {}
    local new_last_controls = {}

    local cc_index = 1
    local num_visible_note_columns = track.visible_note_columns
    local num_visible_effect_columns = track.visible_effect_columns

    -- Assign first CC for cursor position control
    if cc_index <= #self.available_ccs then
        local cc = self.available_ccs[cc_index]
        new_controls[cc] = {
            type = "cursor",
            note_column_index = 1
        }
        new_last_controls[cc] = {
            command = 0,
            channel = 0,
            control_cc = 0,
            value = 0,
            count = 0,
            number_of_steps_to_change_value = self.number_of_steps,
        }
        cc_index = cc_index + 1
    end

    -- Assign CCs for all visible note columns
    for note_col_idx = 1, num_visible_note_columns do
        local column_params = {}

        -- Add optional column types if they're visible
        if track.volume_column_visible then
            table.insert(column_params, "volume")
        end

        if track.panning_column_visible then
            table.insert(column_params, "pan")
        end

        if track.delay_column_visible then
            table.insert(column_params, "delay")
        end

        if track.sample_effects_column_visible then
            table.insert(column_params, "fx_number_xx")
            table.insert(column_params, "fx_number_yy")
            table.insert(column_params, "fx_amount_x")
            table.insert(column_params, "fx_amount_y")
        end

        -- Assign CCs for this note column's parameters
        for _, param_type in ipairs(column_params) do
            if cc_index <= #self.available_ccs then
                local cc = self.available_ccs[cc_index]
                new_controls[cc] = {
                    type = param_type,
                    note_column_index = note_col_idx
                }

                new_last_controls[cc] = {
                    command = 0,
                    channel = 0,
                    control_cc = 0,
                    value = 0,
                    count = 0,
                    number_of_steps_to_change_value = self.number_of_steps,
                }

                cc_index = cc_index + 1
            else
                break
            end
        end

        if cc_index > #self.available_ccs then
            break
        end
    end

    -- Assign CCs for all visible effect columns
    for effect_col_idx = 1, num_visible_effect_columns do
        local effect_params = { "effect_number_xx", "effect_number_yy", "effect_amount_x", "effect_amount_y" }

        for _, param_type in ipairs(effect_params) do
            if cc_index <= #self.available_ccs then
                local cc = self.available_ccs[cc_index]
                new_controls[cc] = {
                    type = param_type,
                    effect_column_index = effect_col_idx
                }

                new_last_controls[cc] = {
                    command = 0,
                    channel = 0,
                    control_cc = 0,
                    value = 0,
                    count = 0,
                    number_of_steps_to_change_value = self.number_of_steps,
                }

                cc_index = cc_index + 1
            else
                break
            end
        end

        if cc_index > #self.available_ccs then
            break
        end
    end

    -- Add automation controls for ALL existing automations
    local all_automations = AutomationHelpers.get_all_track_automations()
    for _, automation_param in ipairs(all_automations) do
        local automation_params = { "automation_prev_scaling", "automation", "automation_scaling" }
        for _, param_type in ipairs(automation_params) do
            if cc_index <= #self.available_ccs then
                local cc = self.available_ccs[cc_index]
                new_controls[cc] = {
                    type = param_type,
                    automation_parameter = automation_param
                }
                new_last_controls[cc] = {
                    command = 0,
                    channel = 0,
                    control_cc = 0,
                    value = 0,
                    count = 0,
                    number_of_steps_to_change_value = self.number_of_steps,
                }

                cc_index = cc_index + 1
            else
                break
            end
        end

        if cc_index > #self.available_ccs then
            break
        end
    end

    -- Find CCs that are being disabled and reset them
    local C = self.colors
    for old_cc, old_control_info in pairs(old_controls) do
        if new_controls[old_cc] == nil then
            self.send_midi_feedback(old_cc, 0)
            self.send_color_feedback(old_cc, C.EMPTY_COLOR)
            local col_info = ""
            if old_control_info.note_column_index then
                col_info = " note col" .. old_control_info.note_column_index
            elseif old_control_info.effect_column_index then
                col_info = " effect col" .. old_control_info.effect_column_index
            elseif old_control_info.automation_parameter then
                col_info = " automation " .. old_control_info.automation_parameter.name
            end
            print("  Reset CC" .. old_cc .. " (was " .. old_control_info.type .. col_info .. ")")
        end
    end

    -- Apply new mappings
    self.controls = new_controls
    self.last_controls = new_last_controls

    print("MIDI Fighter Twister: Column controls rebuilt")
    for cc, control_info in pairs(self.controls) do
        local col_info = ""
        if control_info.note_column_index then
            col_info = " (note column " .. control_info.note_column_index .. ")"
        elseif control_info.effect_column_index then
            col_info = " (effect column " .. control_info.effect_column_index .. ")"
        elseif control_info.automation_parameter then
            local param_name = control_info.automation_parameter.name or "Unknown"
            col_info = " (" .. param_name .. ")"
        end
        print("  CC" .. cc .. " -> " .. control_info.type .. col_info)
    end
end

--- Search backwards for a column value in previous lines
function ColumnControls:search_backwards_for_value(column_type, column_index, current_line_index, song, is_effect_column)
    local params = self.column_params[column_type]
    if not params then
        return 0
    end
    return self.search_backwards(song, is_effect_column, current_line_index, column_index, params)
end

--- Check if a value exists at the current position for a given column type and column index
function ColumnControls:has_value_at_current_position(column_type, column_index, is_effect_column, automation_parameter)
    if column_type == "cursor" then
        return true
    end
    if column_type == "automation" or column_type == "automation_scaling" then
        return automation_parameter ~= nil
    elseif column_type == "automation_prev_scaling" then
        if not automation_parameter then
            return false
        end
        local automation, prev_point = AutomationHelpers.get_automation_and_prev_point(automation_parameter)
        return prev_point ~= nil
    end

    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return false
    end

    local columns = nil
    if is_effect_column then
        columns = current_line.effect_columns
    else
        columns = current_line.note_columns
    end

    if column_index > 0 and column_index <= #columns then
        local column = columns[column_index]
        local params = self.column_params[column_type]

        if params then
            return not params:is_absent(column)
        end
    end

    return false
end

--- Get current column value for a specific column
function ColumnControls:get_current_column_value(column_type, column_index, is_effect_column, automation_parameter)
    if column_type == "cursor" then
        local song = renoise.song()
        return song.selected_line_index, nil, 1
    end
    if column_type == "automation" or column_type == "automation_scaling" or column_type == "automation_prev_scaling" then
        local params = self.column_params[column_type]
        local value_quantum = automation_parameter.value_quantum / (automation_parameter.value_max - automation_parameter.value_min) + automation_parameter.value_min
        local return_value_quantum = math.ceil(value_quantum * 127)
        if return_value_quantum == 0 then
            return_value_quantum = 1
        end
        return params:getter(automation_parameter), automation_parameter, return_value_quantum
    end

    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return 0, nil
    end

    local columns = nil
    if is_effect_column then
        columns = current_line.effect_columns
    else
        columns = current_line.note_columns
    end

    if column_index > 0 and column_index <= #columns then
        local column = columns[column_index]
        local params = self.column_params[column_type]

        if not params then
            return 0, nil
        end

        local column_value = params:getter(column)

        -- Handle empty values by looking back through previous lines
        if params:is_absent(column) then
            column_value = self:search_backwards_for_value(column_type, column_index, song.selected_line_index, song, is_effect_column)
        end

        return column_value, column, 1
    end

    return 0, nil
end

--- Set selection for a specific column
function ColumnControls:set_selection(column_type, column_index, is_effect_column, automation_parameter)
    if column_type == "cursor" then
        return
    end
    if column_type == "automation" or column_type == "automation_scaling" or column_type == "automation_prev_scaling" then
        if renoise.app().window.active_lower_frame ~= renoise.ApplicationWindow.LOWER_FRAME_TRACK_AUTOMATION then
            renoise.app().window.active_lower_frame = renoise.ApplicationWindow.LOWER_FRAME_TRACK_AUTOMATION
        end
        if automation_parameter then
            renoise.song().selected_automation_parameter = automation_parameter
        end
        return
    end

    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return
    end
    if (not is_effect_column) then
        song.selected_note_column_index = column_index
    else
        song.selected_effect_column_index = column_index
    end
    local select_column = column_index
    if is_effect_column then
        select_column = song.selected_track.visible_note_columns + column_index
    end

    song.selection_in_pattern = {
        start_line = song.selected_line_index,
        end_line = song.selected_line_index,
        start_track = song.selected_track_index,
        end_track = song.selected_track_index,
        start_column = select_column,
        end_column = select_column,
    }
end

--- Map column value to MIDI range (0-127)
function ColumnControls:map_to_midi_range(column_type, current_value, automation_parameter, column)
    if column_type == "cursor" then
        local song = renoise.song()
        local num_lines = song.selected_pattern.number_of_lines
        if num_lines <= 1 then
            return 0
        end
        local normalized = (current_value - 1) / (num_lines - 1)
        return math.max(0, math.min(127, math.floor(normalized * 127 + 0.5)))
    end

    local params = self.column_params[column_type]
    if not params then
        return 0
    end

    if column_type == "automation" or column_type == "automation_scaling" or column_type == "automation_prev_scaling" then
        return current_value
    end

    local max_val = params:max_value(column)
    local min_val = params:min_value(column)
    local range = max_val - min_val
    if range <= 0 then
        return 0
    end

    local normalized_value = (current_value - min_val) / range
    local midi_value = math.floor(normalized_value * 127 + 0.5)

    return math.max(0, math.min(127, midi_value))
end

--- Update MIDI controller for a specific column type and column index
function ColumnControls:update_controller_for_column(column_type, column_index, cc, is_effect_column, automation_parameter)
    local current_value, column = self:get_current_column_value(column_type, column_index, is_effect_column, automation_parameter)
    local has_value = self:has_value_at_current_position(column_type, column_index, is_effect_column, automation_parameter)
    local color_value = self:get_column_color(column_type, has_value, automation_parameter)

    local midi_value = self:map_to_midi_range(column_type, current_value, automation_parameter, column)

    self.send_midi_feedback(cc, midi_value)
    self.send_color_feedback(cc, color_value)
end

--- Update all controllers
function ColumnControls:update_all()
    for cc, control_info in pairs(self.controls) do
        local is_effect_column = (control_info.effect_column_index ~= nil)
        local column_index = control_info.note_column_index or control_info.effect_column_index or 0
        local automation_parameter = control_info.automation_parameter
        self:update_controller_for_column(control_info.type, column_index, cc, is_effect_column, automation_parameter)
    end
end

--- Modify column value for a specific column
function ColumnControls:modify_column_value(column_type, column_index, cc, direction, is_effect_column, automation_parameter)
    local song = renoise.song()
    if column_type == "cursor" then
        local current_line = song.selected_line_index
        local num_lines = song.selected_pattern.number_of_lines
        local new_line = current_line

        if direction > 0 then
            new_line = current_line + 1
            if new_line > num_lines then
                new_line = num_lines
            end
        else
            new_line = current_line - 1
            if new_line < 1 then
                new_line = 1
            end
        end

        song.selected_line_index = new_line

        local midi_value = self:map_to_midi_range("cursor", new_line, nil, nil)
        self.send_midi_feedback(cc, midi_value)
        self.send_color_feedback(cc, self.colors.CURSOR_COLOR)
        return
    end

    if not song.transport.edit_mode then
        return
    end

    local current_value, column, value_quantum = self:get_current_column_value(column_type, column_index, is_effect_column, automation_parameter)

    local params = self.column_params[column_type]
    if not params then
        return
    end

    local max_val = params:max_value(column)
    local min_val = params:min_value(column)
    local new_value = current_value

    local real_value = params:getter(column)

    if real_value == current_value then
        if direction > 0 then
            new_value = current_value + value_quantum
            if new_value > max_val then
                new_value = max_val
            end
        elseif direction < 0 then
            new_value = current_value - value_quantum
            if new_value < min_val then
                new_value = min_val
            end
        end
    end

    params:setter(column, new_value, column_index)
    self:set_selection(column_type, column_index, is_effect_column, automation_parameter)

    local midi_value = self:map_to_midi_range(column_type, new_value, automation_parameter, column)
    self.send_midi_feedback(cc, midi_value)
    local has_value = self:has_value_at_current_position(column_type, column_index, is_effect_column, automation_parameter)
    local color_value = self:get_column_color(column_type, has_value, automation_parameter)
    self.send_color_feedback(cc, color_value)
end

--- Check if ready to modify for a specific CC
function ColumnControls:is_ready_to_modify(command, channel, control_cc, control_channel)
    local last_control = self.last_controls[control_cc]
    if not last_control then
        return false
    end

    local is_same_message = (last_control.command == command and
            last_control.channel == channel and
            last_control.control_cc == control_cc)

    if is_same_message then
        last_control.count = last_control.count + 1
        if last_control.count > last_control.number_of_steps_to_change_value then
            last_control.count = 1
        end
    else
        last_control.command = command
        last_control.channel = channel
        last_control.control_cc = control_cc
        last_control.count = 1
    end

    return (channel == control_channel and
            self.controls[control_cc] ~= nil and
            last_control.count >= last_control.number_of_steps_to_change_value)
end

return ColumnControls