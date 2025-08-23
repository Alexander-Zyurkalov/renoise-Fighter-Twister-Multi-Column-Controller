-- MIDI Monitor Tool for Renoise
-- Shows a window to select MIDI device and display last 3 events

-- Global variables
local dialog = nil
local midi_device = nil
local midi_events = {}
local MAX_EVENTS = 3

-- UI elements
local device_popup = nil
local event_text_1 = nil
local event_text_2 = nil
local event_text_3 = nil

-- MIDI event handler
local function midi_callback(message)
  -- Parse MIDI message
  local status = message[1]
  local data1 = message[2] or 0
  local data2 = message[3] or 0
  
  -- Determine message type
  local msg_type = "Unknown"
  local channel = (status % 16) + 1
  local command = status - (status % 16)
  
  if command == 128 then -- 0x80
    msg_type = string.format("Note Off Ch%d: Note %d, Vel %d", channel, data1, data2)
  elseif command == 144 then -- 0x90
    if data2 == 0 then
      msg_type = string.format("Note Off Ch%d: Note %d, Vel %d", channel, data1, data2)
    else
      msg_type = string.format("Note On Ch%d: Note %d, Vel %d", channel, data1, data2)
    end
  elseif command == 176 then -- 0xB0
    msg_type = string.format("CC Ch%d: CC %d, Val %d", channel, data1, data2)
  elseif command == 192 then -- 0xC0
    msg_type = string.format("Program Change Ch%d: %d", channel, data1)
  elseif command == 224 then -- 0xE0
    local pitch_value = data1 + (data2 * 128)
    msg_type = string.format("Pitch Bend Ch%d: %d", channel, pitch_value)
  else
    msg_type = string.format("Status: %d, Data1: %d, Data2: %d", status, data1, data2)
  end
  
  -- Add timestamp
  local timestamp = os.date("%H:%M:%S")
  local event_string = string.format("[%s] %s", timestamp, msg_type)
  
  -- Add to events list (keep only last 3)
  table.insert(midi_events, 1, event_string)
  if table.getn(midi_events) > MAX_EVENTS then
    table.remove(midi_events, MAX_EVENTS + 1)
  end
  
  -- Update UI if dialog is open
  if dialog and dialog.visible then
    event_text_1.text = midi_events[1] or ""
    event_text_2.text = midi_events[2] or ""
    event_text_3.text = midi_events[3] or ""
  end
end

-- Get available MIDI devices
local function get_midi_devices()
  local devices = {"None"}
  local available_devices = renoise.Midi.available_input_devices()
  for i = 1, table.getn(available_devices) do
    table.insert(devices, available_devices[i])
  end
  return devices
end

-- Device selection handler
local function on_device_changed()
  -- Close existing device
  if midi_device then
    midi_device:close()
    midi_device = nil
  end
  
  -- Clear events
  midi_events = {}
  if dialog and dialog.visible then
    event_text_1.text = ""
    event_text_2.text = ""
    event_text_3.text = ""
  end
  
  -- Open new device
  local selected_index = device_popup.value
  if selected_index > 1 then -- Skip "None" option
    local available_devices = renoise.Midi.available_input_devices()
    local device_name = available_devices[selected_index - 1]
    midi_device = renoise.Midi.create_input_device(device_name, midi_callback)
  end
end

-- Create the dialog
local function create_dialog()
  local vb = renoise.ViewBuilder()
  
  -- Get available devices
  local devices = get_midi_devices()
  
  -- Create UI elements
  device_popup = vb:popup {
    items = devices,
    value = 1,
    notifier = on_device_changed,
    width = 200
  }
  
  event_text_1 = vb:text {
    text = "",
    font = "mono",
    width = 400
  }
  
  event_text_2 = vb:text {
    text = "",
    font = "mono", 
    width = 400
  }
  
  event_text_3 = vb:text {
    text = "",
    font = "mono",
    width = 400
  }
  
  -- Create the main content
  local content = vb:column {
    margin = 10,
    spacing = 5,
    
    vb:row {
      vb:text { text = "MIDI Device:" },
      device_popup
    },
    
    vb:space { height = 10 },
    
    vb:text { text = "Last 3 MIDI Events:", style = "strong" },
    vb:space { height = 5 },
    
    vb:column {
      spacing = 2,
      event_text_1,
      event_text_2,
      event_text_3
    },
    
    vb:space { height = 10 },
    
    vb:button {
      text = "Clear Events",
      notifier = function()
        midi_events = {}
        event_text_1.text = ""
        event_text_2.text = ""
        event_text_3.text = ""
      end
    }
  }
  
  return vb:column { content }
end

-- Show the dialog
local function show_dialog()
  if dialog and dialog.visible then
    dialog:show()
    return
  end
  
  dialog = renoise.app():show_custom_dialog(
    "MIDI Monitor",
    create_dialog(),
    function() -- Key handler
      -- Close MIDI device when dialog closes
      if midi_device then
        midi_device:close()
        midi_device = nil
      end
    end
  )
end

-- Add menu entry
renoise.tool():add_menu_entry {
  name = "Main Menu:Tools:MIDI Monitor...",
  invoke = show_dialog
}

-- Cleanup when tool is unloaded
renoise.tool().app_release_document_observable:add_notifier(function()
  if midi_device then
    midi_device:close()
    midi_device = nil
  end
end)
