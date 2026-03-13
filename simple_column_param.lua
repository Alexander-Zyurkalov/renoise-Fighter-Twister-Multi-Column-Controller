-- SimpleColumnParam: for columns backed by a single property on the column object.
-- Covers: note, volume, pan, delay.
--
-- Config:
--   property        (string)  column property name, e.g. "note_value"
--   max             (number)  maximum value
--   absent_sentinel (number)  the raw value that means "empty"
--   default         (number)  default value when nothing found  (optional, 0)

local SimpleColumnParam = {}
SimpleColumnParam.__index = SimpleColumnParam

function SimpleColumnParam.new(config)
    local self = setmetatable({}, SimpleColumnParam)
    self.property        = config.property
    self.min             = config.min or 0
    self.max             = config.max
    self.absent_sentinel = config.absent_sentinel
    self.default         = config.default or 0
    return self
end

function SimpleColumnParam:getter(col)
    return col[self.property]
end

function SimpleColumnParam:setter(col, value, _)
    col[self.property] = value
end

function SimpleColumnParam:min_value()
    return self.min
end

function SimpleColumnParam:max_value()
    return self.max
end

function SimpleColumnParam:is_absent(col)
    return col[self.property] == self.absent_sentinel
end

function SimpleColumnParam:default_value()
    return self.default
end

return SimpleColumnParam