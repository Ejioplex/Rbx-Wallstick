-- CONSTANTS

local RunService = game:GetService("RunService")

local CONSTANTS = require(script:WaitForChild("Constants"))

local ZERO3 = Vector3.new(0, 0, 0)
local UNIT_Y = Vector3.new(0, 1, 0)

local Remotes = script:WaitForChild("Remotes")
local Utility = script:WaitForChild("Utility")
local CharacterModules = script:WaitForChild("CharacterModules")

local Maid = require(Utility:WaitForChild("Maid"))
local Signal = require(Utility:WaitForChild("Signal"))
local Camera = require(CharacterModules:WaitForChild("Camera"))
local Control = require(CharacterModules:WaitForChild("Control"))
local Animation = require(CharacterModules:WaitForChild("Animation"))
local Physics = require(script:WaitForChild("Physics"))

local ReplicatePhysics = Remotes:WaitForChild("ReplicatePhysics")

-- Class

local WallstickClass = {}
WallstickClass.__index = WallstickClass
WallstickClass.ClassName = "Wallstick"

-- Public Constructors

function WallstickClass.new(player)
	local self = setmetatable({}, WallstickClass)

	self.Player = player
	self.Character = player.Character
	self.Humanoid = player.Character:WaitForChild("Humanoid")
	self.HRP = self.Humanoid.RootPart
	self.Physics = Physics.new(self)

	self._camera = Camera.new(self)
	self._control = Control.new(self)
	self._animation = Animation.new(self)

	self._replicateTick = -1
	self._collisionParts = {}
	self._fallStart = 0

	self.Maid = Maid.new()
	self.Falling = Signal.new()

	self.Part = nil
	self.Normal = UNIT_Y
	self.Mode = nil

	init(self)

	return self
end

-- Private Methods

local function setCollisionGroupId(array, id)
	for _, part in pairs(array) do
		if part:IsA("BasePart") then
			part.CollisionGroupId = id
		end
	end
end

local function generalStep(self, dt)
	self.HRP.Velocity = ZERO3
	self.HRP.RotVelocity = ZERO3
	self.HRP.CFrame = self.Part.CFrame * self.Physics.Floor.CFrame:ToObjectSpace(self.Physics.HRP.CFrame)

	if not self.Part.Parent then
		self:Set(workspace.Terrain, UNIT_Y)
	end

	self.Physics:MatchHumanoid(self.Humanoid)
	self.Physics:UpdateGyro()
	self._camera:SetUpVector(self.Part.CFrame:VectorToWorldSpace(self.Normal))
end

local function collisionStep(self, dt)
	local parts = workspace:FindPartsInRegion3WithIgnoreList(Region3.new(
		self.HRP.Position - CONSTANTS.COLLIDER_SIZE2,
		self.HRP.Position + CONSTANTS.COLLIDER_SIZE2
	), {self.Character, self.Physics.World}, 1000)

	local newCollisionParts = {}
	local collisionParts = self._collisionParts

	local stickPart = self.Part
	local stickPartCF = stickPart.CFrame
	local floorCF = self.Physics.Floor.CFrame

	for _, part in pairs(parts) do
		if collisionParts[part] then
			local physicsPart = collisionParts[part]
			physicsPart.CFrame = floorCF:ToWorldSpace(stickPartCF:ToObjectSpace(part.CFrame))
			physicsPart.CanCollide = part.CanCollide

			newCollisionParts[part] = physicsPart
		elseif part ~= stickPart and part.CanCollide then
			local physicsPart

			if CONSTANTS.IGNORE_CLASS_PART[part.ClassName] then
				physicsPart = Instance.new("Part")
				physicsPart.CanCollide = part.CanCollide
				physicsPart.Size = part.Size
			else
				physicsPart = part:Clone()
				physicsPart:ClearAllChildren()
			end

			physicsPart.Transparency = CONSTANTS.DEBUG_TRANSPARENCY
			physicsPart.Anchored = true
			physicsPart.Velocity = ZERO3
			physicsPart.RotVelocity = ZERO3
			physicsPart.Parent = self.Physics.Collision

			newCollisionParts[part] = physicsPart
			collisionParts[part] = physicsPart
		end
	end

	self.Physics.Floor.CanCollide = stickPart.CanCollide

	for part, physicsPart in pairs(collisionParts) do
		if not newCollisionParts[part] then
			collisionParts[part] = nil
			physicsPart:Destroy()
		end
	end
end

