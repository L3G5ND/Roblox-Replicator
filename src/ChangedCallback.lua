local Package = script.Parent

local Util = Package.Util
local Assert = require(Util.Assert)
local DeepEqual = require(Util.DeepEqual)

local function getPath(path, tbl)
	if typeof(tbl) ~= "table" then
		return nil
	end
	local currentPath = tbl
	for _, value in pairs(path) do
		currentPath = currentPath[value]
		if not currentPath then
			return nil
		end
	end
	return currentPath
end

return function(...)
	local args = { ... }
	if #args == 1 then
		local callback = args[1]
		Assert(typeof(callback) == "function", "Invalid argument #1 (type 'function' expected)")

		return callback
	elseif #args == 2 then
		local arg1Type = typeof(args[1])
		Assert(arg1Type == "string" or arg1Type == "table", "Invalid argument #1 (must be type 'string' or 'table')")

		if arg1Type == "string" then
			local key = args[1]
			local callback = args[2]

			return function(newData, oldData)
				local newValue = newData[key]
				local oldValue = oldData[key]
				if not DeepEqual(newValue, oldValue) then
					callback(newValue, oldValue)
				end
			end
		elseif arg1Type == "table" then
			local path = args[1]
			local callback = args[2]

			return function(newData, oldData)
				local newValue = getPath(path, newData)
				local oldValue = getPath(path, oldData)
				if not DeepEqual(newValue, oldValue) then
					callback(newValue, oldValue)
				end
			end
		end
	end
end
