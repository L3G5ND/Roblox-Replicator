local RS = game:GetService("ReplicatedStorage")

local Packages = RS:FindFirstChild('Packages')

local packageName = 'Signal'

if Packages then
    if Packages:FindFirstChild(packageName) then
        return require(Packages[packageName])
    elseif script.Parent.Parent:FindFirstChild(packageName) then
        return require(script.Parent.Parent[packageName])
    end
    error("Coudln't find package ["..packageName.."]")
end
