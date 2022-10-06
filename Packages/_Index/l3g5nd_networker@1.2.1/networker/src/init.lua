local RunService = game:GetService("RunService")

local Networker = {}
Networker._Networkers = {}

local networkerTypeNameEnding = {
	RemoteEvent = "Event",
	RemoteFunction = "Function",
	BindableEvent = "BindableEvent",
	BindableFunction = "BindableFunction",
}

local function createNetworker(api, networkerType)
	local path = Networker._Networkers
	for i, v in pairs(string.split(api, "/")) do
		if not path[v] then
			path[v] = {}
		end
		path = path[v]
	end
	if path[networkerType] then
		path[networkerType]:Destroy()
	end
	path[networkerType] = Instance.new(networkerType, script)
	path[networkerType].Name = api .. networkerTypeNameEnding[networkerType]

	return path[networkerType]
end

local function hasNetworker(api, networkerType)
	return script:FindFirstChild(api .. networkerTypeNameEnding[networkerType]) ~= nil
end

local function getNetworker(api, networkerType)
	local networker
	local startTime = os.time()
	while true do
		networker = script:FindFirstChild(api .. networkerTypeNameEnding[networkerType])
		if networker then
			break
		end
		if os.time() - startTime >= 10 then
			error(api .. " ("..networkerType..") never created on the server", 1)
		end
		RunService.Heartbeat:Wait()
	end
	return networker
end

local function getNetworkerOrCreate(api, networkerType)
	local networker
	if not hasNetworker(api, networkerType) then
		networker = createNetworker(api, networkerType)
	else
		networker = getNetworker(api, networkerType)
	end
	return networker
end

if RunService:IsServer() then
	Networker.OnEvent = function(api, func)
		getNetworkerOrCreate(api, "RemoteEvent").OnServerEvent:Connect(func)
	end

	Networker.OnInvoke = function(api, func)
		getNetworkerOrCreate(api, "RemoteFunction").OnServerInvoke = func
	end

	Networker.OnBindableEvent = function(api, func)
		getNetworkerOrCreate(api, "BindableEvent").Event:Connect(func)
	end

	Networker.OnBindableInvoke = function(api, func)
		getNetworkerOrCreate(api, "BindableFunction").OnInvoke = func
	end

	Networker.Send = function(api, client, ...)
		getNetworker(api, "RemoteEvent"):FireClient(client, ...)
	end

	Networker.SendAll = function(api, ...)
		getNetworker(api, "RemoteEvent"):FireAllClients(...)
	end

	Networker.Get = function(api, client, ...)
		return getNetworker(api, "RemoteFunction"):InvokeClient(client, ...)
	end

	Networker.Fire = function(api, ...)
		getNetworker(api, "BindableEvent"):Fire(...)
	end

	Networker.Invoke = function(api, ...)
		getNetworker(api, "BindableFunction"):Invoke(...)
	end
else
	Networker.OnEvent = function(api, func)
		getNetworker(api, "RemoteEvent").OnClientEvent:Connect(func)
	end

	Networker.OnInvoke = function(api, func)
		getNetworker(api, "RemoteFunction").OnClientInvoke = func
	end

	Networker.OnBindableEvent = function(api, func)
		getNetworkerOrCreate(api, "BindableEvent").BindableEvent.OnEvent:Connect(func)
	end

	Networker.OnBindableInvoke = function(api, func)
		getNetworkerOrCreate(api, "BindableFunction").BindableFunction.OnInvoke = func
	end

	Networker.Send = function(api, ...)
		getNetworker(api, "RemoteEvent"):FireServer(...)
	end

	Networker.Get = function(api, ...)
		return getNetworker(api, "RemoteFunction"):InvokeServer(...)
	end

	Networker.Fire = function(api, ...)
		getNetworker(api, "BindableEvent"):Fire(...)
	end

	Networker.Invoke = function(api, ...)
		getNetworker(api, "BindableFunction"):Invoke(...)
	end
end

Networker.createNetworker = function(api, networkerType)
	assert(networkerTypeNameEnding[networkerType], networkerType .. " is not a valid NetworkerType")
	createNetworker(api, networkerType)
end
Networker.getNetworker = getNetworker
Networker.getNetworkerOrCreate = getNetworkerOrCreate
Networker.hasNetworker = hasNetworker

return Networker
