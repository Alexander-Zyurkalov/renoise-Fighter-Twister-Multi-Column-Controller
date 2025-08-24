-- MIDI Fighter Twister Multi-Column Controller for Renoise
-- Controls instrument, volume, pan, delay, and FX columns with feedback
-- CC12: Instrument, CC13: Volume, CC14: Pan, CC15: Delay, CC16: FX
-- Sends color feedback on corresponding CCs: Green if value exists, Blue if empty

-- Global variables
local midi_device = nil
local midi_output_device = nil
local observers_attached = false
local position_timer = nil

-- MIDI control settings
local CONTROL_CHANNEL = 1
local COLOUR_CHANNEL = 2
local INCREASE_VALUE = 65
local DECREASE_VALUE = 63
local NUMBER_OF_STEPS_TO_CHANGE_VALUE = 6
local DEVICE_NAME = "Midi Fighter Twister"

-- Column control mapping
local COLUMN_CONTROLS = {
    [12] = { type = "instrument", cc = 12 },
    [13] = { type = "volume", cc = 13 },
    [14] = { type = "pan", cc = 14 },
    [15] = { type = "delay", cc = 15 },
    [8] = { type = "fx", cc = 16 }
}

-- Color values for MIDI Fighter Twister
local GREEN_COLOR = 40    -- Value exists
local BLUE_COLOR = 1     -- No value/empty

-- Improved last control state tracking for each CC
local last_controls = {}
for cc, _ in pairs(COLUMN_CONTROLS) do
    last_controls[cc] = {
        command = 0,
        channel = 0,
        control_cc = 0,
        value = 0,
        count = 0
    }
end

-- Function to check if a value exists at the current position for a given column type
local function has_value_at_current_position(column_type)
    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return false
    end

    local note_columns = current_line.note_columns
    local selected_column = song.selected_note_column_index

    if selected_column > 0 and selected_column <= table.getn(note_columns) then
        local note_column = note_columns[selected_column]

        if column_type == "instrument" then
            return note_column.instrument_value ~= 255
        elseif column_type == "volume" then
            return note_column.volume_value ~= 255
        elseif column_type == "pan" then
            return note_column.panning_value ~= 255
        elseif column_type == "delay" then
            return note_column.delay_value ~= 0
        elseif column_type == "fx" then
            return note_column.effect_number_value ~= 0 or note_column.effect_amount_value ~= 0
        end
    end

    return false
end

-- Function to get current column value
local function get_current_column_value(column_type)
    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return 0, nil
    end

    local note_columns = current_line.note_columns
    local selected_column = song.selected_note_column_index

    if selected_column > 0 and selected_column <= table.getn(note_columns) then
        local note_column = note_columns[selected_column]
        local column_value = 0

        -- Get the appropriate value based on column type
        if column_type == "instrument" then
            column_value = note_column.instrument_value
        elseif column_type == "volume" then
            column_value = note_column.volume_value
        elseif column_type == "pan" then
            column_value = note_column.panning_value
        elseif column_type == "delay" then
            column_value = note_column.delay_value
        elseif column_type == "fx" then
            -- For FX, we'll use effect_amount_value as the main controllable parameter
            column_value = note_column.effect_amount_value
        end

        -- Handle empty values (255) by looking back through previous lines
        if column_value == 255 then
            local current_pattern = song.selected_pattern
            local current_track = current_pattern.tracks[song.selected_track_index]
            local current_line_index = song.selected_line_index

            -- Search backwards from the previous line
            for line_index = current_line_index - 1, 1, -1 do
                local line = current_track:line(line_index)
                if line and line.note_columns and selected_column <= table.getn(line.note_columns) then
                    local prev_note_column = line.note_columns[selected_column]
                    if prev_note_column then
                        local prev_value = 0

                        if column_type == "instrument" then
                            prev_value = prev_note_column.instrument_value
                        elseif column_type == "volume" then
                            prev_value = prev_note_column.volume_value
                        elseif column_type == "pan" then
                            prev_value = prev_note_column.panning_value
                        elseif column_type == "delay" then
                            prev_value = prev_note_column.delay_value
                        elseif column_type == "fx" then
                            prev_value = prev_note_column.effect_amount_value
                        end

                        if prev_value ~= 255 then
                            column_value = prev_value
                            break
                        end
                    end
                end
            end

            -- If we still have 255 after looking back, set default
            if column_value == 255 then
                if column_type == "pan" then
                    column_value = 64  -- Center pan
                else
                    column_value = 0
                end
            end
        end

        return column_value, note_column
    end

    return 0, nil