local function characterStep(self, dt)
	local move = self._control:GetMoveVector()
	
	if self.Mode ~= "Debug" then
		local cameraCF = workspace.Camera.CFrame
		local physicsCameraCF = self.Physics.HRP.CFrame * self.HRP.CFrame:ToObjectSpace(cameraCF)

		local c, s
		local _, _, _, R00, R01, R02, _, R11, R12, _, _, R22 =  physicsCameraCF:GetComponents()
		local q = math.sign(R11)

		if R12 < 1 and R12 > -1 then
			c = R22
			s = R02
		else
			c = R00
			s = -R01*math.sign(R12)
		end
		
		local norm = math.sqrt(c*c + s*s)
		move = Vector3.new(
			(c*move.x*q + s*move.z)/norm,
			0,
			(c*move.z - s*move.x*q)/norm
		)
	
		self.Physics.Humanoid:Move(move, false)
	else
		self.Physics.Humanoid:Move(move, true)
	end

	local physicsHRPCF = self.Physics.HRP.CFrame
	self.HRP.Velocity = self.HRP.CFrame:VectorToWorldSpace(physicsHRPCF:VectorToObjectSpace(self.Physics.HRP.Velocity))
	self.HRP.RotVelocity = self.HRP.CFrame:VectorToWorldSpace(physicsHRPCF:VectorToObjectSpace(self.Physics.HRP.RotVelocity))

	for _, enum in pairs(Enum.HumanoidStateType:GetEnumItems()) do
		if not CONSTANTS.IGNORE_STATES[enum] then
			self.Humanoid:SetStateEnabled(enum, false)
		end
	end

	local targetState = self.Physics.Humanoid:GetState()
	self.Humanoid:SetStateEnabled(targetState, true)
	self.Humanoid:ChangeState(targetState)

	if targetState == Enum.HumanoidStateType.Freefall then
		local height = self.Physics.HRP.Position.y
		self.Falling:Fire(height, self._fallStart - height)
	end
end

local function replicateStep(self, dt)
	local t = os.clock()
	if t - self._replicateTick >= CONSTANTS.REPLICATE_RATE then
		local offset = self.Physics.Floor.CFrame:ToObjectSpace(self.Physics.HRP.CFrame)
		ReplicatePhysics:FireServer(self.Part, offset, false)
		self._replicateTick = t
	end
end

function init(self)
	setCollisionGroupId(self.Character:GetChildren(), CONSTANTS.PHYSICS_ID)

	self:SetMode(CONSTANTS.DEFAULT_CAMERA_MODE)
	self:Set(workspace.Terrain, UNIT_Y)

	self.Maid:Mark(self._camera)
	self.Maid:Mark(self._control)
	self.Maid:Mark(self._animation)
	self.Maid:Mark(self.Physics)

	self.Maid:Mark(self.Physics.Humanoid.Died:Connect(function()
		self:Destroy()
	end))

	self.Maid:Mark(self.Physics.Character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:Destroy()
		end
	end))

	self.Maid:Mark(self.Humanoid.Died:Connect(function()
		self:Destroy()
	end))

	self.Maid:Mark(self.Character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self:Destroy()
		end
	end))

	self.Maid:Mark(self.Physics.Humanoid.StateChanged:Connect(function(_, new)
		if new == Enum.HumanoidStateType.Freefall then
			self._fallStart = self.Physics.HRP.Position.y
		end
	end))

	RunService:BindToRenderStep("WallstickStep", Enum.RenderPriority.Camera.Value - 1, function(dt)
		generalStep(self, dt)
		collisionStep(self, dt)
		characterStep(self, dt)
		replicateStep(self, dt)
	end)
end

-- Public Methods

function WallstickClass:SetMode(mode)
	self.Mode = mode
	self._camera:SetMode(mode)
end

function WallstickClass:Set(part, normal, teleportCF)
	local physicsHRP = self.Physics.HRP
	local vel = physicsHRP.CFrame:VectorToObjectSpace(physicsHRP.Velocity)
	local rotVel = physicsHRP.CFrame:VectorToObjectSpace(physicsHRP.RotVelocity)

	self.Physics:UpdateFloor(self.Part, part, self.Normal, normal)
	self.Part = part
	self.Normal = normal

	if self._collisionParts[part] then
		self._collisionParts[part]:Destroy()
		self._collisionParts[part] = nil
	end

	local camera = workspace.CurrentCamera
	local cameraOffset = self.Physics.HRP.CFrame:ToObjectSpace(camera.CFrame)
	local focusOffset = self.Physics.HRP.CFrame:ToObjectSpace(camera.Focus)

	physicsHRP.CFrame = self.Physics.Floor.CFrame * part.CFrame:ToObjectSpace(teleportCF or self.HRP.CFrame)
	
	if CONSTANTS.MAINTAIN_WORLD_VELOCITY then
		physicsHRP.Velocity = physicsHRP.CFrame:VectorToWorldSpace(vel)
		physicsHRP.RotVelocity = physicsHRP.CFrame:VectorToWorldSpace(rotVel)
	end

	self._camera:SetSpinPart(part)

	if self.Mode == "Debug" then
		camera.CFrame = self.Physics.HRP.CFrame:ToWorldSpace(cameraOffset)
		camera.Focus = self.Physics.HRP.CFrame:ToWorldSpace(focusOffset)
	end
end

function WallstickClass:Destroy()
	setCollisionGroupId(self.Character:GetChildren(), 0)
	RunService:UnbindFromRenderStep("WallstickStep")
	ReplicatePhysics:FireServer(nil, nil, true)
	self.Maid:Sweep()
end

--

return WallstickClass