local Util = script.Parent
local Error = require(Util.Error)

return function(condition, message, level)
	if not condition then
		Error(message, level and level + 1 or 4)
	end
end
