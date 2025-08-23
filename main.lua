-- MIDI Fighter Twister Instrument Controller for Renoise
-- Controls instrument number with CC12 Channel 1 and sends feedback

-- Global variables
local midi_device = nil
local midi_output_device = nil

-- MIDI control settings
local CONTROL_CC = 12
local CONTROL_CHANNEL = 1
local INCREASE_VALUE = 65
local DECREASE_VALUE = 63
local DEVICE_NAME = "Midi Fighter Twister"

-- Function to send MIDI feedback
local function send_midi_feedback(value)
    if midi_output_device then
        local status_byte = 176 + (CONTROL_CHANNEL - 1)
        local clamped_value = math.min(127, value)
        local message = {status_byte, CONTROL_CC, clamped_value}
        midi_output_device:send(message)
    end
end

-- Function to modify instrument number
local function modify_instrument(direction)
    local song = renoise.song()
    local current_line = song.selected_line

    if not current_line then
        return
    end

    local note_columns = current_line.note_columns
    local selected_column = song.selected_note_column_index

    if selected_column > 0 and selected_column <= table.getn(note_columns) then
        local note_column = note_columns[selected_column]
        local current_instrument = note_column.instrument_value

        local new_instrument = current_instrument
        if direction > 0 then
            new_instrument = math.min(254, current_instrument + 1)
        else
            new_instrument = math.max(0, current_instrument - 1)
        end

        note_column.instrument_value = new_instrument
        send_midi_feedback(new_instrument)
    end
end

-- MIDI event handler
local function midi_callback(message)
    local status = message[1]
    local data1 = message[2] or 0
    local data2 = message[3] or 0

    local channel = (status % 16) + 1
    local command = status - (status % 16)

    if command == 176 and channel == CONTROL_CHANNEL and data1 == CONTROL_CC then
        if data2 == INCREASE_VALUE then
            modify_instrument(1)
        elseif data2 == DECREASE_VALUE then
            modify_instrument(-1)
        end
    end
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
    if midi_device then
        midi_device:close()
        midi_device = nil
    end
    if midi_output_device then
        midi_output_device:close()
        midi_output_device = nil
    end
end)