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

function AmountNibbleParam.new(config)
    local self = setmetatable({}, AmountNibbleParam)
    self.num_prop = config.number_property
    self.amt_prop = config.amount_property
    self.is_high  = config.is_high_nibble
    self.get_cmd  = config.get_effect_command
    return self
end

function AmountNibbleParam:_command(col)
    return self.get_cmd(col[self.num_prop])
end

function AmountNibbleParam:getter(col)
    local cmd = self:_command(col)
    if self.is_high then
        if cmd and cmd.is_xy then
            return math.floor(col[self.amt_prop] / 16)
        else
            return col[self.amt_prop]
        end
    else
        if cmd and cmd.is_xy then
            return col[self.amt_prop] % 16
        end
        return 0
    end
end

function AmountNibbleParam:setter(col, value, _)
    local cmd = self:_command(col)
    if self.is_high then
        if cmd and cmd.is_xy then
            local low = col[self.amt_prop] % 16
            col[self.amt_prop] = value * 16 + low
        else
            col[self.amt_prop] = value
        end
    else
        if cmd and cmd.is_xy then
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
            local cmd = self:_command(col)
            if cmd then
                if cmd.is_xy then
                    return cmd.x_max
                end
                return cmd.max
            end
        end
        return 255
    else
        if col then
            local cmd = self:_command(col)
            if cmd and cmd.is_xy then
                return cmd.y_max
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