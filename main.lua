-- MIDI Fighter Twister Multi-Column Controller for Renoise
-- Controls instrument, volume, pan, delay, FX columns, and effect columns with feedback
-- Dynamically assigns CCs to control ALL visible note columns and effect columns
-- Sends color feedback: Green if value exists, Blue if empty

-- Global variables
local midi_device = nil
local midi_output_device = nil
local observers_attached = false
local column_observers_attached = false
local position_timer = nil

-- MIDI control settings
local CONTROL_CHANNEL = 1
local COLOUR_CHANNEL = 2
local INCREASE_VALUE = 65
local DECREASE_VALUE = 63
local NUMBER_OF_STEPS_TO_CHANGE_VALUE = 6
local DEVICE_NAME = "Midi Fighter Twister"

-- Color values for MIDI Fighter Twister
local NOTE_COLOR = 50        -- Note values (to differentiate note column boundaries)
local EMPTY_NOTE_COLOR = 30        -- Note values (to differentiate note column boundaries)
local OTHER_PARAM_COLOR = 70 -- Other parameters (instrument, volume, pan, delay, fx)
local EFFECT_COLOR = 90      -- Effect columns (effect number/amount)
local EMPTY_EFFECT_COLOR = 20 -- Empty effect columns
local EMPTY_COLOR = 0         -- No value/empty

-- Available CC numbers pool (modify this list as needed)
local AVAILABLE_CCS = { 12, 13, 14, 15, 8, 9, 10, 11, 4, 5, 6, 7, 0, 1, 2, 3}

-- Dynamic column control mapping (rebuilt when visibility changes)
-- Structure: COLUMN_CONTROLS[cc] = { type = "note/instrument/volume/pan/delay/fx/effect_number/effect_amount", note_column_index = 1..N, effect_column_index = 1..N }
local COLUMN_CONTROLS = {}

-- Column parameter configuration hash-map
local COLUMN_PARAMS = {
    note = {
        getter = function(note_column)
            return note_column.note_value
        end,
        setter = function(note_column, value, note_column_index)
            note_column.note_value = value
        end,
        min_value = 0,
        max_value = 120,
        absent_value = 121,
        default_value = 0,
    },
    instrument = {
        getter = function(note_column)
            return note_column.instrument_value
        end,
        setter = function(note_column, value, note_column_index)
            note_column.instrument_value = value
        end,
        min_value = 0,
        max_value = 254,
        absent_value = 255,
        default_value = 0,
    },
    volume = {
        getter = function(note_column)
            return note_column.volume_value
        end,
        setter = function(note_column, value, note_column_index)
            note_column.volume_value = value
        end,
        min_value = 0,
        max_value = 0x80,
        absent_value = 0xFF,
        default_value = 0,
    },
    pan = {
        getter = function(note_column)
            return note_column.panning_value
        end,
        setter = function(note_column, value, note_column_index)
            note_column.panning_value = value
        end,
        min_value = 0,
        max_value = 0x80,
        absent_value = 0xFF,
        default_value = 0x40, -- Center pan
    },
    delay = {
        getter = function(note_column)
            return note_column.delay_value
        end,
        setter = function(note_column, value, note_column_index)
            note_column.delay_value = value
        end,
        min_value = 0,
        max_value = 0xFF,
        absent_value = 0,
        default_value = 0,
    },
    fx = {
        getter = function(note_column)
            return note_column.effect_amount_value
        end,
        setter = function(note_column, value, note_column_index)
            note_column.effect_amount_value = value
            -- Also set effect_number_value from previous effects if current is empty
            if note_column.effect_number_value == 0 then
                local song = renoise.song()
                local current_line_index = song.selected_line_index
                local current_pattern = song.selected_pattern
                local current_track = current_pattern.tracks[song.selected_track_index]

                -- Search backwards for effect_number_value in this same column
                for line_index = current_line_index - 1, 1, -1 do
                    local line = current_track:line(line_index)
                    if line and line.note_columns and note_column_index <= table.getn(line.note_columns) then
                        local prev_note_column = line.note_columns[note_column_index]
                        if prev_note_column and prev_note_column.effect_number_value ~= 0 then
                            note_column.effect_number_value = prev_note_column.effect_number_value
                            break
                        end
                    end
                end
            end
        end,
        min_value = 0,
        max_value = 255,
        absent_value = 0,
        default_value = 0
    },
    --effect_number = {
    --    getter = function(effect_column)
    --        return effect_column.number_value
    --    end,
    --    setter = function(effect_column, value, effect_column_index)
    --        effect_column.number_value = value
    --    end,
    --    min_value = 0,
    --    max_value = 255,
    --    absent_value = 0,
    --    default_value = 0,
    --},
    effect_amount = {
        getter = function(effect_column)
            return effect_column.amount_value
        end,
        setter = function(effect_column, value, effect_column_index)
            effect_column.amount_value = value
            -- Also set effect number from previous effects if current is empty
            if effect_column.number_value == 0 then
                local song = renoise.song()
                local current_line_index = song.selected_line_index
                local current_pattern = song.selected_pattern
                local current_track = current_pattern.tracks[song.selected_track_index]

                -- Search backwards for number_value in this same effect column
                for line_index = current_line_index - 1, 1, -1 do
                    local line = current_track:line(line_index)
                    if line and line.effect_columns and effect_column_index <= table.getn(line.effect_columns) then
                        local prev_effect_column = line.effect_columns[effect_column_index]
                        if prev_effect_column and prev_effect_column.number_value ~= 0 then
                            effect_column.number_value = prev_effect_column.number_value
                            break
                        end
                    end
                end
            end
        end,
        min_value = 0,
        max_value = 255,
        absent_value = 0,
        default_value = 0
    }
}

