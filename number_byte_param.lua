-- NumberByteParam: high or low byte of a 16-bit column property.
-- Covers: fx_number_xx, fx_number_yy, effect_number_xx, effect_number_yy.
--
-- Config:
--   value_property  (string)   the 16-bit property, e.g. "effect_number_value" or "number_value"
--   is_high_byte    (boolean)  true = xx (bits 15-8), false = yy (bits 7-0)

local NumberByteParam = {}
NumberByteParam.__index = NumberByteParam

function NumberByteParam.new(config)
    local self = setmetatable({}, NumberByteParam)
    self.prop    = config.value_property
    self.is_high = config.is_high_byte
    return self
end

function NumberByteParam:getter(col)
    if self.is_high then
        return math.floor(col[self.prop] / 256)
    else
        return col[self.prop] % 256
    end
end

function NumberByteParam:setter(col, value, _)
    if self.is_high then
        local low = col[self.prop] % 256
        col[self.prop] = value * 256 + low
    else
        local high = math.floor(col[self.prop] / 256)
        col[self.prop] = high * 256 + value
    end
end

function NumberByteParam:min_value(_)
    return 0
end

function NumberByteParam:max_value(_)
    return 35
end

function NumberByteParam:is_absent(col)
    if self.is_high then
        return math.floor(col[self.prop] / 256) == 0
    else
        return col[self.prop] % 256 == 0
    end
end

function NumberByteParam:default_value(_)
    return 0
end

return NumberByteParam