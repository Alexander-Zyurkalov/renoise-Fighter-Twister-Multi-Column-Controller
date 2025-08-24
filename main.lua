-- MIDI Fighter Twister Instrument Controller for Renoise
-- Controls instrument number with CC12 Channel 1 and sends feedback

-- Global variables
local midi_device = nil
local midi_output_device = nil
local observers_attached = false
local position_timer = nil
local last_edit_pos = nil
local last_note_column = nil

-- MIDI control settings
local CONTROL_CC = 12
local CONTROL_CHANNEL = 1
local INCREASE_VALUE = 65
local DECREASE_VALUE = 63
local NUMBER_OF_STEPS_TO_CHANGE_VALUE = 6
local DEVICE_NAME = "Midi Fighter Twister"

-- Improved last control state tracking (following Lua conventions)
local last_control = {
    command = 0,
    channel = 0,
    control_cc = 0,
    value = 0,
    count = 0
}

-- Function to get current instrument value and note column
local function get_current_instrument()
    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return 0, nil
    end

    local note_columns = current_line.note_columns
    local selected_column = song.selected_note_column_index

    if selected_column > 0 and selected_column <= table.getn(note_columns) then
        local note_column = note_columns[selected_column]
        local instrument_value = note_column.instrument_value

        if instrument_value == 255 then
            -- Look back through previous lines to find a non-255 value
            local current_pattern = song.selected_pattern
            local current_track = current_pattern.tracks[song.selected_track_index]
            local current_line_index = song.selected_line_index

            -- Search backwards from the previous line
            for line_index = current_line_index - 1, 1, -1 do
                local line = current_track:line(line_index)
                if line and line.note_columns and selected_column <= table.getn(line.note_columns) then
                    local prev_note_column = line.note_columns[selected_column]
                    if prev_note_column then
                        local prev_instrument_value = prev_note_column.instrument_value
                        if prev_instrument_value ~= 255 then
                            instrument_value = prev_instrument_value
                            break
                        end
                    end
                end
            end

            -- If we still have 255 after looking back (or are at the top), set to 0
            if instrument_value == 255 then
                instrument_value = 0
            end
        end

        return instrument_value, note_column
    end

    return 0, nil
end

local function send_midi_feedback(value)
    if midi_output_device then
        local status_byte = 176 + (CONTROL_CHANNEL - 1)
        local clamped_value = math.min(127, value)
        local message = { status_byte, CONTROL_CC, clamped_value }
        midi_output_device:send(message)
    end
end

-- Function to update MIDI controller with current instrument
local function update_controller()
    local current_instrument, _ = get_current_instrument()
    send_midi_feedback(current_instrument)
end

-- Function to modify instrument number
local function modify_instrument(direction)
    local current_instrument, note_column = get_current_instrument()

    if not note_column then
        return
    end

    local new_instrument = current_instrument
    if direction > 0 then
        new_instrument = math.min(254, current_instrument + 1)
    else
        new_instrument = math.max(0, current_instrument - 1)
    end

    note_column.instrument_value = new_instrument
    send_midi_feedback(new_instrument)
end

local function is_ready_to_modify(command, channel, control_cc)
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
            control_cc == CONTROL_CC and
            last_control.count == NUMBER_OF_STEPS_TO_CHANGE_VALUE)
end

-- MIDI event handler
local function midi_callback(message)
    local status = message[1]
    local data1 = message[2] or 0
    local data2 = message[3] or 0

    local channel = (status % 16) + 1
    local command = status - (status % 16)

    if is_ready_to_modify(command, channel, data1) then
        if data2 == INCREASE_VALUE then
            modify_instrument(1)
        elseif data2 == DECREASE_VALUE then
            modify_instrument(-1)
        end
    end
end

-- Function to start position monitoring
local function start_position_timer()
    if renoise.tool():has_timer(update_controller) then
        return
    end

    -- Check position every 1000ms
    position_timer = renoise.tool():add_timer(update_controller, 1000)
end

-- Function to stop position monitoring
local function stop_position_timer()
    if renoise.tool():has_timer(update_controller) then
        renoise.tool():remove_timer(update_controller)
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
    if song.selected_track_index_observable:has_notifier(update_controller) == false then
        song.selected_track_index_observable:add_notifier(update_controller)
    end

    -- Pattern selection changed
    if song.selected_pattern_index_observable:has_notifier(update_controller) == false then
        song.selected_pattern_index_observable:add_notifier(update_controller)
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
    if song.selected_track_index_observable:has_notifier(update_controller) then
        song.selected_track_index_observable:remove_notifier(update_controller)
    end

    if song.selected_pattern_index_observable:has_notifier(update_controller) then
        song.selected_pattern_index_observable:remove_notifier(update_controller)
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

    -- Attach observers and update controller
    if midi_output_device then
        attach_observers()
        update_controller() -- Send current instrument value immediately
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