-- Function to send MIDI feedback for a specific CC
local function send_midi_feedback(cc, value)
    if midi_output_device then
        local status_byte = 176 + (CONTROL_CHANNEL - 1)
        local clamped_value = math.min(127, value)
        local message = { status_byte, cc, clamped_value }
        midi_output_device:send(message)
    end
end

-- Function to send color feedback for a specific CC
local function send_color_feedback(cc, color_value)
    if midi_output_device then
        local status_byte = 176 + (COLOUR_CHANNEL - 1)
        local clamped_value = math.min(127, color_value)
        local message = { status_byte, cc, clamped_value }
        midi_output_device:send(message)
    end
end

-- Function to get the appropriate color for a column type and value state
local function get_column_color(column_type, has_value)
    if not has_value and column_type ~= "note" and column_type ~= "effect_number" and column_type ~= "effect_amount" then
        return EMPTY_COLOR
    end
    if not has_value and column_type == "note" then
        return EMPTY_NOTE_COLOR
    end
    if not has_value and (column_type == "effect_number" or column_type == "effect_amount") then
        return EMPTY_EFFECT_COLOR
    end

    if column_type == "note" then
        return NOTE_COLOR
    elseif column_type == "effect_number" or column_type == "effect_amount" then
        return EFFECT_COLOR
    else
        return OTHER_PARAM_COLOR
    end
end

