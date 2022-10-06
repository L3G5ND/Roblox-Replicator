local RS = game:GetService('ReplicatedStorage')
local Networker = script.Parent.Parent:FindFirstChild('Networker')
if not Networker then
    return require(RS.Packages.Networker)
else
    return require(Networker)
end