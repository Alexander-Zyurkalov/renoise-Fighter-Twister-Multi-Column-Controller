-- AmountNibbleParam: high or low nibble of an effect amount value.
-- For xy-type effects the byte is split into two 4-bit nibbles.
-- For xx-type effects the high nibble controls the full byte and the low nibble is disabled (max 0).
-- Covers: fx_amount_x, fx_amount_y, effect_amount_x, effect_amount_y.
--
-- Config:
--   number_property     (string)    property holding the 16-bit command id, e.g. "effect_number_value" or "number_value"
--   amount_property     (string)    property holding the amount byte, e.g. "effect_amount_value" or "amount_value"
--   is_high_nibble      (boolean)   true = x (bits 7-4), false = y (bits 3-0)
--   get_effect_command   (function)  lookup function(number_value) -> command table or nil

local AmountNibbleParam = {}
AmountNibbleParam.__index = AmountNibbleParam

-- Effect command definitions
-- Maps first character value (xx byte of effect_number) to x/y nibble max values
-- Character encoding: 0-9 = digits, 10-35 = A-Z
-- These apply to both note column fx (effect_number_value) and effect columns (number_value)
local EFFECT_COMMANDS = {
    [10] = { name = "A", is_xy = true, x_max = 15, y_max = 15 }, -- Arpeggio (xy)
    [11] = { name = "B", is_xy = false, max = 1 }, -- Backwards (00=back, 01=fwd)
    [12] = { name = "C", is_xy = true, x_max = 15, y_max = 15 }, -- Cut volume (xy)
    [13] = { name = "D", is_xy = false, max = 255 }, -- Pitch down (xx)
    [14] = { name = "E", is_xy = false, max = 255 }, -- Envelope pos (xx)
    [16] = { name = "G", is_xy = false, max = 255 }, -- Glide (xx)
    [18] = { name = "I", is_xy = false, max = 255 }, -- Fade in (xx)
    [23] = { name = "N", is_xy = true, x_max = 15, y_max = 15 }, -- Auto pan (xy)
    [24] = { name = "O", is_xy = false, max = 255 }, -- Fade out (xx)
    [28] = { name = "S", is_xy = false, max = 255 }, -- Trigger slice (xx)
    [29] = { name = "T", is_xy = true, x_max = 15, y_max = 15 }, -- Tremolo (xy)
    [30] = { name = "U", is_xy = false, max = 255 }, -- Pitch up (xx)
    [31] = { name = "V", is_xy = true, x_max = 15, y_max = 15 }, -- Vibrato (xy)
}

-- Helper: get effect command info from a 16-bit effect_number value (0xXXYY)
local function get_effect_command(effect_number_value)
    local xx = math.floor(effect_number_value / 256)
    return EFFECT_COMMANDS[xx]
end


function AmountNibbleParam.new(config)
    local self = setmetatable({}, AmountNibbleParam)
    self.num_prop = config.number_property
    self.amt_prop = config.amount_property
    self.is_high  = config.is_high_nibble
    return self
end

function AmountNibbleParam:_command(col)
    return get_effect_command(col[self.num_prop])
end

function AmountNibbleParam:getter(col)
    local command = self:_command(col)
    if self.is_high then
        if command and command.is_xy then
            return math.floor(col[self.amt_prop] / 16)
        else
            return col[self.amt_prop]
        end
    else
        if command and command.is_xy then
            return col[self.amt_prop] % 16
        end
        return 0
    end
end

function AmountNibbleParam:setter(col, value, _)
    local command = self:_command(col)
    if self.is_high then
        if command and command.is_xy then
            local low = col[self.amt_prop] % 16
            col[self.amt_prop] = value * 16 + low
        else
            col[self.amt_prop] = value
        end
    else
        if command and command.is_xy then
            local high = math.floor(col[self.amt_prop] / 16)
            col[self.amt_prop] = high * 16 + value
        end
    end
end

function AmountNibbleParam:min_value(_)
    return 0
end

function AmountNibbleParam:max_value(col)
    if self.is_high then
        if col then
            local command = self:_command(col)
            if command then
                if command.is_xy then
                    return command.x_max
                end
                return command.max
            end
        end
        return 255
    else
        if col then
            local command = self:_command(col)
            if command and command.is_xy then
                return command.y_max
            end
        end
        return 0
    end
end

-- Absent when the command itself is empty (number property == 0)
function AmountNibbleParam:is_absent(col)
    return col[self.num_prop] == 0
end

function AmountNibbleParam:default_value(_)
    return 0
end

return AmountNibbleParam