-- Function to rebuild COLUMN_CONTROLS based on current track's visible columns
local function rebuild_column_controls()
    local song = renoise.song()
    local track = song.selected_track

    -- Store old mappings before clearing
    local old_column_controls = {}
    for cc, control_info in pairs(COLUMN_CONTROLS) do
        old_column_controls[cc] = control_info
    end

    -- Build new mappings in temporary table
    local new_column_controls = {}
    local new_last_controls = {}

    local cc_index = 1
    local num_visible_note_columns = track.visible_note_columns
    local num_visible_effect_columns = track.visible_effect_columns

    -- Assign CCs for all visible note columns
    for note_col_idx = 1, num_visible_note_columns do
        -- Always assign note and instrument for each column
        local column_params = {"note", "instrument"}

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
            table.insert(column_params, "fx")
        end

        -- Assign CCs for this note column's parameters
        for _, param_type in ipairs(column_params) do
            if cc_index <= table.getn(AVAILABLE_CCS) then
                local cc = AVAILABLE_CCS[cc_index]
                new_column_controls[cc] = {
                    type = param_type,
                    note_column_index = note_col_idx
                }

                -- Initialize last control state for this CC
                new_last_controls[cc] = {
                    command = 0,
                    channel = 0,
                    control_cc = 0,
                    value = 0,
                    count = 0,
                    number_of_steps_to_change_value = NUMBER_OF_STEPS_TO_CHANGE_VALUE,
                }

                cc_index = cc_index + 1
            else
                -- Run out of available CCs
                break
            end
        end

        if cc_index > table.getn(AVAILABLE_CCS) then
            break
        end
    end

    -- Assign CCs for all visible effect columns
    for effect_col_idx = 1, num_visible_effect_columns do
        local effect_params = {"effect_amount"}

        -- Assign CCs for this effect column's parameters
        for _, param_type in ipairs(effect_params) do
            if cc_index <= table.getn(AVAILABLE_CCS) then
                local cc = AVAILABLE_CCS[cc_index]
                new_column_controls[cc] = {
                    type = param_type,
                    effect_column_index = effect_col_idx
                }

                -- Initialize last control state for this CC
                new_last_controls[cc] = {
                    command = 0,
                    channel = 0,
                    control_cc = 0,
                    value = 0,
                    count = 0,
                    number_of_steps_to_change_value = NUMBER_OF_STEPS_TO_CHANGE_VALUE,
                }

                cc_index = cc_index + 1
            else
                -- Run out of available CCs
                break
            end
        end

        if cc_index > table.getn(AVAILABLE_CCS) then
            break
        end
    end

    -- Find CCs that are being disabled and reset them
    for old_cc, old_control_info in pairs(old_column_controls) do
        if new_column_controls[old_cc] == nil then
            -- This CC is being disabled, reset it
            send_midi_feedback(old_cc, 0)        -- Reset value to 0
            send_color_feedback(old_cc, EMPTY_COLOR)  -- Reset color to blue (inactive)
            local col_info = ""
            if old_control_info.note_column_index then
                col_info = " note col" .. old_control_info.note_column_index
            elseif old_control_info.effect_column_index then
                col_info = " effect col" .. old_control_info.effect_column_index
            end
            print("  Reset CC" .. old_cc .. " (was " .. old_control_info.type .. col_info .. ")")
        end
    end

    -- Apply new mappings
    COLUMN_CONTROLS = new_column_controls
    last_controls = new_last_controls

    print("MIDI Fighter Twister: Column controls rebuilt")
    for cc, control_info in pairs(COLUMN_CONTROLS) do
        local col_info = ""
        if control_info.note_column_index then
            col_info = " (note column " .. control_info.note_column_index .. ")"
        elseif control_info.effect_column_index then
            col_info = " (effect column " .. control_info.effect_column_index .. ")"
        end
        print("  CC" .. cc .. " -> " .. control_info.type .. col_info)
    end
end

-- Function to search backwards for a column value in previous lines
local function search_backwards_for_value(column_type, column_index, current_line_index, song, is_effect_column)
    local params = COLUMN_PARAMS[column_type]
    if not params then
        return params.default_value
    end

    local current_pattern = song.selected_pattern
    local current_track = current_pattern.tracks[song.selected_track_index]

    -- Search backwards from the previous line
    for line_index = current_line_index - 1, 1, -1 do
        local line = current_track:line(line_index)
        if line then
            local prev_column = nil

            if is_effect_column then
                if line.effect_columns and column_index <= table.getn(line.effect_columns) then
                    prev_column = line.effect_columns[column_index]
                end
            else
                if line.note_columns and column_index <= table.getn(line.note_columns) then
                    prev_column = line.note_columns[column_index]
                end
            end

            if prev_column then
                local prev_value = params.getter(prev_column)

                if prev_value ~= params.absent_value then
                    return prev_value
                end
            end
        end
    end

    -- If we still have absent value after looking back, return default
    return params.default_value
end

-- Function to check if a value exists at the current position for a given column type and column index
local function has_value_at_current_position(column_type, column_index, is_effect_column)
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

    if column_index > 0 and column_index <= table.getn(columns) then
        local column = columns[column_index]
        local params = COLUMN_PARAMS[column_type]

        if params then
            local value = params.getter(column)
            return value ~= params.absent_value
        end
    end

    return false
end

-- Function to get current column value for a specific column
local function get_current_column_value(column_type, column_index, is_effect_column)
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

    if column_index > 0 and column_index <= table.getn(columns) then
        local column = columns[column_index]
        local params = COLUMN_PARAMS[column_type]

        if not params then
            return 0, nil
        end

        local column_value = params.getter(column)

        -- Handle empty values by looking back through previous lines
        if column_value == params.absent_value then
            column_value = search_backwards_for_value(column_type, column_index, song.selected_line_index, song, is_effect_column)
        end

        return column_value, column
    end

    return 0, nil
end

-- Function to update MIDI controller for a specific column type and column index
local function update_controller_for_column(column_type, column_index, cc, is_effect_column)
    local current_value, _ = get_current_column_value(column_type, column_index, is_effect_column)
    local has_value = has_value_at_current_position(column_type, column_index, is_effect_column)
    local color_value = get_column_color(column_type, has_value)

    -- Send both column value and color
    send_midi_feedback(cc, current_value)
    send_color_feedback(cc, color_value)
