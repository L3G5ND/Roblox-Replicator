local RS = game:GetService("ReplicatedStorage")

local Util = script.Parent.Util
local Error = require(Util.Error)

local Packages = RS:FindFirstChild("Packages")

if Packages then
	local Package = Packages:FindFirstChild("Networker")
	if Package then
		return require(Package)
	end
end

Error("Couldn't find 'Networker' in 'ReplicatedStorage.Packages'")
