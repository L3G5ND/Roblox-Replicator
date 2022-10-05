local Package = script.Parent

local Util = Package.Util
local Assert = require(Util.Assert)
local TypeMarker = require(Util.TypeMarker)
local Type = require(Util.Type)

local Signal = {}
Signal.type = TypeMarker.Mark("Signal")

Signal.new = function()
	local self = setmetatable({}, { __index = Signal })
	self._connections = {}
	Type.SetType(self, Signal.type)
	return self
end

function Signal:Connect(callback)
	Assert(typeof(callback) == "function", "Invalid argument #1 (Must be of type 'function')", 4)

	local index = #self._connections + 1
	self._connections[index] = callback

	return function()
		self._connections[index] = nil
	end
end

function Signal:Fire(...)
	local args = { ... }
	self._firing = true
	for _, callback in pairs(self._connections) do
		callback(table.unpack(args))
	end
	self._firing = false
end

function Signal:FireAsync(...)
	local args = { ... }
	self._firing = true
	for _, callback in pairs(self._connections) do
		coroutine.wrap(function()
			callback(table.unpack(args))
		end)()
	end
	self._firing = false
end

function Signal:Disconnect()
	for key, _ in pairs(self._connections) do
		self._connections[key] = nil
	end
end

function Signal:Destroy()
	for key, _ in pairs(self) do
		self[key] = nil
	end
end

return Signal