end

-- Function to update all controllers
local function update_all_controllers()
    for cc, control_info in pairs(COLUMN_CONTROLS) do
        local is_effect_column = (control_info.effect_column_index ~= nil)
        local column_index = control_info.note_column_index or control_info.effect_column_index
        update_controller_for_column(control_info.type, column_index, cc, is_effect_column)
    end
end

-- Function to modify column value for a specific column
local function modify_column_value(column_type, column_index, cc, direction, is_effect_column)
    local current_value, column = get_current_column_value(column_type, column_index, is_effect_column)

    if not column then
        return
    end

    local params = COLUMN_PARAMS[column_type]
    if not params then
        return
    end

    local new_value = current_value

    if direction > 0 then
        new_value = current_value + 1
        if new_value > params.max_value then
            new_value = params.min_value
        end
    else
        new_value = current_value - 1
        if new_value < params.min_value then
            new_value = params.max_value
        end
    end

    params.setter(column, new_value, column_index)

    -- Send feedback
    send_midi_feedback(cc, new_value)
    local has_value = has_value_at_current_position(column_type, column_index, is_effect_column)
    local color_value = get_column_color(column_type, has_value)
    send_color_feedback(cc, color_value)
end

-- Function to check if ready to modify for a specific CC
local function is_ready_to_modify(command, channel, control_cc)
    local last_control = last_controls[control_cc]
    if not last_control then
        return false
    end

    -- Check if this is the same message as before
    local is_same_message = (last_control.command == command and
            last_control.channel == channel and
            last_control.control_cc == control_cc)

    if is_same_message then
        -- Increment counter for consecutive identical messages
        last_control.count = last_control.count + 1
        -- Reset counter if it exceeds the threshold
        if last_control.count > last_control.number_of_steps_to_change_value then
            last_control.count = 1
        end
    else
        -- Store new message state and reset counter
        last_control.command = command
        last_control.channel = channel
        last_control.control_cc = control_cc
        last_control.count = 1
    end

    -- Check if we should modify: correct CC message on correct channel with enough repetitions
    return (channel == CONTROL_CHANNEL and
            COLUMN_CONTROLS[control_cc] ~= nil and
            last_control.count >= last_control.number_of_steps_to_change_value)
end

-- MIDI event handler
local function midi_callback(message)
    local status = message[1]
    local data1 = message[2] or 0  -- CC number
    local data2 = message[3] or 0  -- CC value

    local channel = (status % 16) + 1
    local command = status - (status % 16)

    if command == 176 and data2 == 127 or data2 == 0 then
        if data2 == 127 then
            if last_controls[data1] then
                last_controls[data1].number_of_steps_to_change_value = 1
            end
        elseif data2 == 0 then
            if last_controls[data1] then
                last_controls[data1].number_of_steps_to_change_value = NUMBER_OF_STEPS_TO_CHANGE_VALUE
            end
        end
    elseif command == 176 and is_ready_to_modify(command, channel, data1) then
        local control_info = COLUMN_CONTROLS[data1]
        if control_info then
            local is_effect_column = (control_info.effect_column_index ~= nil)
            local column_index = control_info.note_column_index or control_info.effect_column_index

            if data2 == INCREASE_VALUE then
                modify_column_value(control_info.type, column_index, data1, 1, is_effect_column)
            elseif data2 == DECREASE_VALUE then
                modify_column_value(control_info.type, column_index, data1, -1, is_effect_column)
            end
        end
    end
end

-- Function to start position monitoring
local function start_position_timer()
    if renoise.tool():has_timer(update_all_controllers) then
        return
    end

    -- Check position every 1000ms
    position_timer = renoise.tool():add_timer(update_all_controllers, 1000)
end

-- Function to stop position monitoring
local function stop_position_timer()
    if renoise.tool():has_timer(update_all_controllers) then
        renoise.tool():remove_timer(update_all_controllers)
        position_timer = nil
    end
end

