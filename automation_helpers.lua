local AutomationHelpers = { }
AutomationHelpers.__index = AutomationHelpers

-- Helper functions for automation with specific parameters
function AutomationHelpers.get_automation_and_point(automation_parameter)
    if not automation_parameter then
        return nil, nil
    end

    local song = renoise.song()
    local automation = song.selected_pattern_track:find_automation(automation_parameter)
    if not automation then
        return nil, nil
    end

    local line = song.selected_line_index

    -- Search backwards for the nearest automation point
    while line >= 1 and not automation:has_point_at(line) do
        line = line - 1
    end

    if line < 1 then
        return automation, nil
    end

    -- Find the actual point
    for _, point in ipairs(automation.points) do
        if point.time == line then
            return automation, point
        end
    end

    return automation, nil
end

function AutomationHelpers.get_automation_and_prev_point(automation_parameter)
    if not automation_parameter then
        return nil, nil
    end

    local song = renoise.song()
    local automation = song.selected_pattern_track:find_automation(automation_parameter)
    if not automation then
        return nil, nil
    end

    local current_line = song.selected_line_index
    local prev_point = nil
    local latest_time = 0

    -- Find the most recent automation point before current line
    for _, point in ipairs(automation.points) do
        if point.time < current_line and point.time > latest_time then
            prev_point = point
            latest_time = point.time
        end
    end

    return automation, prev_point
end

function AutomationHelpers.create_or_get_automation(automation_parameter)
    if not automation_parameter then
        return nil
    end

    local song = renoise.song()
    local automation = song.selected_pattern_track:find_automation(automation_parameter)

    if not automation then
        if automation_parameter.is_automatable then
            automation = song.selected_pattern_track:create_automation(automation_parameter)
        else
            return nil
        end
    end

    return automation
end

-- Function to get all existing automations on the current track
function AutomationHelpers.get_all_track_automations()
    local song = renoise.song()
    local pattern_track = song.selected_pattern_track
    local automations = {}

    if pattern_track and pattern_track.automation then
        for _, automation in ipairs(pattern_track.automation) do
            if automation.dest_parameter then
                table.insert(automations, automation.dest_parameter)
            end
        end
    end

    return automations
end

return AutomationHelpers