end

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

-- Function to update MIDI controller for a specific column type
local function update_controller_for_column(column_type, cc)
    local current_value, _ = get_current_column_value(column_type)
    local has_value = has_value_at_current_position(column_type)
    local color_value = has_value and GREEN_COLOR or BLUE_COLOR

    -- Send both column value and color
    send_midi_feedback(cc, current_value)
    send_color_feedback(cc, color_value)
end

-- Function to update all controllers
local function update_all_controllers()
    for cc, control_info in pairs(COLUMN_CONTROLS) do
        update_controller_for_column(control_info.type, cc)
    end
end

-- Function to modify column value
local function modify_column_value(column_type, cc, direction)
    local current_value, note_column = get_current_column_value(column_type)

    if not note_column then
        return
    end

    local new_value = current_value
    local min_val, max_val = 0, 127

    -- Set appropriate ranges for different column types
    if column_type == "instrument" then
        min_val, max_val = 0, 254
    elseif column_type == "volume" then
        min_val, max_val = 0, 127
    elseif column_type == "pan" then
        min_val, max_val = 0, 127
    elseif column_type == "delay" then
        min_val, max_val = 0, 255
    elseif column_type == "fx" then
        min_val, max_val = 0, 255
    end

    -- Calculate new value
    if direction > 0 then
        new_value = math.min(max_val, current_value + 1)
    else
        new_value = math.max(min_val, current_value - 1)
    end

    -- Set the appropriate column value
    if column_type == "instrument" then
        note_column.instrument_value = new_value
    elseif column_type == "volume" then
        note_column.volume_value = new_value
    elseif column_type == "pan" then
        note_column.panning_value = new_value
    elseif column_type == "delay" then
        note_column.delay_value = new_value
    elseif column_type == "fx" then
        note_column.effect_amount_value = new_value
        -- If effect amount is being set and there's no effect number, set a default
        if new_value > 0 and note_column.effect_number_value == 0 then
            note_column.effect_number_value = 1  -- Default to first effect
        end
    end

    -- Send feedback
    send_midi_feedback(cc, new_value)
    local has_value = has_value_at_current_position(column_type)
    local color_value = has_value and GREEN_COLOR or BLUE_COLOR
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
        if last_control.count > NUMBER_OF_STEPS_TO_CHANGE_VALUE then
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
    return (command == 176 and
            channel == CONTROL_CHANNEL and
            COLUMN_CONTROLS[control_cc] ~= nil and
            last_control.count == NUMBER_OF_STEPS_TO_CHANGE_VALUE)
end

-- MIDI event handler
local function midi_callback(message)
    local status = message[1]
    local data1 = message[2] or 0  -- CC number
    local data2 = message[3] or 0  -- CC value

    local channel = (status % 16) + 1
    local command = status - (status % 16)

    if is_ready_to_modify(command, channel, data1) then
        local control_info = COLUMN_CONTROLS[data1]
        if control_info then
            if data2 == INCREASE_VALUE then
                modify_column_value(control_info.type, data1, 1)
            elseif data2 == DECREASE_VALUE then
                modify_column_value(control_info.type, data1, -1)
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

-- Function to attach selection observers
local function attach_observers()
    if observers_attached then
        return
    end

    local song = renoise.song()

    -- Track selection changed
    if song.selected_track_index_observable:has_notifier(update_all_controllers) == false then
        song.selected_track_index_observable:add_notifier(update_all_controllers)
    end

    -- Pattern selection changed
    if song.selected_pattern_index_observable:has_notifier(update_all_controllers) == false then
        song.selected_pattern_index_observable:add_notifier(update_all_controllers)
    end

    -- Start position timer (handles line position and note column changes)
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
    if song.selected_track_index_observable:has_notifier(update_all_controllers) then
        song.selected_track_index_observable:remove_notifier(update_all_controllers)
    end

    if song.selected_pattern_index_observable:has_notifier(update_all_controllers) then
        song.selected_pattern_index_observable:remove_notifier(update_all_controllers)
    end

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

    -- Attach observers and update controllers
    if midi_output_device then
        attach_observers()
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