-- Function to attach column visibility observers
local function attach_column_observers()
    if column_observers_attached then
        return
    end

    local song = renoise.song()
    local track = song.selected_track

    -- Attach observers for column visibility changes
    if track.volume_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.volume_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.panning_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.panning_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.delay_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.delay_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.sample_effects_column_visible_observable:has_notifier(rebuild_column_controls) == false then
        track.sample_effects_column_visible_observable:add_notifier(rebuild_column_controls)
    end

    if track.visible_note_columns_observable:has_notifier(rebuild_column_controls) == false then
        track.visible_note_columns_observable:add_notifier(rebuild_column_controls)
    end

    -- Add observer for effect columns visibility
    if track.visible_effect_columns_observable:has_notifier(rebuild_column_controls) == false then
        track.visible_effect_columns_observable:add_notifier(rebuild_column_controls)
    end

    column_observers_attached = true
end

-- Function to detach column visibility observers
local function detach_column_observers()
    if not column_observers_attached then
        return
    end

    local song = renoise.song()
    local track = song.selected_track

    -- Remove column visibility observers
    if track.volume_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.volume_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.panning_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.panning_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.delay_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.delay_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.sample_effects_column_visible_observable:has_notifier(rebuild_column_controls) then
        track.sample_effects_column_visible_observable:remove_notifier(rebuild_column_controls)
    end

    if track.visible_note_columns_observable:has_notifier(rebuild_column_controls) then
        track.visible_note_columns_observable:remove_notifier(rebuild_column_controls)
    end

    -- Remove effect columns observer
    if track.visible_effect_columns_observable:has_notifier(rebuild_column_controls) then
        track.visible_effect_columns_observable:remove_notifier(rebuild_column_controls)
    end

    column_observers_attached = false
end

-- Function to handle track changes (need to reattach column observers)
local function on_track_changed()
    detach_column_observers()
    rebuild_column_controls()
    attach_column_observers()
    update_all_controllers()
end

-- Function to attach selection observers
local function attach_observers()
    if observers_attached then
        return
    end

    local song = renoise.song()

    -- Track selection changed
    if song.selected_track_index_observable:has_notifier(on_track_changed) == false then
        song.selected_track_index_observable:add_notifier(on_track_changed)
    end

    -- Pattern selection changed
    if song.selected_pattern_index_observable:has_notifier(update_all_controllers) == false then
        song.selected_pattern_index_observable:add_notifier(update_all_controllers)
    end

    -- Start position timer (handles line position changes)
    start_position_timer()

    observers_attached = true
end

-- Function to detach selection observers
local function detach_observers()
    if not observers_attached then
        return
    end

    local song = renoise.song()

    -- Remove observers
    if song.selected_track_index_observable:has_notifier(on_track_changed) then
        song.selected_track_index_observable:remove_notifier(on_track_changed)
    end

    if song.selected_pattern_index_observable:has_notifier(update_all_controllers) then
        song.selected_pattern_index_observable:remove_notifier(update_all_controllers)
    end

    -- Detach column observers
    detach_column_observers()

    -- Stop position timer
    stop_position_timer()

    observers_attached = false
end

-- Function to initialize MIDI devices
local function initialize_midi_devices()
    -- Close existing devices
    if midi_device then
        midi_device:close()
        midi_device = nil
    end
    if midi_output_device then
        midi_output_device:close()
        midi_output_device = nil
    end

    -- Detach old observers
    detach_observers()

    -- Find and open MIDI Fighter Twister
    local available_input_devices = renoise.Midi.available_input_devices()
    local available_output_devices = renoise.Midi.available_output_devices()

    -- Open input device
    for i = 1, table.getn(available_input_devices) do
        if available_input_devices[i] == DEVICE_NAME then
            midi_device = renoise.Midi.create_input_device(DEVICE_NAME, midi_callback)
            break
        end
    end

    -- Open output device
    for i = 1, table.getn(available_output_devices) do
        if available_output_devices[i] == DEVICE_NAME then
            midi_output_device = renoise.Midi.create_output_device(DEVICE_NAME)
            break
        end
    end

    -- Setup column controls and observers
    if midi_output_device then
        rebuild_column_controls()
        attach_observers()
        attach_column_observers()
        update_all_controllers() -- Send current values and colors for all columns
    end
end

-- Initialize devices when tool loads
initialize_midi_devices()

-- Add menu entry to reconnect if needed
renoise.tool():add_menu_entry {
    name = "Main Menu:Tools:Reconnect MIDI Fighter Twister",
    invoke = initialize_midi_devices
}

-- Cleanup when tool is unloaded
renoise.tool().app_release_document_observable:add_notifier(function()
    detach_observers()
    if midi_device then
        midi_device:close()
        midi_device = nil
    end
    if midi_output_device then
        midi_output_device:close()
        midi_output_device = nil
    end
end)