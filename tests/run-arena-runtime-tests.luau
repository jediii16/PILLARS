local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local server = ServerScriptService:WaitForChild("Server")
local arenaModules = server:WaitForChild("Arena")
local ArenaConfig = require(arenaModules.ArenaConfig)

RunService:Run()
task.wait(0.5)

local arena = Workspace:FindFirstChild(ArenaConfig.GENERATED_MODEL_NAME)
assert(arena and arena:IsA("Model"), "server startup must generate one arena model")

local voidBoundary = arena:FindFirstChild("VoidBoundary")
assert(voidBoundary and voidBoundary:IsA("Model"), "generated arena must contain one logical void boundary")

local voidTile = voidBoundary:FindFirstChild("VoidTile01")
assert(voidTile and voidTile:IsA("Part"), "logical void boundary must contain touch tiles")
assert(not voidTile.CanCollide, "runtime void tiles must remain non-collidable")
assert(voidTile.CanTouch, "runtime void tiles must retain touch detection")

local character = Instance.new("Model")
character.Name = "VoidBoundaryTestCharacter"

local humanoid = Instance.new("Humanoid")
humanoid.Parent = character

local rootPart = Instance.new("Part")
rootPart.Name = "HumanoidRootPart"
rootPart.Size = Vector3.new(2, 2, 1)
rootPart.CFrame = voidTile.CFrame + Vector3.new(0, 8, 0)
rootPart.Parent = character

character.PrimaryPart = rootPart
character.Parent = Workspace

task.wait(1)
RunService:Pause()

assert(humanoid.Health == 0, "touching the void boundary must eliminate a Humanoid")

character:Destroy()
task.wait()
arena:Destroy()
task.wait()
print("PILLARS_ARENA_RUNTIME_TESTS_PASSED")
