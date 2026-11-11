-- Dex Explorer v1.1.0 -> Matcha Luau Port
-- Preserves the Dex v1.1.0 UI & workflow via Matcha's Drawing library.
-- Skipped impossible standard-Roblox features: Instance.new / Clone / Group / Ungroup / non-bound Roblox properties.

if _G.DEX_MATCHA_CLEANUP then
	pcall(_G.DEX_MATCHA_CLEANUP)
end

local S = {}   -- Shared state, services, schema, tree, selection, clipboard
local F = {}   -- Shared helpers, tree/search, properties, actions, input, UI
local UI = {}  -- Drawing pools, layout, window/scroll/input state
local VK = {}  -- Windows virtual keycodes

--=====================================================================
-- 1. SERVICES, SAFE INSTANCE HELPERS & TIME/CLIPBOARD
--=====================================================================
(function()
	S.alive = true
	S.connections = {}
	S.drawings = {}
	S.lastRefresh = 0
	S.autoRefresh = true
	S.showHiddenServices = false
	S.selectionEsp = true
	S.espTargets = {}
	S.clickSelectMode = false
	S.pickableParts = {}
	S.lastPickCacheTime = 0
	S.hoverPickTarget = nil

	function F.getService(name)
		local ok, svc = pcall(function() return game:GetService(name) end)
		if ok and svc ~= nil then return svc end
		local ok2, svc2 = pcall(function() return game:FindFirstChild(name) end)
		if ok2 and svc2 ~= nil then return svc2 end
		local ok3, svc3 = pcall(function() return game:FindFirstChildOfClass(name) end)
		if ok3 and svc3 ~= nil then return svc3 end
		return nil
	end

	function F.initServices()
		S.Workspace = S.Workspace or workspace or F.getService("Workspace")
		S.Players = S.Players or F.getService("Players")
		S.RunService = S.RunService or F.getService("RunService")
		S.UserInputService = S.UserInputService or F.getService("UserInputService")
		S.HttpService = S.HttpService or F.getService("HttpService")
		if S.Players and not S.lp then
			local okL, lpObj = pcall(function() return S.Players.LocalPlayer end)
			if okL and lpObj ~= nil then S.lp = lpObj end
		end
		if S.lp and not S.mouse then
			local okM, mObj = pcall(function() return S.lp:GetMouse() end)
			if okM and mObj ~= nil then S.mouse = mObj end
		end
	end

	F.initServices()

	function F.trackConn(c)
		if c then S.connections[#S.connections + 1] = c end
		return c
	end

	function F.newDraw(kind, props)
		local d = Drawing.new(kind)
		if kind == "Square" or kind == "Circle" or kind == "Triangle" or kind == "Quad" then
			pcall(function() d.Outline = false end)
		elseif kind == "Text" then
			pcall(function() d.Outline = false end)
		end
		if props then
			for k, v in pairs(props) do
				pcall(function() d[k] = v end)
			end
		end
		S.drawings[#S.drawings + 1] = d
		return d
	end

	function F.addrOf(inst)
		if not inst then return nil end
		local ok, addr = pcall(function() return inst.Address end)
		if ok and addr ~= nil then return addr end
		return nil
	end

	function F.safeName(inst)
		local ok, v = pcall(function() return inst.Name end)
		return ok and tostring(v or "") or "<dead>"
	end

	function F.safeClass(inst)
		local ok, v = pcall(function() return inst.ClassName end)
		return ok and tostring(v or "Instance") or "Instance"
	end

	function F.safeParent(inst)
		local ok, v = pcall(function() return inst.Parent end)
		return ok and v or nil
	end

	function F.safeChildren(inst)
		local ok, v = pcall(function() return inst:GetChildren() end)
		if ok and type(v) == "table" then return v end
		return {}
	end

	function F.safeFullName(inst)
		local ok, v = pcall(function() return inst:GetFullName() end)
		return ok and tostring(v or "") or F.safeName(inst)
	end

	function F.now()
		if tick then return tick() end
		if os and os.clock then return os.clock() end
		return 0
	end

	function F.trim(s)
		return tostring(s or ""):match("^%s*(.-)%s*$") or ""
	end

	function F.splitString(str, delim)
		local out = {}
		delim = delim or ","
		for w in string.gmatch(tostring(str or ""), "[^" .. delim .. "]+") do
			out[#out + 1] = w
		end
		return out
	end

	function F.round(num, dec)
		local m = 10 ^ (dec or 2)
		return math.floor(num * m + 0.5) / m
	end

	function F.pointInRect(pt, x, y, w, h)
		return pt.X >= x and pt.X <= x + w and pt.Y >= y and pt.Y <= y + h
	end

	function F.getViewport()
		local ok, vs = pcall(function()
			local cam = workspace and workspace.CurrentCamera
			return cam and cam.ViewportSize or nil
		end)
		if ok and vs and vs.X > 0 and vs.Y > 0 then return vs end
		return Vector2.new(1920, 1080)
	end

	function F.getMousePos()
		if S.mouse then
			local ok, x, y = pcall(function() return S.mouse.X, S.mouse.Y end)
			if ok and type(x) == "number" and type(y) == "number" then
				return Vector2.new(x, y)
			end
		end
		return Vector2.new(-9999, -9999)
	end

	function F.notify(title, msg, secs)
		if notify then
			pcall(notify, tostring(title), tostring(msg), secs or 3)
		end
	end

	function F.copyToClipboard(txt)
		if setclipboard then
			pcall(setclipboard, tostring(txt))
			return true
		end
		return false
	end

	local ruler = F.newDraw("Text", { Size = 14, Font = 0, Visible = false, Outline = false })
	function F.measureText(str, size, font)
		ruler.Size = size or 14
		ruler.Font = font or 0
		ruler.Text = tostring(str or "")
		local tb = ruler.TextBounds
		return tb and tb.X or (#tostring(str or "") * 7)
	end

	function F.fitText(str, maxPx, approxCharW)
		str = tostring(str or "")
		if maxPx <= 12 then return "" end
		local maxChars = math.max(1, math.floor(maxPx / (approxCharW or 6.6)))
		if #str <= maxChars then return str end
		if maxChars <= 3 then return str:sub(1, maxChars) end
		return str:sub(1, maxChars - 2) .. ".."
	end
end)();

--=====================================================================
-- 2. VIRTUAL KEYCODES & KEYBOARD HELPERS
--=====================================================================
(function()
	VK.BACKSPACE = 0x08; VK.TAB = 0x09; VK.ENTER = 0x0D; VK.SHIFT = 0x10
	VK.CTRL = 0x11; VK.ALT = 0x12; VK.ESCAPE = 0x1B; VK.SPACE = 0x20
	VK.PGUP = 0x21; VK.PGDN = 0x22; VK.END = 0x23; VK.HOME = 0x24
	VK.LEFT = 0x25; VK.UP = 0x26; VK.RIGHT = 0x27; VK.DOWN = 0x28
	VK.INSERT = 0x2D; VK.DELETE = 0x2E
	VK.F4 = 0x73
	VK.LSHIFT = 0xA0; VK.RSHIFT = 0xA1; VK.LCTRL = 0xA2; VK.RCTRL = 0xA3

	local NUM_SHIFT = { ["0"]=")",["1"]="!",["2"]="@",["3"]="#",["4"]="$",["5"]="%",["6"]="^",["7"]="&",["8"]="*",["9"]="(" }
	local PUNCT = {
		[0x20]={" "," "}, [0xBA]={";",":"}, [0xBB]={"=","+"}, [0xBC]={",","<"},
		[0xBD]={"-","_"}, [0xBE]={".",">"}, [0xBF]={"/","?"}, [0xC0]={"`","~"},
		[0xDB]={"[","{"}, [0xDC]={"\\","|"}, [0xDD]={"]","}"}, [0xDE]={"'","\""},
	}

	function F.isKeyDown(vk)
		if iskeypressed then
			local ok, r = pcall(iskeypressed, vk)
			if ok and r then return true end
		end
		if S.UserInputService then
			local ok2, r2 = pcall(function() return S.UserInputService:IsKeyDown(vk) end)
			if ok2 and r2 then return true end
		end
		return false
	end

	function F.isShiftDown()
		return F.isKeyDown(VK.SHIFT) or F.isKeyDown(VK.LSHIFT) or F.isKeyDown(VK.RSHIFT)
	end

	function F.isCtrlDown()
		return F.isKeyDown(VK.CTRL) or F.isKeyDown(VK.LCTRL) or F.isKeyDown(VK.RCTRL)
	end

	function F.isAltDown()
		return F.isKeyDown(VK.ALT) or F.isKeyDown(0xA4) or F.isKeyDown(0xA5)
	end

	function F.keyToChar(vk)
		local shifted = F.isShiftDown()
		if vk >= 0x41 and vk <= 0x5A then
			local b = string.char(vk + 32)
			return shifted and b:upper() or b
		elseif vk >= 0x30 and vk <= 0x39 then
			local d = tostring(vk - 0x30)
			return shifted and NUM_SHIFT[d] or d
		elseif PUNCT[vk] then
			return shifted and PUNCT[vk][2] or PUNCT[vk][1]
		end
		return nil
	end
end)();

--=====================================================================
-- 3. CLASS HIERARCHY, EXPLORER ORDER, ICON STYLES & MATCHA PROP SCHEMA
--=====================================================================
(function()
	S.CLASS_SUPER = {
		["Instance"]=false, ["Accoutrement"]="Instance", ["Accessory"]="Accoutrement", ["Hat"]="Accoutrement",
		["AdService"]="Instance", ["AdvancedDragger"]="Instance", ["AnalyticsService"]="Instance",
		["Animation"]="Instance", ["AnimationController"]="Instance", ["AnimationTrack"]="Instance",
		["Animator"]="Instance", ["AssetService"]="Instance", ["Attachment"]="Instance",
		["BadgeService"]="Instance", ["BasePlayerGui"]="Instance", ["CoreGui"]="BasePlayerGui",
		["PlayerGui"]="BasePlayerGui", ["StarterGui"]="BasePlayerGui", ["Beam"]="Instance",
		["BinaryStringValue"]="Instance", ["BindableEvent"]="Instance", ["BindableFunction"]="Instance",
		["BodyMover"]="Instance", ["BodyAngularVelocity"]="BodyMover", ["BodyForce"]="BodyMover",
		["BodyGyro"]="BodyMover", ["BodyPosition"]="BodyMover", ["BodyThrust"]="BodyMover",
		["BodyVelocity"]="BodyMover", ["RocketPropulsion"]="BodyMover", ["BoolValue"]="Instance",
		["BrickColorValue"]="Instance", ["Button"]="Instance", ["CFrameValue"]="Instance",
		["CacheableContentProvider"]="Instance", ["MeshContentProvider"]="CacheableContentProvider",
		["SolidModelContentProvider"]="CacheableContentProvider", ["Camera"]="Instance",
		["ChangeHistoryService"]="Instance", ["CharacterAppearance"]="Instance",
		["BodyColors"]="CharacterAppearance", ["CharacterMesh"]="CharacterAppearance",
		["Clothing"]="CharacterAppearance", ["Pants"]="Clothing", ["Shirt"]="Clothing",
		["ShirtGraphic"]="CharacterAppearance", ["Skin"]="CharacterAppearance", ["Chat"]="Instance",
		["ClickDetector"]="Instance", ["CollectionService"]="Instance", ["Color3Value"]="Instance",
		["Configuration"]="Instance", ["Constraint"]="Instance", ["AlignOrientation"]="Constraint",
		["AlignPosition"]="Constraint", ["BallSocketConstraint"]="Constraint", ["HingeConstraint"]="Constraint",
		["LineForce"]="Constraint", ["RodConstraint"]="Constraint", ["RopeConstraint"]="Constraint",
		["SlidingBallConstraint"]="Constraint", ["CylindricalConstraint"]="SlidingBallConstraint",
		["PrismaticConstraint"]="SlidingBallConstraint", ["SpringConstraint"]="Constraint",
		["Torque"]="Constraint", ["VectorForce"]="Constraint", ["LinearVelocity"]="Constraint",
		["AngularVelocity"]="Constraint", ["ContentProvider"]="Instance",
		["ContextActionService"]="Instance", ["Controller"]="Instance", ["HumanoidController"]="Controller",
		["SkateboardController"]="Controller", ["VehicleController"]="Controller",
		["ControllerService"]="Instance", ["CookiesService"]="Instance", ["CustomEvent"]="Instance",
		["CustomEventReceiver"]="Instance", ["DataModelMesh"]="Instance", ["BevelMesh"]="DataModelMesh",
		["BlockMesh"]="BevelMesh", ["CylinderMesh"]="BevelMesh", ["FileMesh"]="DataModelMesh",
		["SpecialMesh"]="FileMesh", ["DataStoreService"]="Instance", ["Debris"]="Instance",
		["DebugSettings"]="Instance", ["DebuggerBreakpoint"]="Instance", ["DebuggerManager"]="Instance",
		["DebuggerWatch"]="Instance", ["Dialog"]="Instance", ["DialogChoice"]="Instance",
		["DoubleConstrainedValue"]="Instance", ["Dragger"]="Instance", ["Explosion"]="Instance",
		["FaceInstance"]="Instance", ["Decal"]="FaceInstance", ["Texture"]="Decal", ["Feature"]="Instance",
		["Hole"]="Feature", ["MotorFeature"]="Feature", ["Fire"]="Instance", ["FlagStandService"]="Instance",
		["FlyweightService"]="Instance", ["CSGDictionaryService"]="FlyweightService",
		["NonReplicatedCSGDictionaryService"]="FlyweightService", ["Folder"]="Instance", ["ForceField"]="Instance",
		["FriendService"]="Instance", ["FunctionalTest"]="Instance", ["GamePassService"]="Instance",
		["GameSettings"]="Instance", ["GamepadService"]="Instance", ["Geometry"]="Instance",
		["GlobalDataStore"]="Instance", ["OrderedDataStore"]="GlobalDataStore",
		["GoogleAnalyticsConfiguration"]="Instance", ["GroupService"]="Instance", ["GuiBase"]="Instance",
		["GuiBase2d"]="GuiBase", ["GuiObject"]="GuiBase2d", ["Frame"]="GuiObject", ["GuiButton"]="GuiObject",
		["ImageButton"]="GuiButton", ["TextButton"]="GuiButton", ["GuiLabel"]="GuiObject",
		["ImageLabel"]="GuiLabel", ["TextLabel"]="GuiLabel", ["Scale9Frame"]="GuiObject",
		["ScrollingFrame"]="GuiObject", ["TextBox"]="GuiObject", ["CanvasGroup"]="GuiObject",
		["ViewportFrame"]="GuiObject", ["VideoFrame"]="GuiObject",
		["LayerCollector"]="GuiBase2d", ["BillboardGui"]="LayerCollector", ["ScreenGui"]="LayerCollector",
		["GuiMain"]="ScreenGui", ["SurfaceGui"]="LayerCollector", ["GuiBase3d"]="GuiBase",
		["FloorWire"]="GuiBase3d", ["PVAdornment"]="GuiBase3d", ["HandleAdornment"]="PVAdornment",
		["BoxHandleAdornment"]="HandleAdornment", ["ConeHandleAdornment"]="HandleAdornment",
		["CylinderHandleAdornment"]="HandleAdornment", ["ImageHandleAdornment"]="HandleAdornment",
		["LineHandleAdornment"]="HandleAdornment", ["SphereHandleAdornment"]="HandleAdornment",
		["ParabolaAdornment"]="PVAdornment", ["SelectionBox"]="PVAdornment", ["SelectionSphere"]="PVAdornment",
		["PartAdornment"]="GuiBase3d", ["HandlesBase"]="PartAdornment", ["ArcHandles"]="HandlesBase",
		["Handles"]="HandlesBase", ["SurfaceSelection"]="PartAdornment", ["SelectionLasso"]="GuiBase3d",
		["SelectionPartLasso"]="SelectionLasso", ["SelectionPointLasso"]="SelectionLasso", ["GuiItem"]="Instance",
		["Backpack"]="GuiItem", ["BackpackItem"]="GuiItem", ["HopperBin"]="BackpackItem", ["Tool"]="BackpackItem",
		["Flag"]="Tool", ["ButtonBindingWidget"]="GuiItem", ["GuiRoot"]="GuiItem", ["Hopper"]="GuiItem",
		["StarterPack"]="GuiItem", ["GuiService"]="Instance", ["GuidRegistryService"]="Instance",
		["HapticService"]="Instance", ["Highlight"]="Instance", ["HttpRbxApiService"]="Instance",
		["HttpService"]="Instance", ["Humanoid"]="Instance", ["InputObject"]="Instance",
		["InsertService"]="Instance", ["InstancePacketCache"]="Instance", ["IntConstrainedValue"]="Instance",
		["IntValue"]="Instance", ["JointInstance"]="Instance", ["DynamicRotate"]="JointInstance",
		["RotateP"]="DynamicRotate", ["RotateV"]="DynamicRotate", ["Glue"]="JointInstance",
		["ManualSurfaceJointInstance"]="JointInstance", ["ManualGlue"]="ManualSurfaceJointInstance",
		["ManualWeld"]="ManualSurfaceJointInstance", ["Motor"]="JointInstance", ["Motor6D"]="Motor",
		["Rotate"]="JointInstance", ["Snap"]="JointInstance", ["VelocityMotor"]="JointInstance",
		["Weld"]="JointInstance", ["JointsService"]="Instance", ["Keyframe"]="Instance",
		["KeyframeSequence"]="Instance", ["KeyframeSequenceProvider"]="Instance",
		["Light"]="Instance", ["PointLight"]="Light", ["SpotLight"]="Light", ["SurfaceLight"]="Light",
		["Lighting"]="Instance", ["LobbyService"]="Instance", ["LocalWorkspace"]="Instance",
		["LocalizationService"]="Instance", ["LocalizationTable"]="Instance", ["LogService"]="Instance",
		["LoginService"]="Instance", ["LuaSettings"]="Instance", ["LuaSourceContainer"]="Instance",
		["BaseScript"]="LuaSourceContainer", ["CoreScript"]="BaseScript", ["Script"]="BaseScript",
		["LocalScript"]="Script", ["ModuleScript"]="LuaSourceContainer", ["LuaWebService"]="Instance",
		["MarketplaceService"]="Instance", ["MaterialService"]="Instance", ["Message"]="Instance",
		["Hint"]="Message", ["Mouse"]="Instance", ["PlayerMouse"]="Mouse", ["PluginMouse"]="Mouse",
		["NetworkMarker"]="Instance", ["NetworkPeer"]="Instance", ["NetworkClient"]="NetworkPeer",
		["NetworkServer"]="NetworkPeer", ["NetworkReplicator"]="Instance", ["ClientReplicator"]="NetworkReplicator",
		["ServerReplicator"]="NetworkReplicator", ["NetworkSettings"]="Instance",
		["NotificationService"]="Instance", ["NumberValue"]="Instance", ["ObjectValue"]="Instance",
		["OneQuarterClusterPacketCacheBase"]="Instance", ["PVInstance"]="Instance",
		["BasePart"]="PVInstance", ["CornerWedgePart"]="BasePart", ["FormFactorPart"]="BasePart",
		["Part"]="FormFactorPart", ["FlagStand"]="Part", ["Platform"]="Part", ["Seat"]="Part",
		["SkateboardPlatform"]="Part", ["SpawnLocation"]="Part", ["WedgePart"]="FormFactorPart",
		["MeshPart"]="BasePart", ["ParallelRampPart"]="BasePart", ["PartOperation"]="BasePart",
		["NegateOperation"]="PartOperation", ["UnionOperation"]="PartOperation", ["PrismPart"]="BasePart",
		["PyramidPart"]="BasePart", ["RightAngleRampPart"]="BasePart", ["Terrain"]="BasePart",
		["TrussPart"]="BasePart", ["VehicleSeat"]="BasePart", ["Model"]="PVInstance",
		["WorldModel"]="Model", ["RootInstance"]="Model", ["Workspace"]="RootInstance", ["Status"]="Model",
		["Pages"]="Instance", ["PartOperationAsset"]="Instance", ["ParticleEmitter"]="Instance",
		["Path"]="Instance", ["PathWaypoint"]="Instance", ["PathfindingService"]="Instance",
		["PersonalServerService"]="Instance", ["PhysicsPacketCache"]="Instance", ["PhysicsService"]="Instance",
		["PhysicsSettings"]="Instance", ["Player"]="Instance", ["PlayerScripts"]="Instance",
		["Players"]="Instance", ["Plugin"]="Instance", ["PluginManager"]="Instance",
		["PointsService"]="Instance", ["Pose"]="Instance", ["PostEffect"]="Instance",
		["BloomEffect"]="PostEffect", ["BlurEffect"]="PostEffect", ["ColorCorrectionEffect"]="PostEffect",
		["SunRaysEffect"]="PostEffect", ["ProximityPrompt"]="Instance", ["ProximityPromptService"]="Instance",
		["RayValue"]="Instance", ["RemoteEvent"]="Instance", ["RemoteFunction"]="Instance",
		["RenderSettings"]="Instance", ["ReplicatedFirst"]="Instance", ["ReplicatedStorage"]="Instance",
		["RobloxReplicatedStorage"]="Instance", ["RunService"]="Instance", ["RuntimeScriptService"]="Instance",
		["ScriptContext"]="Instance", ["ScriptDebugger"]="Instance", ["ScriptService"]="Instance",
		["Selection"]="Instance", ["ServerScriptService"]="Instance", ["ServerStorage"]="Instance",
		["ServiceProvider"]="Instance", ["DataModel"]="ServiceProvider", ["GenericSettings"]="ServiceProvider",
		["GlobalSettings"]="GenericSettings", ["UserSettings"]="GenericSettings",
		["Sky"]="Instance", ["Smoke"]="Instance", ["Sound"]="Instance", ["SoundEffect"]="Instance",
		["ChorusSoundEffect"]="SoundEffect", ["CompressorSoundEffect"]="SoundEffect",
		["DistortionSoundEffect"]="SoundEffect", ["EchoSoundEffect"]="SoundEffect",
		["EqualizerSoundEffect"]="SoundEffect", ["FlangeSoundEffect"]="SoundEffect",
		["PitchShiftSoundEffect"]="SoundEffect", ["ReverbSoundEffect"]="SoundEffect",
		["TremoloSoundEffect"]="SoundEffect", ["SoundGroup"]="Instance", ["SoundService"]="Instance",
		["Sparkles"]="Instance", ["SpawnerService"]="Instance", ["StarterGear"]="Instance",
		["StarterPlayer"]="Instance", ["StarterPlayerScripts"]="Instance",
		["StarterCharacterScripts"]="StarterPlayerScripts", ["Stats"]="Instance", ["StatsItem"]="Instance",
		["StringValue"]="Instance", ["TaskScheduler"]="Instance", ["Team"]="Instance", ["Teams"]="Instance",
		["TeleportService"]="Instance", ["TerrainRegion"]="Instance", ["TestService"]="Instance",
		["TextChatService"]="Instance", ["TextService"]="Instance", ["ThirdPartyUserService"]="Instance",
		["TimerService"]="Instance", ["Toolbar"]="Instance", ["TouchInputService"]="Instance",
		["TouchTransmitter"]="Instance", ["Trail"]="Instance", ["TweenBase"]="Instance", ["Tween"]="TweenBase",
		["TweenService"]="Instance", ["UIBase"]="Instance", ["UIComponent"]="UIBase",
		["UIConstraint"]="UIComponent", ["UIAspectRatioConstraint"]="UIConstraint",
		["UISizeConstraint"]="UIConstraint", ["UITextSizeConstraint"]="UIConstraint",
		["UICorner"]="UIComponent", ["UIStroke"]="UIComponent", ["UIGradient"]="UIComponent",
		["UILayout"]="UIComponent", ["UIGridStyleLayout"]="UILayout", ["UIGridLayout"]="UIGridStyleLayout",
		["UIListLayout"]="UIGridStyleLayout", ["UIPageLayout"]="UIGridStyleLayout",
		["UITableLayout"]="UIGridStyleLayout", ["UIPadding"]="UIComponent", ["UIScale"]="UIComponent",
		["UserGameSettings"]="Instance", ["UserInputService"]="Instance", ["VRService"]="Instance",
		["Vector3Value"]="Instance", ["VirtualUser"]="Instance", ["Visit"]="Instance",
		["WeldConstraint"]="Instance", ["DragDetector"]="Instance", ["UIDragDetector"]="UIComponent",
	}

	S.EXPLORER_ORDER = {
		["Workspace"]=0, ["Player"]=1, ["Folder"]=1, ["Sound"]=1, ["Team"]=1,
		["Players"]=2, ["Accoutrement"]=2, ["MeshPart"]=2, ["UnionOperation"]=2, ["NegateOperation"]=2,
		["Clothing"]=2, ["Shirt"]=2, ["Pants"]=2, ["ShirtGraphic"]=2, ["BodyColors"]=2, ["Motor"]=2,
		["Lighting"]=3, ["MaterialService"]=3, ["ReplicatedFirst"]=3, ["ReplicatedStorage"]=3,
		["StarterGui"]=3, ["StarterPack"]=3, ["StarterPlayer"]=3, ["CoreGui"]=3,
		["ServerScriptService"]=3, ["ServerStorage"]=3, ["Accessory"]=3, ["Hat"]=3,
		["Attachment"]=3, ["Constraint"]=3, ["WeldConstraint"]=3, ["Humanoid"]=3, ["Script"]=3,
		["Tool"]=3, ["Backpack"]=3, ["StarterGear"]=3, ["Seat"]=3, ["VehicleSeat"]=3, ["SpawnLocation"]=3,
		["Fire"]=3, ["Smoke"]=3, ["Sparkles"]=3, ["ParticleEmitter"]=3, ["Beam"]=3, ["Trail"]=3,
		["Light"]=3, ["PointLight"]=3, ["SpotLight"]=3, ["SurfaceLight"]=3, ["ClickDetector"]=3,
		["ProximityPrompt"]=3, ["Highlight"]=3, ["ForceField"]=3, ["Explosion"]=3,
		["BoolValue"]=3, ["IntValue"]=3, ["NumberValue"]=3, ["StringValue"]=3, ["ObjectValue"]=3,
		["Vector3Value"]=3, ["CFrameValue"]=3, ["Color3Value"]=3, ["BrickColorValue"]=3, ["RayValue"]=3,
		["UICorner"]=3, ["UIStroke"]=3, ["UIGradient"]=3, ["UIPadding"]=3, ["UIScale"]=3,
		["UIListLayout"]=3, ["UIGridLayout"]=3, ["UIPageLayout"]=3, ["UITableLayout"]=3,
		["UIAspectRatioConstraint"]=3, ["UISizeConstraint"]=3, ["UITextSizeConstraint"]=3,
		["LocalScript"]=4, ["RemoteFunction"]=4, ["BindableFunction"]=4, ["Decal"]=4, ["Texture"]=4,
		["ModuleScript"]=5, ["RemoteEvent"]=5, ["BindableEvent"]=5,
		["Model"]=10, ["WorldModel"]=10, ["Status"]=10, ["Part"]=11, ["Message"]=11, ["Hint"]=11,
		["WedgePart"]=12, ["CornerWedgePart"]=12, ["TrussPart"]=12,
		["PlayerGui"]=13, ["PlayerScripts"]=13, ["StarterPlayerScripts"]=13, ["StarterCharacterScripts"]=13,
		["Teams"]=14, ["ScreenGui"]=14, ["BillboardGui"]=14, ["SurfaceGui"]=14, ["GuiMain"]=14,
		["BodyPosition"]=14, ["BodyVelocity"]=14, ["BodyGyro"]=14, ["BodyForce"]=14,
		["Frame"]=15, ["ScrollingFrame"]=15, ["CanvasGroup"]=15, ["ViewportFrame"]=15,
		["ImageButton"]=16, ["TextButton"]=17, ["TextBox"]=17, ["ImageLabel"]=18, ["TextLabel"]=19,
		["Weld"]=20, ["JointInstance"]=20, ["SelectionBox"]=21, ["SelectionSphere"]=21,
		["Animation"]=22, ["AnimationController"]=22, ["Configuration"]=22, ["Dialog"]=22,
		["SoundService"]=50, ["Chat"]=51, ["TextChatService"]=52, ["TestService"]=100,
	}

	-- Standard Studio services shown at root when "Show Hidden Services" is OFF
	S.STANDARD_SERVICES = {
		Workspace=true, Players=true, Lighting=true, MaterialService=true,
		ReplicatedFirst=true, ReplicatedStorage=true, StarterGui=true,
		StarterPack=true, StarterPlayer=true, Teams=true, SoundService=true,
		Chat=true, TextChatService=true, CoreGui=true, CorePackages=true,
		TestService=true, ProximityPromptService=true, LocalizationService=true,
	}

	S.isaCache = {}
	function F.isClassA(className, targetClass)
		if not className or not targetClass then return false end
		if className == targetClass or targetClass == "Instance" then return true end
		local key = className .. ">" .. targetClass
		local cached = S.isaCache[key]
		if cached ~= nil then return cached end
		local cur = className
		local hit = false
		for _ = 1, 16 do
			local sup = S.CLASS_SUPER[cur]
			if not sup then break end
			if sup == targetClass then hit = true; break end
			cur = sup
		end
		S.isaCache[key] = hit
		return hit
	end

	function F.getExplorerOrder(className, parentIsGame)
		if parentIsGame and className ~= "Workspace" then
			local ord = S.EXPLORER_ORDER[className]
			if not ord or ord <= 0 then return 999 end
			return ord
		end
		local cur = className
		for _ = 1, 16 do
			local ord = S.EXPLORER_ORDER[cur]
			if ord ~= nil then return ord end
			cur = S.CLASS_SUPER[cur]
			if not cur then break end
		end
		return 999
	end

	local ICON_STYLES = {
		Workspace        = { bg = Color3.fromRGB(48, 130, 210), fg = Color3.new(1,1,1), g = "W" },
		Terrain          = { bg = Color3.fromRGB(70, 165, 85),  fg = Color3.new(1,1,1), g = "^" },
		Players          = { bg = Color3.fromRGB(58, 150, 225), fg = Color3.new(1,1,1), g = "P" },
		Player           = { bg = Color3.fromRGB(80, 175, 240), fg = Color3.new(1,1,1), g = "P" },
		Folder           = { bg = Color3.fromRGB(220, 178, 65), fg = Color3.fromRGB(40,30,10), g = "F" },
		Model            = { bg = Color3.fromRGB(165, 110, 215),fg = Color3.new(1,1,1), g = "M" },
		Part             = { bg = Color3.fromRGB(85, 155, 230), fg = Color3.new(1,1,1), g = "B" },
		MeshPart         = { bg = Color3.fromRGB(65, 185, 200), fg = Color3.new(1,1,1), g = "#" },
		UnionOperation   = { bg = Color3.fromRGB(100, 165, 225),fg = Color3.new(1,1,1), g = "U" },
		Seat             = { bg = Color3.fromRGB(210, 145, 75), fg = Color3.new(1,1,1), g = "S" },
		SpawnLocation    = { bg = Color3.fromRGB(190, 120, 75), fg = Color3.new(1,1,1), g = "*" },
		Script           = { bg = Color3.fromRGB(75, 180, 105), fg = Color3.new(1,1,1), g = "S" },
		LocalScript      = { bg = Color3.fromRGB(65, 145, 235), fg = Color3.new(1,1,1), g = "L" },
		ModuleScript     = { bg = Color3.fromRGB(150, 95, 220), fg = Color3.new(1,1,1), g = "M" },
		RemoteEvent      = { bg = Color3.fromRGB(235, 155, 50), fg = Color3.fromRGB(30,20,0), g = "E" },
		RemoteFunction   = { bg = Color3.fromRGB(215, 95, 175), fg = Color3.new(1,1,1), g = "f" },
		BindableEvent    = { bg = Color3.fromRGB(70, 180, 175), fg = Color3.new(1,1,1), g = "e" },
		BindableFunction = { bg = Color3.fromRGB(85, 155, 185), fg = Color3.new(1,1,1), g = "f" },
		Humanoid         = { bg = Color3.fromRGB(85, 195, 115), fg = Color3.fromRGB(15,35,20), g = "H" },
		Camera           = { bg = Color3.fromRGB(95, 115, 135), fg = Color3.new(1,1,1), g = "C" },
		Lighting         = { bg = Color3.fromRGB(235, 200, 70), fg = Color3.fromRGB(35,30,10), g = "*" },
		Light            = { bg = Color3.fromRGB(240, 215, 90), fg = Color3.fromRGB(35,30,10), g = "*" },
		Sound            = { bg = Color3.fromRGB(75, 190, 130), fg = Color3.new(1,1,1), g = "~" },
		LayerCollector   = { bg = Color3.fromRGB(60, 165, 210), fg = Color3.new(1,1,1), g = "G" },
		BasePlayerGui    = { bg = Color3.fromRGB(75, 150, 205), fg = Color3.new(1,1,1), g = "G" },
		Frame            = { bg = Color3.fromRGB(90, 135, 185), fg = Color3.new(1,1,1), g = "[]" },
		TextLabel        = { bg = Color3.fromRGB(105, 165, 225),fg = Color3.new(1,1,1), g = "T" },
		TextButton       = { bg = Color3.fromRGB(90, 175, 205), fg = Color3.new(1,1,1), g = "T" },
		TextBox          = { bg = Color3.fromRGB(115, 150, 215),fg = Color3.new(1,1,1), g = "I" },
		ImageLabel       = { bg = Color3.fromRGB(115, 180, 145),fg = Color3.new(1,1,1), g = "i" },
		Value            = { bg = Color3.fromRGB(100, 185, 140),fg = Color3.fromRGB(15,30,20), g = "V" },
		Tool             = { bg = Color3.fromRGB(210, 135, 70), fg = Color3.new(1,1,1), g = "T" },
		Accessory        = { bg = Color3.fromRGB(190, 130, 180),fg = Color3.new(1,1,1), g = "A" },
		Constraint       = { bg = Color3.fromRGB(205, 175, 95), fg = Color3.fromRGB(30,25,10), g = "@" },
		JointInstance    = { bg = Color3.fromRGB(150, 155, 165),fg = Color3.new(1,1,1), g = "=" },
		ParticleEmitter  = { bg = Color3.fromRGB(220, 115, 115),fg = Color3.new(1,1,1), g = "+" },
		UIComponent      = { bg = Color3.fromRGB(130, 145, 210),fg = Color3.new(1,1,1), g = "u" },
		Service          = { bg = Color3.fromRGB(110, 120, 135),fg = Color3.new(1,1,1), g = "*" },
	}

	local iconCache = {}
	function F.getIconStyle(cls)
		if iconCache[cls] then return iconCache[cls] end
		local st = ICON_STYLES[cls]
		if not st then
			if cls:find("Value$") then st = ICON_STYLES.Value
			elseif F.isClassA(cls, "LocalScript") then st = ICON_STYLES.LocalScript
			elseif F.isClassA(cls, "ModuleScript") then st = ICON_STYLES.ModuleScript
			elseif F.isClassA(cls, "BaseScript") then st = ICON_STYLES.Script
			elseif F.isClassA(cls, "Terrain") then st = ICON_STYLES.Terrain
			elseif F.isClassA(cls, "MeshPart") then st = ICON_STYLES.MeshPart
			elseif F.isClassA(cls, "PartOperation") then st = ICON_STYLES.UnionOperation
			elseif F.isClassA(cls, "BasePart") then st = ICON_STYLES.Part
			elseif F.isClassA(cls, "Model") then st = ICON_STYLES.Model
			elseif F.isClassA(cls, "LayerCollector") then st = ICON_STYLES.LayerCollector
			elseif F.isClassA(cls, "BasePlayerGui") then st = ICON_STYLES.BasePlayerGui
			elseif F.isClassA(cls, "TextButton") then st = ICON_STYLES.TextButton
			elseif F.isClassA(cls, "TextLabel") then st = ICON_STYLES.TextLabel
			elseif F.isClassA(cls, "TextBox") then st = ICON_STYLES.TextBox
			elseif F.isClassA(cls, "ImageLabel") or F.isClassA(cls, "ImageButton") then st = ICON_STYLES.ImageLabel
			elseif F.isClassA(cls, "GuiObject") then st = ICON_STYLES.Frame
			elseif F.isClassA(cls, "UIComponent") then st = ICON_STYLES.UIComponent
			elseif F.isClassA(cls, "Light") then st = ICON_STYLES.Light
			elseif F.isClassA(cls, "Sound") or F.isClassA(cls, "SoundEffect") then st = ICON_STYLES.Sound
			elseif F.isClassA(cls, "Tool") or F.isClassA(cls, "Backpack") or F.isClassA(cls, "StarterPack") then st = ICON_STYLES.Tool
			elseif F.isClassA(cls, "Accoutrement") then st = ICON_STYLES.Accessory
			elseif F.isClassA(cls, "Constraint") or cls == "Attachment" then st = ICON_STYLES.Constraint
			elseif F.isClassA(cls, "JointInstance") then st = ICON_STYLES.JointInstance
			elseif cls == "Fire" or cls == "Smoke" or cls == "Sparkles" or cls == "Beam" or cls == "Trail" then st = ICON_STYLES.ParticleEmitter
			else st = ICON_STYLES.Service end
		end
		iconCache[cls] = st
		return st
	end

	-- Dex Category Sort Order
	S.CATEGORY_ORDER = {
		Appearance=1, Data=2, Behavior=3, Part=4, Camera=5, Control=6,
		Game=7, Text=8, Gui=9, Mesh=10, Attributes=11, Matcha=12, Other=99
	}

	-- Exact Matcha-supported readable/writable property schema (avoids FindFirstChild fallback!)
	S.CLASS_PROPS = {
		Instance = {
			{ name="Name",       vtype="string",   cat="Data",   writable=true },
			{ name="ClassName",  vtype="string",   cat="Data",   writable=false },
			{ name="Parent",     vtype="Instance", cat="Data",   writable=true },
			{ name="Address",    vtype="hex",      cat="Matcha", writable=false },
			{ name="FullName",   vtype="fullname", cat="Matcha", writable=false },
			{ name="Children",   vtype="childcnt", cat="Matcha", writable=false },
		},
		BasePart = {
			{ name="Color",                  vtype="Color3",  cat="Appearance", writable=false },
			{ name="Transparency",           vtype="number",  cat="Appearance", writable=false },
			{ name="CFrame",                 vtype="CFrame",  cat="Data",       writable=true },
			{ name="Position",               vtype="Vector3", cat="Data",       writable=true },
			{ name="Velocity",               vtype="Vector3", cat="Data",       writable=true },
			{ name="AssemblyLinearVelocity", vtype="Vector3", cat="Data",       writable=true },
			{ name="CanCollide",             vtype="bool",    cat="Behavior",   writable=true },
			{ name="Size",                   vtype="Vector3", cat="Part",       writable=true },
		},
		MeshPart = {
			{ name="MeshId",    vtype="string", cat="Mesh", writable=false },
			{ name="TextureID", vtype="string", cat="Mesh", writable=false },
		},
		Humanoid = {
			{ name="Health",      vtype="number",   cat="Game",    writable=false },
			{ name="MaxHealth",   vtype="number",   cat="Game",    writable=false },
			{ name="WalkToPoint", vtype="Vector3",  cat="Control", writable=true },
			{ name="WalkToPart",  vtype="Instance", cat="Control", writable=true },
		},
		Player = {
			{ name="Character", vtype="Instance", cat="Data", writable=false },
			{ name="Team",      vtype="Instance", cat="Data", writable=false },
			{ name="UserId",    vtype="number",   cat="Data", writable=false },
		},
		Players = {
			{ name="LocalPlayer", vtype="Instance", cat="Data", writable=false },
		},
		Camera = {
			{ name="CFrame",        vtype="CFrame",   cat="Data",   writable=true },
			{ name="Position",      vtype="Vector3",  cat="Data",   writable=false },
			{ name="FieldOfView",   vtype="number",   cat="Data",   writable=true },
			{ name="ViewportSize",  vtype="Vector2",  cat="Data",   writable=false },
			{ name="CameraSubject", vtype="Instance", cat="Camera", writable=false },
		},
		Model = {
			{ name="PrimaryPart", vtype="Instance", cat="Data", writable=false },
		},
		DataModel = {
			{ name="PlaceId", vtype="number", cat="Data", writable=false },
			{ name="GameId",  vtype="number", cat="Data", writable=false },
			{ name="JobId",   vtype="string", cat="Data", writable=false },
		},
		GuiObject = {
			{ name="AbsolutePosition", vtype="Vector2", cat="Gui", writable=true },
			{ name="AbsoluteSize",     vtype="Vector2", cat="Gui", writable=true },
		},
		TextLabel = {
			{ name="Text", vtype="string", cat="Text", writable=false },
		},
		ValueObject = {
			{ name="Value", vtype="auto", cat="Data", writable=true },
		},
	}

	S.VALUE_TYPES = {
		BoolValue = "bool", IntValue = "number", NumberValue = "number",
		IntConstrainedValue = "number", DoubleConstrainedValue = "number",
		StringValue = "string", Vector3Value = "Vector3", CFrameValue = "CFrame",
		Color3Value = "Color3", ObjectValue = "Instance", BrickColorValue = "string",
	}
end)();

--=====================================================================
-- 4. EXPLORER TREE ENGINE, SEARCH & SELECTION (KEYED BY ADDRESS)
--=====================================================================
(function()
	S.nodes = {}          -- [addr] = node
	S.rootNode = nil
	S.treeList = {}       -- flattened visible explorer rows
	S.expanded = {}       -- [addr] = true
	S.searchText = ""
	S.searchResults = nil -- [addr] = true
	S.searchExpanded = {} -- [addr] = 1 (match) | 2 (ancestor)
	S.searchCache = {}
	S.nodeMaxWidth = 260
	S.selectionList = {}  -- array of nodes
	S.selectionMap = {}   -- [addr] = true
	S.lastSelectedAddr = nil
	S.clipboardCut = {}   -- array of { obj, addr, name }

	function F.clearSelection()
		S.selectionList = {}
		S.selectionMap = {}
		if F.rebuildSelectionEsp then F.rebuildSelectionEsp() end
	end

	function F.setSelectionNodes(list)
		S.selectionList = {}
		S.selectionMap = {}
		for _, node in ipairs(list) do
			if node and node.addr and not S.selectionMap[node.addr] then
				S.selectionMap[node.addr] = true
				S.selectionList[#S.selectionList + 1] = node
				S.lastSelectedAddr = node.addr
			end
		end
		if F.rebuildSelectionEsp then F.rebuildSelectionEsp() end
	end

	function F.toggleSelectionNode(node)
		if not node or not node.addr then return end
		if S.selectionMap[node.addr] then
			S.selectionMap[node.addr] = nil
			for i = #S.selectionList, 1, -1 do
				if S.selectionList[i].addr == node.addr then
					table.remove(S.selectionList, i)
				end
			end
		else
			S.selectionMap[node.addr] = true
			S.selectionList[#S.selectionList + 1] = node
			S.lastSelectedAddr = node.addr
		end
		if F.rebuildSelectionEsp then F.rebuildSelectionEsp() end
	end

	local function makeNode(obj, parentNode, depth)
		local addr = F.addrOf(obj)
		if not addr then return nil end
		local existing = S.nodes[addr]
		if existing then
			existing.obj = obj
			existing.parent = parentNode
			existing.depth = depth
			existing.name = F.safeName(obj)
			existing.className = F.safeClass(obj)
			return existing
		end
		local cls = F.safeClass(obj)
		local name = F.safeName(obj)
		local parentIsGame = (parentNode and parentNode.addr == S.rootNode.addr)
		local node = {
			obj = obj,
			addr = addr,
			parent = parentNode,
			depth = depth,
			name = name,
			className = cls,
			order = F.getExplorerOrder(cls, parentIsGame),
			children = nil, -- nil = not yet loaded; array once loaded
			hasChildren = true,
			sorted = false,
		}
		S.nodes[addr] = node
		return node
	end

	function F.loadNodeChildren(node, force)
		if not node or not node.obj then return end
		if node.children ~= nil and not force then return end
		local rawKids = F.safeChildren(node.obj)
		local isGame = (node.addr == S.rootNode.addr)
		local kids = {}
		for _, ch in ipairs(rawKids) do
			local cname = F.safeName(ch)
			local ccls = F.safeClass(ch)
			local include = true
			if isGame and not S.showHiddenServices then
				include = (S.STANDARD_SERVICES[cname] == true) or (S.STANDARD_SERVICES[ccls] == true)
			end
			if include then
				local kn = makeNode(ch, node, node.depth + 1)
				if kn then
					local sub = F.safeChildren(ch)
					kn.hasChildren = (#sub > 0)
					kids[#kids + 1] = kn
				end
			end
		end
		node.children = kids
		node.hasChildren = (#kids > 0)
		node.sorted = false
	end

	local function sortChildren(node)
		if not node.children or node.sorted then return end
		table.sort(node.children, function(a, b)
			if a.order ~= b.order then return a.order < b.order end
			if a.name ~= b.name then return a.name < b.name end
			if a.className ~= b.className then return a.className < b.className end
			return a.addr < b.addr
		end)
		node.sorted = true
	end

	function F.rebuildTreeList()
		if not S.rootNode then return end
		local isSearching = (S.searchResults ~= nil)
		local list = {}
		local maxW = 240

		local function walk(node)
			if not node.children then return end
			sortChildren(node)
			for _, child in ipairs(node.children) do
				if not isSearching or S.searchResults[child.addr] then
					list[#list + 1] = child
					local tw = child.depth * 16 + 38 + #child.name * 7
					if tw > maxW then maxW = tw end
					local exp = (not isSearching and S.expanded[child.addr]) or (isSearching and S.searchExpanded[child.addr] == 2)
					if exp then
						if child.children == nil then F.loadNodeChildren(child, false) end
						walk(child)
					end
				end
			end
		end

		walk(S.rootNode)
		S.treeList = list
		S.nodeMaxWidth = maxW
		S.lastRefresh = F.now()
	end

	function F.initTree()
		S.nodes = {}
		local rootAddr = F.addrOf(game)
		S.rootNode = {
			obj = game,
			addr = rootAddr,
			parent = nil,
			depth = -1,
			name = "game",
			className = "DataModel",
			order = 0,
			children = nil,
			hasChildren = true,
			sorted = false,
		}
		S.nodes[rootAddr] = S.rootNode
		S.expanded = {}
		S.expanded[rootAddr] = true
		F.loadNodeChildren(S.rootNode, true)
		F.rebuildTreeList()
	end

	function F.refreshExpandedTree()
		if not S.rootNode then return end
		F.loadNodeChildren(S.rootNode, true)
		for addr, isExp in pairs(S.expanded) do
			if isExp and addr ~= S.rootNode.addr then
				local node = S.nodes[addr]
				if node then
					local okName = pcall(function() return node.obj.Name end)
					if okName then
						node.name = F.safeName(node.obj)
						node.className = F.safeClass(node.obj)
						F.loadNodeChildren(node, true)
					else
						S.expanded[addr] = nil
					end
				else
					S.expanded[addr] = nil
				end
			end
		end
		F.rebuildTreeList()
	end

	function F.toggleExpandNode(node)
		if not node or not node.addr then return end
		if S.searchResults then
			if S.searchExpanded[node.addr] == 2 then
				S.searchExpanded[node.addr] = 1
			else
				if node.children == nil then F.loadNodeChildren(node, false) end
				S.searchExpanded[node.addr] = 2
			end
		else
			if S.expanded[node.addr] then
				S.expanded[node.addr] = nil
			else
				F.loadNodeChildren(node, true)
				if node.hasChildren then
					S.expanded[node.addr] = true
				end
			end
		end
		F.rebuildTreeList()
	end

	function F.revealInstance(inst)
		if not inst or not S.rootNode then return nil end
		local chain = {}
		local cur = inst
		for _ = 1, 64 do
			local a = F.addrOf(cur)
			if not a then break end
			table.insert(chain, 1, cur)
			if a == S.rootNode.addr then break end
			cur = F.safeParent(cur)
			if not cur then break end
		end
		if #chain == 0 then return nil end
		local parentNode = S.rootNode
		for idx = 1, #chain do
			local obj = chain[idx]
			local a = F.addrOf(obj)
			if a ~= S.rootNode.addr then
				if parentNode.children == nil then F.loadNodeChildren(parentNode, true) end
				local found = S.nodes[a]
				if not found then
					found = makeNode(obj, parentNode, parentNode.depth + 1)
					if parentNode.children then
						parentNode.children[#parentNode.children + 1] = found
						parentNode.hasChildren = true
						parentNode.sorted = false
					end
				end
				if idx < #chain then
					S.expanded[a] = true
				end
				parentNode = found
			end
		end
		S.searchText = ""
		S.searchResults = nil
		if UI.expSearch then UI.expSearch.text = "" end
		F.rebuildTreeList()
		-- Scroll Explorer so revealed node is visible
		for i, n in ipairs(S.treeList) do
			if n.addr == parentNode.addr then
				UI.expScrollTargetIdx = math.max(0, i - 4)
				break
			end
		end
		return parentNode
	end

	local function buildSearchPredicate(token)
		local kw, val = token:match("^(%S+):%s*(.*)$")
		if kw == "class" and val ~= "" then
			local q = val:lower()
			local exact = nil
			for cls in pairs(S.CLASS_SUPER) do
				if cls:lower() == q then exact = cls; break end
			end
			if exact then
				return function(_, cls) return cls == exact end
			end
			return function(_, cls) return cls:lower():find(q, 1, true) ~= nil end
		elseif kw == "isa" and val ~= "" then
			local q = val:lower()
			local target = val
			for cls in pairs(S.CLASS_SUPER) do
				if cls:lower() == q then target = cls; break end
			end
			return function(_, cls) return F.isClassA(cls, target) end
		elseif kw == "regex" and val ~= "" then
			return function(name)
				local ok, hit = pcall(string.find, name, val)
				return ok and hit ~= nil
			end
		end
		local q = token:lower()
		return function(name) return name:lower():find(q, 1, true) ~= nil end
	end

	local searchNonce = 0
	local function ensureNodeChain(inst, svcNode)
		local chain = {}
		local cur = inst
		for _ = 1, 48 do
			local a = F.addrOf(cur)
			if not a then break end
			if a == svcNode.addr then break end
			chain[#chain + 1] = { obj = cur, addr = a }
			cur = F.safeParent(cur)
			if not cur then break end
		end
		local parentNode = svcNode
		for i = #chain, 1, -1 do
			local entry = chain[i]
			if parentNode.children == nil then F.loadNodeChildren(parentNode, false) end
			local node = S.nodes[entry.addr]
			if not node then
				node = makeNode(entry.obj, parentNode, parentNode.depth + 1)
				if node and parentNode.children then
					parentNode.children[#parentNode.children + 1] = node
					parentNode.hasChildren = true
					parentNode.sorted = false
				end
			end
			if not node then break end
			parentNode = node
		end
		return parentNode
	end

	function F.runExplorerSearch(query)
		searchNonce = searchNonce + 1
		S.searchText = F.trim(query or "")
		if S.searchText == "" then
			S.searchResults = nil
			S.searchExpanded = {}
			F.rebuildTreeList()
			return
		end

		local checks = {}
		for _, rawTok in ipairs(F.splitString(S.searchText, "|")) do
			local tok = F.trim(rawTok)
			if tok ~= "" then
				checks[#checks + 1] = buildSearchPredicate(tok)
			end
		end
		if #checks == 0 then
			S.searchResults = nil
			S.searchExpanded = {}
			F.rebuildTreeList()
			return
		end

		local results = {}
		local searchExp = {}
		local maxHits = 250
		local hitCount = 0

		if not S.rootNode.children then F.loadNodeChildren(S.rootNode, true) end
		for _, svcNode in ipairs(S.rootNode.children) do
			if hitCount >= maxHits then break end
			if S.showHiddenServices or svcNode.name ~= "CorePackages" then
				local svcMatched = false
				for _, pred in ipairs(checks) do
					if pred(svcNode.name, svcNode.className) then svcMatched = true; break end
				end
				if svcMatched then
					hitCount = hitCount + 1
					results[svcNode.addr] = true
					searchExp[svcNode.addr] = math.max(searchExp[svcNode.addr] or 0, 1)
				end
				local okD, desc = pcall(function() return svcNode.obj:GetDescendants() end)
				if okD and type(desc) == "table" then
					for _, inst in ipairs(desc) do
						if hitCount >= maxHits then break end
						local dName = F.safeName(inst)
						local dCls = F.safeClass(inst)
						local matched = false
						for _, pred in ipairs(checks) do
							if pred(dName, dCls) then matched = true; break end
						end
						if matched then
							local hitNode = ensureNodeChain(inst, svcNode)
							if hitNode and hitNode.addr then
								hitCount = hitCount + 1
								results[hitNode.addr] = true
								searchExp[hitNode.addr] = math.max(searchExp[hitNode.addr] or 0, 1)
								local p = hitNode.parent
								while p and p.addr ~= S.rootNode.addr do
									results[p.addr] = true
									searchExp[p.addr] = 2
									p = p.parent
								end
							end
						end
					end
				end
			end
		end

		S.searchResults = results
		S.searchExpanded = searchExp
		UI.expScroll = 0
		F.rebuildTreeList()
	end

	function F.scheduleExplorerSearch(query)
		searchNonce = searchNonce + 1
		local myNonce = searchNonce
		task.spawn(function()
			task.wait(0.16)
			if S.alive and searchNonce == myNonce then
				F.runExplorerSearch(query)
			end
		end)
	end
end)();

--=====================================================================
-- 5. PROPERTIES SCHEMA BUILDER, FORMATTER & LIVE UPDATER
--=====================================================================
(function()
	S.propTree = {}       -- flattened visible property rows
	S.propExpanded = {}   -- ["CAT:Data"] = true | ["PropName"] = true
	S.propSearch = ""
	S.propNameWidth = 110
	S.propSelectedObj = nil
	S.propSelectedAddr = nil

	-- Expand default categories matching dex.txt lines 3414-3419
	for cat in pairs(S.CATEGORY_ORDER) do
		S.propExpanded["CAT:" .. cat] = true
	end

	function F.formatPropValue(val, vtype)
		if val == nil then return "nil" end
		local t = typeof and typeof(val) or type(val)
		if vtype == "hex" and type(val) == "number" then
			return string.format("0x%X", val)
		elseif vtype == "Instance" then
			return F.safeName(val)
		elseif t == "Vector3" then
			return string.format("%.2f, %.2f, %.2f", val.X, val.Y, val.Z)
		elseif t == "Vector2" then
			return string.format("%.1f, %.1f", val.X, val.Y)
		elseif t == "CFrame" then
			local p = val.Position
			return string.format("%.2f, %.2f, %.2f", p.X, p.Y, p.Z)
		elseif t == "Color3" then
			return string.format("%d, %d, %d", math.floor(val.R * 255 + 0.5), math.floor(val.G * 255 + 0.5), math.floor(val.B * 255 + 0.5))
		elseif type(val) == "table" and val.x ~= nil and val.y ~= nil and val.z ~= nil then
			return string.format("%s, %s, %s", tostring(val.x), tostring(val.y), tostring(val.z))
		elseif type(val) == "number" then
			if math.floor(val) == val then return tostring(val) end
			return tostring(F.round(val, 3))
		elseif type(val) == "boolean" then
			return val and "true" or "false"
		end
		return tostring(val)
	end

	function F.readPropValue(obj, spec)
		if not obj then return nil end
		if spec.isAttr then
			local ok, v = pcall(function() return obj:GetAttribute(spec.attrName) end)
			return ok and v or nil
		elseif spec.vtype == "fullname" then
			return F.safeFullName(obj)
		elseif spec.vtype == "childcnt" then
			return #F.safeChildren(obj)
		else
			local ok, v = pcall(function() return obj[spec.name] end)
			return ok and v or nil
		end
	end

	local function parseNums(str)
		local out = {}
		for tok in tostring(str):gmatch("[^,%s]+") do
			local n = tonumber(tok)
			if n then out[#out + 1] = n end
		end
		return out
	end

	function F.writePropValue(spec, rawStr)
		if #S.selectionList == 0 then return false end
		local str = F.trim(rawStr)
		local applied = false

		for _, node in ipairs(S.selectionList) do
			local obj = node.obj
			if obj then
				local ok = pcall(function()
					if spec.isAttr then
						local cur = obj:GetAttribute(spec.attrName)
						local ct = typeof and typeof(cur) or type(cur)
						if type(cur) == "boolean" then
							obj:SetAttribute(spec.attrName, str:lower() == "true" or str == "1")
						elseif type(cur) == "number" then
							local n = tonumber(str); if n then obj:SetAttribute(spec.attrName, n) end
						elseif ct == "Vector3" then
							local ns = parseNums(str)
							if #ns >= 3 then obj:SetAttribute(spec.attrName, Vector3.new(ns[1], ns[2], ns[3])) end
						else
							obj:SetAttribute(spec.attrName, str)
						end
						applied = true
						return
					end

					if spec.parentProp then
						local cur = obj[spec.parentProp]
						local num = tonumber(str)
						if not num then return end
						if spec.parentType == "Vector3" and cur then
							obj[spec.parentProp] = Vector3.new(
								spec.axis == "X" and num or cur.X,
								spec.axis == "Y" and num or cur.Y,
								spec.axis == "Z" and num or cur.Z
							)
						elseif spec.parentType == "Vector2" and cur then
							obj[spec.parentProp] = Vector2.new(
								spec.axis == "X" and num or cur.X,
								spec.axis == "Y" and num or cur.Y
							)
						elseif spec.parentType == "CFrame" and cur then
							local p = cur.Position
							local newP = Vector3.new(
								spec.axis == "X" and num or p.X,
								spec.axis == "Y" and num or p.Y,
								spec.axis == "Z" and num or p.Z
							)
							obj[spec.parentProp] = CFrame.new(newP) * (cur - p)
						end
						applied = true
						return
					end

					local vt = spec.vtype
					if vt == "auto" then
						vt = S.VALUE_TYPES[F.safeClass(obj)] or "string"
					end
					if vt == "string" then
						obj[spec.name] = rawStr
						if spec.name == "Name" then node.name = rawStr end
						applied = true
					elseif vt == "number" then
						local n = tonumber(str)
						if n then obj[spec.name] = n; applied = true end
					elseif vt == "bool" then
						obj[spec.name] = (str:lower() == "true" or str == "1")
						applied = true
					elseif vt == "Vector3" then
						local ns = parseNums(str)
						if #ns >= 3 then obj[spec.name] = Vector3.new(ns[1], ns[2], ns[3]); applied = true end
					elseif vt == "Vector2" then
						local ns = parseNums(str)
						if #ns >= 2 then obj[spec.name] = Vector2.new(ns[1], ns[2]); applied = true end
					elseif vt == "CFrame" then
						local ns = parseNums(str)
						if #ns >= 3 then
							local cur = obj[spec.name]
							if cur then
								obj[spec.name] = CFrame.new(ns[1], ns[2], ns[3]) * (cur - cur.Position)
							else
								obj[spec.name] = CFrame.new(ns[1], ns[2], ns[3])
							end
							applied = true
						end
					elseif vt == "Parent" or spec.name == "Parent" then
						if str:lower() == "nil" then
							obj.Parent = nil
							applied = true
						else
							local target = game:FindFirstChild(str)
							if target then obj.Parent = target; applied = true end
						end
					end
				end)
				if not ok then
					F.notify("Property Error", "Cannot set " .. tostring(spec.name))
				end
			end
		end
		if applied then
			F.rebuildPropTree()
			if spec.name == "Name" or spec.name == "Parent" then
				F.refreshExpandedTree()
			end
		end
		return applied
	end

	function F.rebuildPropTree()
		local sel = S.selectionList[1]
		if not sel or not sel.obj then
			S.propTree = {}
			S.propSelectedObj = nil
			S.propSelectedAddr = nil
			return
		end

		local obj = sel.obj
		local cls = F.safeClass(obj)
		S.propSelectedObj = obj
		S.propSelectedAddr = sel.addr

		local specs = {}
		local function appendSchema(schemaKey)
			local list = S.CLASS_PROPS[schemaKey]
			if list then
				for _, sp in ipairs(list) do specs[#specs + 1] = sp end
			end
		end

		appendSchema("Instance")
		if F.isClassA(cls, "BasePart") then appendSchema("BasePart") end
		if cls == "MeshPart" then appendSchema("MeshPart") end
		if cls == "Humanoid" then appendSchema("Humanoid") end
		if cls == "Player" then appendSchema("Player") end
		if cls == "Players" then appendSchema("Players") end
		if cls == "Camera" then appendSchema("Camera") end
		if F.isClassA(cls, "Model") and cls ~= "Workspace" then appendSchema("Model") end
		if cls == "DataModel" then appendSchema("DataModel") end
		if F.isClassA(cls, "GuiObject") then appendSchema("GuiObject") end
		if cls == "TextLabel" then appendSchema("TextLabel") end
		if S.VALUE_TYPES[cls] then appendSchema("ValueObject") end

		-- Dynamic Attributes
		local okAttr, attrList = pcall(function() return obj:GetAttributes() end)
		if okAttr and type(attrList) == "table" then
			local seen = {}
			for _, aName in ipairs(attrList) do
				if type(aName) == "string" and not seen[aName] then
					seen[aName] = true
					specs[#specs + 1] = {
						name = aName,
						vtype = "auto",
						cat = "Attributes",
						writable = true,
						isAttr = true,
						attrName = aName,
					}
				end
			end
		end

		local q = F.trim(S.propSearch):lower()
		local items = {}
		local maxNW = 95

		for _, sp in ipairs(specs) do
			if q == "" or sp.name:lower():find(q, 1, true) or sp.cat:lower():find(q, 1, true) then
				local val = F.readPropValue(obj, sp)
				local realType = sp.vtype
				if realType == "auto" then
					realType = S.VALUE_TYPES[cls] or (typeof and typeof(val)) or type(val)
				end
				local entry = {
					spec = sp,
					realType = realType,
					val = val,
					valStr = F.formatPropValue(val, realType),
					depth = 1,
					refKey = sp.cat .. "|" .. sp.name,
				}
				local nw = #sp.name * 7 + 26
				if nw > maxNW then maxNW = nw end
				items[#items + 1] = entry
			end
		end

		table.sort(items, function(a, b)
			local o1 = S.CATEGORY_ORDER[a.spec.cat] or 99
			local o2 = S.CATEGORY_ORDER[b.spec.cat] or 99
			if o1 ~= o2 then return o1 < o2 end
			return a.spec.name < b.spec.name
		end)

		local tree = {}
		local curCat = nil
		for _, item in ipairs(items) do
			if item.spec.cat ~= curCat then
				curCat = item.spec.cat
				local catKey = "CAT:" .. curCat
				if S.propExpanded[catKey] == nil then S.propExpanded[catKey] = true end
				tree[#tree + 1] = {
					isCategory = true,
					name = curCat,
					refKey = catKey,
					depth = 0,
				}
			end
			if S.propExpanded["CAT:" .. curCat] or q ~= "" then
				tree[#tree + 1] = item
				local rt = item.realType
				if (rt == "Vector3" or rt == "Vector2" or rt == "CFrame") and S.propExpanded[item.refKey] then
					local axes = (rt == "Vector2") and {"X", "Y"} or {"X", "Y", "Z"}
					local vec = (rt == "CFrame" and item.val) and item.val.Position or item.val
					for _, ax in ipairs(axes) do
						local axVal = vec and vec[ax] or 0
						tree[#tree + 1] = {
							spec = {
								name = ax,
								vtype = "number",
								cat = item.spec.cat,
								writable = item.spec.writable,
								parentProp = item.spec.name,
								parentType = rt,
								axis = ax,
							},
							realType = "number",
							val = axVal,
							valStr = F.formatPropValue(axVal, "number"),
							depth = 2,
							refKey = item.refKey .. "|" .. ax,
						}
					end
				end
			end
		end

		S.propTree = tree
		S.propNameWidth = math.min(145, maxNW)
	end

	function F.refreshVisiblePropValues()
		if not S.propSelectedObj or #S.propTree == 0 then return end
		local obj = S.propSelectedObj
		for _, row in ipairs(S.propTree) do
			if not row.isCategory and row.spec then
				if row.spec.parentProp then
					local okP, pv = pcall(function() return obj[row.spec.parentProp] end)
					if okP and pv then
						local vec = (row.spec.parentType == "CFrame") and pv.Position or pv
						local av = vec and vec[row.spec.axis]
						row.val = av
						row.valStr = F.formatPropValue(av, "number")
					end
				else
					local val = F.readPropValue(obj, row.spec)
					row.val = val
					row.valStr = F.formatPropValue(val, row.realType)
				end
			end
		end
	end
end)();

--=====================================================================
-- 6. EXPLORER ACTIONS, CONTEXT MENU ITEMS & SCRIPT DECOMPILER
--=====================================================================
(function()
	S.viewer = {
		visible = false,
		title = "Script Viewer",
		lines = {},
		raw = "",
		scroll = 0,
		x = 180, y = 100, w = 540, h = 380,
		targetObj = nil,
	}

	function F.openScriptViewer(obj)
		if not obj then return end
		S.viewer.targetObj = obj
		S.viewer.title = F.safeName(obj) .. " (" .. F.safeClass(obj) .. ")"
		S.viewer.scroll = 0
		S.viewer.visible = true
		local ok, src = pcall(decompile, obj)
		local text
		if ok and type(src) == "string" and #src > 0 then
			text = src
		else
			text = "-- Unable to decompile " .. F.safeFullName(obj) .. "\n-- " .. tostring(src)
		end
		S.viewer.raw = text
		local lines = {}
		for line in (text .. "\n"):gmatch("(.-)\n") do
			lines[#lines + 1] = line:gsub("\r", ""):gsub("\t", "    ")
		end
		S.viewer.lines = lines
	end

	function F.actionCut()
		if #S.selectionList == 0 then return end
		S.clipboardCut = {}
		for _, node in ipairs(S.selectionList) do
			if node.obj and node.addr ~= S.rootNode.addr then
				S.clipboardCut[#S.clipboardCut + 1] = node
			end
		end
		F.notify("Dex", "Cut " .. #S.clipboardCut .. " item(s) for move")
	end

	function F.actionPasteInto()
		if #S.clipboardCut == 0 or #S.selectionList == 0 then return end
		local target = S.selectionList[1]
		if not target or not target.obj then return end
		local moved = 0
		for _, cutNode in ipairs(S.clipboardCut) do
			if cutNode.obj and cutNode.addr ~= target.addr then
				local ok = pcall(function() cutNode.obj.Parent = target.obj end)
				if ok then moved = moved + 1 end
			end
		end
		S.clipboardCut = {}
		S.expanded[target.addr] = true
		F.refreshExpandedTree()
		F.notify("Dex", "Moved " .. moved .. " item(s) into " .. target.name)
	end

	function F.actionDelete()
		if #S.selectionList == 0 then return end
		local deleted = 0
		for _, node in ipairs(S.selectionList) do
			if node.obj and node.addr ~= S.rootNode.addr then
				local ok = pcall(function() node.obj.Parent = nil end)
				if ok then deleted = deleted + 1 end
			end
		end
		F.clearSelection()
		F.refreshExpandedTree()
		F.rebuildPropTree()
		F.notify("Dex", "Unparented " .. deleted .. " item(s)")
	end

	function F.actionSelectChildren()
		if #S.selectionList == 0 then return end
		local nextSel = {}
		for _, node in ipairs(S.selectionList) do
			F.loadNodeChildren(node, true)
			S.expanded[node.addr] = true
			if node.children then
				for _, ch in ipairs(node.children) do
					nextSel[#nextSel + 1] = ch
				end
			end
		end
		F.setSelectionNodes(nextSel)
		F.rebuildTreeList()
		F.rebuildPropTree()
	end

	function F.actionJumpParent()
		local node = S.selectionList[1]
		if node and node.parent and node.parent.addr ~= S.rootNode.addr then
			F.setSelectionNodes({ node.parent })
			F.rebuildPropTree()
			for i, n in ipairs(S.treeList) do
				if n.addr == node.parent.addr then
					UI.expScroll = math.max(0, i - 4)
					break
				end
			end
		end
	end

	local PRIORITY_PART_NAMES = {
		"HumanoidRootPart", "Head", "Torso", "UpperTorso", "LowerTorso", "RootPart", "Handle", "Main"
	}

	local function isValidPart(p)
		if not p then return false end
		if not F.isClassA(F.safeClass(p), "BasePart") then return false end
		local ok, pos = pcall(function() return p.Position end)
		return ok and pos ~= nil and type(pos.X) == "number"
	end

	local function findPartInContainer(container)
		if not container then return nil end
		if isValidPart(container) then return container end

		for _, pName in ipairs(PRIORITY_PART_NAMES) do
			local okF, ch = pcall(function() return container:FindFirstChild(pName) end)
			if okF and isValidPart(ch) then
				return ch
			end
		end

		local cls = F.safeClass(container)
		if F.isClassA(cls, "Model") then
			local okP, pp = pcall(function() return container.PrimaryPart end)
			if okP and isValidPart(pp) then
				return pp
			end
		end

		for _, d in ipairs(F.safeChildren(container)) do
			if isValidPart(d) then return d end
		end

		local okD, desc = pcall(function() return container:GetDescendants() end)
		if okD and type(desc) == "table" then
			local firstValid = nil
			for _, d in ipairs(desc) do
				if isValidPart(d) then
					local dn = F.safeName(d)
					if dn == "HumanoidRootPart" or dn == "Head" or dn == "Torso" or dn == "UpperTorso" then
						return d
					end
					if not firstValid then firstValid = d end
				end
			end
			if firstValid then return firstValid end
		end
		return nil
	end

	function F.findTeleportTarget(obj)
		if not obj then return nil, nil, nil end
		if isValidPart(obj) then
			local _, pos = pcall(function() return obj.Position end)
			local _, cf = pcall(function() return obj.CFrame end)
			return obj, pos, cf
		end

		local cls = F.safeClass(obj)
		if cls == "Player" then
			local okC, ch = pcall(function() return obj.Character end)
			local part = okC and findPartInContainer(ch) or nil
			if not part and S.Workspace then
				local pName = F.safeName(obj)
				local okW, wCh = pcall(function() return S.Workspace:FindFirstChild(pName) end)
				if okW and wCh then part = findPartInContainer(wCh) end
			end
			if part then
				local _, pos = pcall(function() return part.Position end)
				local _, cf = pcall(function() return part.CFrame end)
				return part, pos, cf
			end
			return nil, nil, nil
		elseif cls == "Camera" then
			local okP, pos = pcall(function() return obj.Position end)
			local okCF, cf = pcall(function() return obj.CFrame end)
			if okP and pos ~= nil and type(pos.X) == "number" then
				return nil, pos, okCF and cf or nil
			end
			return nil, nil, nil
		end

		local part = findPartInContainer(obj)
		if not part then
			local cur = F.safeParent(obj)
			local hops = 0
			while cur and hops < 6 do
				hops = hops + 1
				local cCls = F.safeClass(cur)
				if cCls == "Workspace" or cCls == "DataModel" then break end
				if isValidPart(cur) then
					part = cur
					break
				elseif F.isClassA(cCls, "Model") or F.isClassA(cCls, "Tool") or F.isClassA(cCls, "Accessory") then
					part = findPartInContainer(cur)
					if part then break end
				end
				cur = F.safeParent(cur)
			end
		end

		if part then
			local _, pos = pcall(function() return part.Position end)
			local _, cf = pcall(function() return part.CFrame end)
			return part, pos, cf
		end
		return nil, nil, nil
	end

	function F.getLocalRoot()
		if not S.lp then F.initServices() end
		local lp = S.lp
		if not lp then return nil, nil end
		local okC, lpChar = pcall(function() return lp.Character end)
		local root = okC and findPartInContainer(lpChar) or nil
		if not root and S.Workspace then
			local okW, wChar = pcall(function() return S.Workspace:FindFirstChild(F.safeName(lp)) end)
			if okW and wChar then
				lpChar = wChar
				root = findPartInContainer(wChar)
			end
		end
		return root, lpChar
	end

	function F.actionTeleportTo()
		local hrp = F.getLocalRoot()
		if not hrp then
			F.notify("Dex", "Local character root not found")
			return
		end
		for _, node in ipairs(S.selectionList) do
			local _, tPos, tCF = F.findTeleportTarget(node.obj)
			if tPos then
				local destPos = tPos + Vector3.new(0, 3, 0)
				if tCF then
					pcall(function() hrp.CFrame = tCF + Vector3.new(0, 3, 0) end)
				else
					pcall(function() hrp.CFrame = CFrame.new(destPos.X, destPos.Y, destPos.Z) end)
				end
				pcall(function() hrp.Position = destPos end)
				local z = Vector3.new(0, 0, 0)
				pcall(function() hrp.Velocity = z end)
				pcall(function() hrp.AssemblyLinearVelocity = z end)
				F.notify("Dex", "Teleported to " .. tostring(node.name))
				return
			end
		end
		F.notify("Dex", "No teleport target found")
	end

	function F.actionTeleportHere()
		local hrp = F.getLocalRoot()
		if not hrp then
			F.notify("Dex", "Local character root not found")
			return
		end
		local _, myPos = pcall(function() return hrp.Position end)
		local _, myCF = pcall(function() return hrp.CFrame end)
		if not myPos then return end
		local destPos = myPos + Vector3.new(0, 2, 0)
		local destCF = myCF and (myCF + Vector3.new(0, 2, 0)) or CFrame.new(destPos.X, destPos.Y, destPos.Z)
		local z = Vector3.new(0, 0, 0)

		for _, node in ipairs(S.selectionList) do
			local part, tPos = F.findTeleportTarget(node.obj)
			if part then
				local delta = tPos and (destPos - tPos) or Vector3.new(0, 0, 0)
				local targetContainer = nil
				if node.className == "Player" then
					local okC, ch = pcall(function() return node.obj.Character end)
					if okC and ch then targetContainer = ch end
				elseif F.isClassA(node.className, "Model") then
					targetContainer = node.obj
				end
				if targetContainer and tPos then
					local okD, desc = pcall(function() return targetContainer:GetDescendants() end)
					if okD and type(desc) == "table" then
						for _, d in ipairs(desc) do
							if isValidPart(d) then
								pcall(function() d.Position = d.Position + delta end)
								pcall(function() d.Velocity = z end)
								pcall(function() d.AssemblyLinearVelocity = z end)
							end
						end
					end
				end
				pcall(function() part.CFrame = destCF end)
				pcall(function() part.Position = destPos end)
				pcall(function() part.Velocity = z end)
				pcall(function() part.AssemblyLinearVelocity = z end)
				F.notify("Dex", "Moved " .. tostring(node.name) .. " here")
				return
			end
		end
		F.notify("Dex", "No movable part found")
	end

	local function collectModelParts(container, maxParts)
		maxParts = maxParts or 48
		local parts = {}
		local seen = {}
		local function addPart(p)
			if #parts >= maxParts or not isValidPart(p) then return end
			local a = F.addrOf(p)
			if a and not seen[a] then
				seen[a] = true
				parts[#parts + 1] = p
			end
		end
		for _, d in ipairs(F.safeChildren(container)) do
			addPart(d)
		end
		if #parts < maxParts then
			local okD, desc = pcall(function() return container:GetDescendants() end)
			if okD and type(desc) == "table" then
				for _, d in ipairs(desc) do
					if #parts >= maxParts then break end
					addPart(d)
				end
			end
		end
		return parts
	end

	function F.rebuildSelectionEsp()
		local targets = {}
		local maxTargets = 8
		for _, node in ipairs(S.selectionList) do
			if #targets >= maxTargets then break end
			local obj = node and node.obj
			local cls = node and node.className or ""
			if obj and cls ~= "DataModel" and cls ~= "Workspace" then
				if isValidPart(obj) then
					targets[#targets + 1] = {
						kind = "part",
						name = node.name,
						className = cls,
						part = obj,
					}
				elseif cls == "Player" then
					local okC, ch = pcall(function() return obj.Character end)
					local charModel = (okC and ch and F.safeName(ch) ~= "Unreadable_name") and ch or nil
					if not charModel and S.Workspace then
						local okW, wCh = pcall(function() return S.Workspace:FindFirstChild(node.name) end)
						if okW and wCh then charModel = wCh end
					end
					if charModel then
						local parts = collectModelParts(charModel, 48)
						if #parts > 0 then
							targets[#targets + 1] = {
								kind = "model",
								name = node.name,
								className = "Player",
								container = charModel,
								parts = parts,
							}
						end
					end
				elseif F.isClassA(cls, "Model") or F.isClassA(cls, "Tool") or F.isClassA(cls, "Accessory") or cls == "Folder" then
					local parts = collectModelParts(obj, 48)
					if #parts > 0 then
						targets[#targets + 1] = {
							kind = "model",
							name = node.name,
							className = cls,
							container = obj,
							parts = parts,
						}
					end
				else
					local cur = F.safeParent(obj)
					local hops = 0
					while cur and hops < 5 do
						hops = hops + 1
						local cCls = F.safeClass(cur)
						if cCls == "Workspace" or cCls == "DataModel" then break end
						if isValidPart(cur) then
							targets[#targets + 1] = {
								kind = "part",
								name = node.name .. " (" .. F.safeName(cur) .. ")",
								className = cls,
								part = cur,
							}
							break
						elseif F.isClassA(cCls, "Model") or F.isClassA(cCls, "Tool") or F.isClassA(cCls, "Accessory") then
							local parts = collectModelParts(cur, 48)
							if #parts > 0 then
								targets[#targets + 1] = {
									kind = "model",
									name = node.name .. " (" .. F.safeName(cur) .. ")",
									className = cls,
									container = cur,
									parts = parts,
								}
								break
							end
						end
						cur = F.safeParent(cur)
					end
				end
			end
		end
		S.espTargets = targets
	end

	function F.findTopModelOfPart(part)
		local cur = F.safeParent(part)
		local bestModel = nil
		local hops = 0
		while cur and hops < 8 do
			hops = hops + 1
			local cls = F.safeClass(cur)
			if cls == "Workspace" or cls == "DataModel" then break end
			if F.isClassA(cls, "Model") or F.isClassA(cls, "Tool") or F.isClassA(cls, "Accessory") then
				bestModel = cur
			end
			cur = F.safeParent(cur)
		end
		return bestModel
	end

	function F.refreshPickableParts()
		if not S.Workspace then F.initServices() end
		if not S.Workspace then return end
		local _, lpChar = F.getLocalRoot()
		local lpCharAddr = lpChar and F.addrOf(lpChar) or 0
		local list = {}
		local okD, desc = pcall(function() return S.Workspace:GetDescendants() end)
		if okD and type(desc) == "table" then
			for _, d in ipairs(desc) do
				local cls = F.safeClass(d)
				if F.isClassA(cls, "BasePart") and cls ~= "Terrain" then
					local skip = false
					if lpCharAddr ~= 0 then
						local p = F.safeParent(d)
						if p and F.addrOf(p) == lpCharAddr then
							skip = true
						else
							local pp = p and F.safeParent(p)
							if pp and F.addrOf(pp) == lpCharAddr then skip = true end
						end
					end
					if not skip then
						list[#list + 1] = d
					end
				end
			end
		end
		S.pickableParts = list
		S.lastPickCacheTime = F.now()
	end

	function F.raycastScreenPart(sx, sy)
		if not S.Workspace then F.initServices() end
		local okCam, cam, cf, orig, fov, vp = pcall(function()
			local c = S.Workspace and S.Workspace.CurrentCamera
			return c, c.CFrame, c.Position, c.FieldOfView, c.ViewportSize
		end)
		if not (okCam and cam and cf and orig and fov and vp and vp.Y > 0) then
			return nil, nil
		end

		if #S.pickableParts == 0 or (F.now() - S.lastPickCacheTime) > 2.0 then
			F.refreshPickableParts()
		end

		local scale = (vp.Y * 0.5) / math.tan(math.rad(fov * 0.5))
		local rx = (sx - vp.X * 0.5) / scale
		local ry = (vp.Y * 0.5 - sy) / scale
		local dir = (cf.LookVector + cf.RightVector * rx + cf.UpVector * ry).Unit

		local bestPart = nil
		local bestT = math.huge
		local parts = S.pickableParts

		for i = 1, #parts do
			local part = parts[i]
			local okP, pPos, pSz, pCF = pcall(function()
				return part.Position, part.Size, part.CFrame
			end)
			if okP and pPos and pSz and pCF and type(pPos.X) == "number" then
				local rel = orig - pPos
				local hx = math.max(0.05, pSz.X * 0.5)
				local hy = math.max(0.05, pSz.Y * 0.5)
				local hz = math.max(0.05, pSz.Z * 0.5)
				local R, U, L = pCF.RightVector, pCF.UpVector, pCF.LookVector
				local ox, oy, oz = rel:Dot(R), rel:Dot(U), rel:Dot(L)
				local dx, dy, dz = dir:Dot(R), dir:Dot(U), dir:Dot(L)

				local tMin, tMax = -math.huge, math.huge
				local hit = true

				if math.abs(dx) < 1e-6 then
					if ox < -hx or ox > hx then hit = false end
				else
					local t1 = (-hx - ox) / dx
					local t2 = ( hx - ox) / dx
					if t1 > t2 then t1, t2 = t2, t1 end
					if t1 > tMin then tMin = t1 end
					if t2 < tMax then tMax = t2 end
					if tMin > tMax or tMax < 0 then hit = false end
				end

				if hit then
					if math.abs(dy) < 1e-6 then
						if oy < -hy or oy > hy then hit = false end
					else
						local t1 = (-hy - oy) / dy
						local t2 = ( hy - oy) / dy
						if t1 > t2 then t1, t2 = t2, t1 end
						if t1 > tMin then tMin = t1 end
						if t2 < tMax then tMax = t2 end
						if tMin > tMax or tMax < 0 then hit = false end
					end
				end

				if hit then
					if math.abs(dz) < 1e-6 then
						if oz < -hz or oz > hz then hit = false end
					else
						local t1 = (-hz - oz) / dz
						local t2 = ( hz - oz) / dz
						if t1 > t2 then t1, t2 = t2, t1 end
						if t1 > tMin then tMin = t1 end
						if t2 < tMax then tMax = t2 end
						if tMin > tMax or tMax < 0 then hit = false end
					end
				end

				if hit then
					local t = (tMin > 0) and tMin or tMax
					if t >= 0 and t < bestT then
						bestT = t
						bestPart = part
					end
				end
			end
		end
		return bestPart, bestT
	end

	function F.selectWorldPartAt(sx, sy)
		local hitPart = F.raycastScreenPart(sx, sy)
		if not hitPart then return false end
		local targetInst = hitPart
		if F.isShiftDown() then
			local mdl = F.findTopModelOfPart(hitPart)
			if mdl then targetInst = mdl end
		end
		UI.expWin.visible = true
		local node = F.revealInstance(targetInst)
		if node then
			if F.isCtrlDown() then
				F.toggleSelectionNode(node)
			else
				F.setSelectionNodes({ node })
			end
			F.rebuildPropTree()
			F.notify("Dex Pick", F.safeName(targetInst) .. " [" .. F.safeClass(targetInst) .. "]", 2)
			return true
		end
		return false
	end

	function F.openRenameDialog()
		local node = S.selectionList[1]
		if not node or not node.obj then return end
		UI.renameModal = {
			visible = true,
			node = node,
			text = node.name,
		}
		UI.focusTarget = "rename"
	end

	function F.buildContextMenu()
		local sel = S.selectionList
		local first = sel[1]
		local items = {}

		local cutMap = {}
		for _, c in ipairs(S.clipboardCut) do cutMap[c.addr] = true end

		items[#items + 1] = { name = "Cut (Move)", shortcut = "Ctrl+X", disabled = (#sel == 0), color = Color3.fromRGB(220, 160, 80), cb = F.actionCut }
		items[#items + 1] = { name = "Paste Into", shortcut = "Ctrl+B", disabled = (#S.clipboardCut == 0 or #sel == 0), color = Color3.fromRGB(110, 190, 130), cb = F.actionPasteInto }
		items[#items + 1] = { name = "Delete", shortcut = "Ctrl+Del", disabled = (#sel == 0), color = Color3.fromRGB(230, 95, 95), cb = F.actionDelete }
		items[#items + 1] = { name = "Rename", shortcut = "Ctrl+R", disabled = (#sel == 0), color = Color3.fromRGB(150, 185, 235), cb = F.openRenameDialog }
		items[#items + 1] = { divider = true }

		items[#items + 1] = { name = "Select Children", shortcut = "", disabled = (#sel == 0), color = Color3.fromRGB(220, 180, 70), cb = F.actionSelectChildren }
		items[#items + 1] = { name = "Jump To Parent", shortcut = "", disabled = (not first or not first.parent or first.parent.addr == S.rootNode.addr), color = Color3.fromRGB(140, 180, 230), cb = F.actionJumpParent }
		items[#items + 1] = { name = "Copy Path", shortcut = "", disabled = (not first), color = Color3.fromRGB(170, 175, 190), cb = function()
			if first then F.copyToClipboard(F.safeFullName(first.obj)); F.notify("Dex", "Path copied") end
		end }
		items[#items + 1] = { name = "Copy Address", shortcut = "", disabled = (not first), color = Color3.fromRGB(170, 175, 190), cb = function()
			if first then F.copyToClipboard(string.format("0x%X", first.addr)); F.notify("Dex", "Address copied") end
		end }

		local canTeleport = false
		local hasPlayer = false
		local charOwner = nil
		local hasScript = false
		for _, node in ipairs(sel) do
			if F.isClassA(node.className, "BasePart")
				or F.isClassA(node.className, "Model")
				or node.className == "Player"
				or node.className == "Camera"
				or F.isClassA(node.className, "Tool")
				or F.isClassA(node.className, "Accessory")
				or node.className == "Humanoid"
			then
				canTeleport = true
			else
				local _, tPos = F.findTeleportTarget(node.obj)
				if tPos ~= nil then canTeleport = true end
			end
			if node.className == "Player" then hasPlayer = true end
			if F.isClassA(node.className, "LuaSourceContainer") then hasScript = true end
			if S.Players then
				for _, plr in ipairs(S.Players:GetPlayers()) do
					local okC, pc = pcall(function() return plr.Character end)
					if okC and pc and F.addrOf(pc) == node.addr then
						charOwner = plr
						break
					elseif F.isClassA(node.className, "Model") and F.safeName(plr) == node.name then
						charOwner = plr
						break
					end
				end
			end
		end

		if canTeleport then
			items[#items + 1] = { divider = true }
			items[#items + 1] = { name = "Teleport To", shortcut = "", disabled = false, color = Color3.fromRGB(95, 195, 225), cb = F.actionTeleportTo }
			items[#items + 1] = { name = "Teleport Here", shortcut = "", disabled = false, color = Color3.fromRGB(95, 195, 225), cb = F.actionTeleportHere }
		end

		if hasPlayer or charOwner then
			items[#items + 1] = { divider = true }
			if hasPlayer then
				items[#items + 1] = { name = "Jump To Character", shortcut = "", disabled = false, color = Color3.fromRGB(100, 200, 130), cb = function()
					local ch = first and first.obj and first.obj.Character
					if (not ch or F.safeName(ch) == "Unreadable_name") and first and S.Workspace then
						local okW, wCh = pcall(function() return S.Workspace:FindFirstChild(first.name) end)
						if okW and wCh then ch = wCh end
					end
					if ch then
						local node = F.revealInstance(ch)
						if node then F.setSelectionNodes({node}); F.rebuildPropTree() end
					end
				end }
			end
			if charOwner then
				items[#items + 1] = { name = "Jump To Player", shortcut = "", disabled = false, color = Color3.fromRGB(100, 200, 130), cb = function()
					local node = F.revealInstance(charOwner)
					if node then F.setSelectionNodes({node}); F.rebuildPropTree() end
				end }
			end
		end

		if hasScript and first then
			items[#items + 1] = { divider = true }
			items[#items + 1] = { name = "View / Decompile", shortcut = "", disabled = false, color = Color3.fromRGB(165, 115, 230), cb = function()
				F.openScriptViewer(first.obj)
			end }
		end

		return items
	end
end)();

--=====================================================================
-- 7. DEX UI LAYOUT, DRAWING POOLS & RENDERER
--=====================================================================
(function()
	local vp = F.getViewport()

	-- Exact Dex Palette
	local C_DARK     = Color3.fromRGB(30, 30, 30)
	local C_BLACK    = Color3.fromRGB(10, 10, 10)
	local C_TOPBAR   = Color3.fromRGB(48, 48, 48)
	local C_BG       = Color3.fromRGB(64, 64, 64)
	local C_BORDER   = Color3.fromRGB(37, 53, 54)
	local C_PROP_BG  = Color3.fromRGB(74, 74, 76)
	local C_PROP_BD  = Color3.fromRGB(96, 96, 96)
	local C_CTX_BG   = Color3.fromRGB(80, 80, 80)
	local C_CTX_BD   = Color3.fromRGB(112, 112, 112)
	local C_SEARCH   = Color3.fromRGB(80, 80, 80)
	local C_BLUE     = Color3.fromRGB(34, 167, 240)
	local C_SEL      = Color3.fromRGB(96, 140, 211)
	local C_SEL_BD   = Color3.fromRGB(86, 125, 188)
	local C_HOV      = Color3.fromRGB(78, 82, 90)
	local C_TXT      = Color3.fromRGB(220, 220, 220)
	local C_TXT_RO   = Color3.fromRGB(144, 144, 144)
	local C_TXT_DIM  = Color3.fromRGB(110, 110, 115)
	local C_WHITE    = Color3.new(1, 1, 1)
	local C_SCR_TRK  = Color3.fromRGB(88, 88, 90)
	local C_SCR_THM  = Color3.fromRGB(122, 122, 125)
	local C_SCR_THM2 = Color3.fromRGB(145, 145, 150)
	local C_SCR_BTN  = Color3.fromRGB(68, 68, 70)

	-- UI State
	UI.uiHidden = false
	UI.focusTarget = nil -- nil | "expSearch" | "propSearch" | "propEdit" | "rename"
	UI.expSearch = { text = "" }
	UI.propSearch = { text = "" }
	UI.propEdit = { spec = nil, text = "" }
	UI.renameModal = { visible = false, node = nil, text = "" }

	UI.rightPaneWidth = 300
	UI.splitRatio = 0.50
	UI.paneSide = "Right" -- "Right" | "Left"

	UI.expWin = { visible = true, docked = true, x = vp.X - 300, y = 0, w = 300, h = math.floor(vp.Y * 0.5), floatW = 310, floatH = 360 }
	UI.propWin = { visible = true, docked = true, x = vp.X - 300, y = math.floor(vp.Y * 0.5), w = 300, h = math.ceil(vp.Y * 0.5), floatW = 310, floatH = 360 }

	UI.expScroll = 0
	UI.expScrollH = 0
	UI.expScrollTargetIdx = nil
	UI.propScroll = 0
	UI.viewsOpen = false
	UI.settingsWin = { visible = false, x = math.max(20, vp.X - 530), y = 60, w = 215, h = 224 }

	UI.welcome = {
		visible = true,
		step = 1,
		autoCloseAt = F.now() + 2.2,
	}

	UI.ctx = { visible = false, x = 0, y = 0, w = 204, items = {} }

	local MAX_EXP_ROWS = 48
	local MAX_PROP_ROWS = 42
	local MAX_CTX_ROWS = 22
	local MAX_VIEW_ROWS = 22
	local MAX_VIEW_MENU = 7

	local function sq(z, color, filled)
		return F.newDraw("Square", { ZIndex = z, Color = color or C_BG, Filled = (filled ~= false), Visible = false })
	end
	local function ln(z, color, thick)
		return F.newDraw("Line", { ZIndex = z, Color = color or C_PROP_BD, Thickness = thick or 1, Visible = false })
	end
	local function tx(z, size, color, font, center)
		return F.newDraw("Text", { ZIndex = z, Size = size or 14, Color = color or C_TXT, Font = font or 0, Center = (center == true), Visible = false })
	end
	local function tri(z, color, filled)
		return F.newDraw("Triangle", { ZIndex = z, Color = color or C_TXT, Filled = (filled ~= false), Visible = false })
	end

	-- -----------------------------------------------------------------
	-- TopMenu Drawing Objects (ZIndex 40..44)
	-- -----------------------------------------------------------------
	local TM = {
		bg = sq(40, C_DARK),
		wingL = tri(40, C_DARK),
		wingR = tri(40, C_DARK),
		title = tx(41, 14, C_WHITE, 2),
		ver = tx(41, 12, C_TXT, 0),
		slideBg = sq(41, C_BLACK),
		slideBd = sq(42, C_TOPBAR, false),
		slideArrowBg = sq(42, C_DARK),
		slideArrow = tri(43, C_TXT),
		slideTxt = tx(43, 13, C_WHITE, 0),
		aboutBg = sq(41, C_TOPBAR),
		aboutTxt = tx(42, 14, C_WHITE, 2, true),
		dropBg = sq(45, C_DARK),
		dropBd = sq(46, C_CTX_BD, false),
		dropRows = {},
	}
	for i = 1, MAX_VIEW_MENU do
		TM.dropRows[i] = {
			bg = sq(46, C_DARK),
			txt = tx(47, 13, C_TXT, 0),
		}
	end

	-- -----------------------------------------------------------------
	-- WelcomeFrame Drawing Objects (ZIndex 50..55)
	-- -----------------------------------------------------------------
	local WL = {
		outerBd = sq(50, C_BLACK),
		mainBg = sq(51, C_TOPBAR),
		rightBg = sq(51, C_BG),
		closeBg = sq(52, C_TOPBAR),
		closeTxt = tx(53, 15, C_WHITE, 2, true),
		title = tx(52, 38, C_WHITE, 2),
		ver = tx(52, 16, C_WHITE, 2),
		credit = tx(52, 14, C_TXT, 2),
		progLine = sq(52, C_SEARCH),
		prog = {},
		chgBg = sq(52, C_BG),
		chgBd = sq(53, C_CTX_BD, false),
		chgTitle = tx(53, 14, C_WHITE, 2, true),
		chgLines = {},
		botBg = sq(52, C_BG),
		logoOut = sq(53, C_BLUE),
		logoIn = tx(54, 15, C_WHITE, 2, true),
		desc = tx(53, 15, C_WHITE, 0),
		subCred = tx(53, 12, C_TXT, 0),
	}
	for i = 1, 5 do WL.prog[i] = tx(52, 13, C_TXT_DIM, 0) end
	for i = 1, 9 do WL.chgLines[i] = tx(53, 12, C_TXT, 0) end

	-- -----------------------------------------------------------------
	-- ExplorerPanel Pool (ZIndex 10..17)
	-- -----------------------------------------------------------------
	local EX = {
		bg = sq(10, C_BG),
		bd = sq(11, C_BORDER, false),
		topBar = sq(12, C_TOPBAR),
		title = tx(13, 14, C_TXT, 0, true),
		pickBg = sq(13, C_BG),
		pickBd = sq(14, C_BLUE, false),
		pickTxt = tx(14, 12, C_WHITE, 2, true),
		closeBg = sq(13, C_TOPBAR),
		closeTxt = tx(14, 14, C_TXT, 2, true),
		setBg = sq(13, C_TOPBAR),
		setTxt = tx(14, 14, C_TXT, 2, true),
		sUnder = sq(13, C_SEARCH),
		sActive = sq(14, C_BLUE),
		sTxt = tx(14, 13, C_TXT, 0),
		-- Vertical Scrollbar
		vTrk = sq(13, C_SCR_TRK),
		vThm = sq(14, C_SCR_THM),
		vUpBg = sq(14, C_SCR_BTN),
		vUpTri = tri(15, C_TXT),
		vDnBg = sq(14, C_SCR_BTN),
		vDnTri = tri(15, C_TXT),
		-- Horizontal Scrollbar
		hTrk = sq(13, C_SCR_TRK),
		hThm = sq(14, C_SCR_THM),
		hLtBg = sq(14, C_SCR_BTN),
		hLtTri = tri(15, C_TXT),
		hRtBg = sq(14, C_SCR_BTN),
		hRtTri = tri(15, C_TXT),
		rows = {},
	}
	for i = 1, MAX_EXP_ROWS do
		EX.rows[i] = {
			bg = sq(11, C_SEL),
			bd = sq(12, C_SEL_BD, false),
			expTri = tri(13, C_TXT),
			iconBg = sq(13, C_BLUE),
			iconTx = tx(14, 11, C_WHITE, 2, true),
			label = tx(13, 14, C_TXT, 0),
		}
	end

	-- -----------------------------------------------------------------
	-- PropertiesPanel Pool (ZIndex 10..17)
	-- -----------------------------------------------------------------
	local PR = {
		bg = sq(10, C_BG),
		bd = sq(11, C_BORDER, false),
		topBar = sq(12, C_TOPBAR),
		title = tx(13, 14, C_TXT, 0, true),
		closeBg = sq(13, C_TOPBAR),
		closeTxt = tx(14, 14, C_TXT, 2, true),
		setBg = sq(13, C_TOPBAR),
		setTxt = tx(14, 14, C_TXT, 2, true),
		sUnder = sq(13, C_SEARCH),
		sActive = sq(14, C_BLUE),
		sTxt = tx(14, 13, C_TXT, 0),
		vTrk = sq(13, C_SCR_TRK),
		vThm = sq(14, C_SCR_THM),
		vUpBg = sq(14, C_SCR_BTN),
		vUpTri = tri(15, C_TXT),
		vDnBg = sq(14, C_SCR_BTN),
		vDnTri = tri(15, C_TXT),
		rows = {},
	}
	for i = 1, MAX_PROP_ROWS do
		PR.rows[i] = {
			bg = sq(11, C_PROP_BG),
			bot = ln(12, C_PROP_BD, 1),
			sep = ln(12, C_PROP_BD, 1),
			expTri = tri(13, C_TXT),
			nameTxt = tx(13, 13, C_TXT, 0),
			valBg = sq(12, C_TOPBAR),
			valBd = sq(13, C_BLUE, false),
			swatch = sq(13, C_WHITE),
			valTxt = tx(13, 13, C_TXT, 0),
		}
	end

	-- -----------------------------------------------------------------
	-- Splitter, Dock Preview, Context Menu, Settings, Rename & Script Viewer
	-- -----------------------------------------------------------------
	local SP = {
		splitter = sq(18, C_BORDER),
		edgeGrip = sq(18, C_BORDER),
		dockPrev = sq(35, C_SEL, false),
	}
	SP.dockPrev.Thickness = 2

	local CT = {
		bg = sq(60, C_CTX_BG),
		bd = sq(61, C_CTX_BD, false),
		rows = {},
	}
	for i = 1, MAX_CTX_ROWS do
		CT.rows[i] = {
			bg = sq(61, C_SEL),
			icon = sq(62, C_BLUE),
			name = tx(62, 13, C_TXT, 0),
			short = tx(62, 12, C_TXT_RO, 0),
			div = ln(62, C_CTX_BD, 1),
		}
	end

	local ST = {
		bg = sq(55, C_CTX_BG),
		bd = sq(56, C_CTX_BD, false),
		bar = sq(56, C_TOPBAR),
		title = tx(57, 13, C_WHITE, 2),
		close = tx(57, 13, C_WHITE, 2, true),
		rows = {},
	}
	for i = 1, 8 do
		ST.rows[i] = {
			bg = sq(56, C_BG),
			txt = tx(57, 13, C_TXT, 0),
		}
	end

	-- -----------------------------------------------------------------
	-- Selection 3D ESP / SelectionBox Pool (ZIndex 5..9)
	-- -----------------------------------------------------------------
	local MAX_ESP_SLOTS = 8
	local C_GOLD = Color3.fromRGB(255, 195, 55)
	local CUBE_EDGES = {
		{1, 2}, {2, 3}, {3, 4}, {4, 1},
		{5, 6}, {6, 7}, {7, 8}, {8, 5},
		{1, 5}, {2, 6}, {3, 7}, {4, 8},
	}
	local ESP = { slots = {}, hover = nil }
	for i = 1, MAX_ESP_SLOTS do
		local edges = {}
		for e = 1, 12 do
			edges[e] = ln(6, C_BLUE, 2)
		end
		ESP.slots[i] = {
			edges = edges,
			box2d = sq(5, Color3.fromRGB(95, 205, 255), false),
			dot = F.newDraw("Circle", { ZIndex = 7, Color = C_BLUE, Radius = 3.5, Filled = true, Visible = false }),
			tagBg = sq(7, Color3.fromRGB(22, 24, 28), true),
			tagBd = sq(8, C_BLUE, false),
			tagTxt = tx(9, 13, C_WHITE, 2, true),
		}
	end
	do
		local hEdges = {}
		for e = 1, 12 do
			hEdges[e] = ln(6, C_GOLD, 2)
		end
		ESP.hover = {
			edges = hEdges,
			box2d = sq(5, C_GOLD, false),
			dot = F.newDraw("Circle", { ZIndex = 7, Color = C_GOLD, Radius = 3.5, Filled = true, Visible = false }),
			tagBg = sq(7, Color3.fromRGB(28, 24, 16), true),
			tagBd = sq(8, C_GOLD, false),
			tagTxt = tx(9, 13, C_GOLD, 2, true),
		}
	end

	local RN = {
		bg = sq(70, C_TOPBAR),
		bd = sq(71, C_CTX_BD, false),
		title = tx(71, 14, C_WHITE, 2),
		box = sq(71, C_BG),
		boxBd = sq(72, C_BLUE, false),
		input = tx(72, 13, C_WHITE, 0),
		okBg = sq(71, C_SEL),
		okTx = tx(72, 13, C_WHITE, 2, true),
		caBg = sq(71, C_BG),
		caTx = tx(72, 13, C_TXT, 0, true),
	}

	local SV = {
		bg = sq(30, C_TOPBAR),
		bd = sq(31, C_CTX_BD, false),
		bar = sq(31, C_DARK),
		title = tx(32, 13, C_WHITE, 2),
		copyBg = sq(32, C_SEL),
		copyTx = tx(33, 12, C_WHITE, 2, true),
		upBg = sq(32, C_BG),
		upTx = tx(33, 12, C_WHITE, 2, true),
		dnBg = sq(32, C_BG),
		dnTx = tx(33, 12, C_WHITE, 2, true),
		closeBg = sq(32, C_DARK),
		closeTx = tx(33, 13, C_WHITE, 2, true),
		codeBg = sq(31, Color3.fromRGB(35, 37, 42)),
		lines = {},
	}
	for i = 1, MAX_VIEW_ROWS do
		SV.lines[i] = {
			num = tx(32, 13, C_TXT_DIM, 5),
			txt = tx(32, 13, C_TXT, 5),
		}
	end

	-- Helper to draw triangle pointing up/down/left/right inside box (x,y,w,h)
	local function setTriDir(t, x, y, w, h, dir, col)
		local cx, cy = x + w * 0.5, y + h * 0.5
		if dir == "up" then
			t.PointA = Vector2.new(cx, cy - 3)
			t.PointB = Vector2.new(cx - 4, cy + 2)
			t.PointC = Vector2.new(cx + 4, cy + 2)
		elseif dir == "down" then
			t.PointA = Vector2.new(cx - 4, cy - 2)
			t.PointB = Vector2.new(cx + 4, cy - 2)
			t.PointC = Vector2.new(cx, cy + 3)
		elseif dir == "right" then
			t.PointA = Vector2.new(cx - 2, cy - 4)
			t.PointB = Vector2.new(cx - 2, cy + 4)
			t.PointC = Vector2.new(cx + 3, cy)
		elseif dir == "left" then
			t.PointA = Vector2.new(cx + 2, cy - 4)
			t.PointB = Vector2.new(cx + 2, cy + 4)
			t.PointC = Vector2.new(cx - 3, cy)
		end
		t.Color = col
		t.Visible = true
	end

	local function hideGroup(tbl)
		for _, v in pairs(tbl) do
			if type(v) == "table" then
				hideGroup(v)
			else
				pcall(function() v.Visible = false end)
			end
		end
	end

	local function drawScrollbar(sb, x, y, w, h, total, visibleCount, index, hor, mPos, m1, clicked, state)
		local canUp = index > 0
		local canDn = index + visibleCount < total
		local maxIdx = math.max(0, total - visibleCount)

		sb.trk.Position = Vector2.new(x, y); sb.trk.Size = Vector2.new(w, h); sb.trk.Visible = true
		sb.b1.Position = Vector2.new(x, y); sb.b1.Size = Vector2.new(16, 16)
		sb.b1.Color = F.pointInRect(mPos, x, y, 16, 16) and C_HOV or C_SCR_BTN; sb.b1.Visible = true

		local b2x = hor and (x + w - 16) or x
		local b2y = hor and y or (y + h - 16)
		sb.b2.Position = Vector2.new(b2x, b2y); sb.b2.Size = Vector2.new(16, 16)
		sb.b2.Color = F.pointInRect(mPos, b2x, b2y, 16, 16) and C_HOV or C_SCR_BTN; sb.b2.Visible = true

		setTriDir(sb.t1, x, y, 16, 16, hor and "left" or "up", canUp and C_TXT or C_TXT_DIM)
		setTriDir(sb.t2, b2x, b2y, 16, 16, hor and "right" or "down", canDn and C_TXT or C_TXT_DIM)

		local trackSpan = (hor and w or h) - 32
		if total > visibleCount and trackSpan > 18 then
			local thumbSpan = math.max(18, math.floor(trackSpan * (visibleCount / total)))
			local frac = maxIdx > 0 and (index / maxIdx) or 0
			local thumbOff = math.floor(frac * (trackSpan - thumbSpan))
			local txPos = hor and (x + 16 + thumbOff) or x
			local tyPos = hor and y or (y + 16 + thumbOff)
			local tw = hor and thumbSpan or 16
			local th = hor and 16 or thumbSpan
			local hovThm = F.pointInRect(mPos, txPos, tyPos, tw, th)
			sb.thm.Position = Vector2.new(txPos, tyPos); sb.thm.Size = Vector2.new(tw, th)
			sb.thm.Color = (hovThm or state.dragging) and C_SCR_THM2 or C_SCR_THM
			sb.thm.Visible = true

			if clicked then
				if F.pointInRect(mPos, txPos, tyPos, tw, th) then
					state.dragging = true
					state.dragOffset = (hor and mPos.X or mPos.Y) - (hor and txPos or tyPos)
				elseif F.pointInRect(mPos, x, y, 16, 16) then
					state.holdDir = -1; state.holdAt = F.now(); index = math.max(0, index - state.step)
				elseif F.pointInRect(mPos, b2x, b2y, 16, 16) then
					state.holdDir = 1; state.holdAt = F.now(); index = math.min(maxIdx, index + state.step)
				elseif F.pointInRect(mPos, x, y, w, h) then
					local cur = hor and mPos.X or mPos.Y
					local thMid = (hor and txPos or tyPos) + thumbSpan * 0.5
					if cur < thMid then index = math.max(0, index - math.max(1, visibleCount - 2))
					else index = math.min(maxIdx, index + math.max(1, visibleCount - 2)) end
				end
			elseif state.dragging and m1 then
				local base = hor and (x + 16) or (y + 16)
				local cur = (hor and mPos.X or mPos.Y) - state.dragOffset - base
				local avail = math.max(1, trackSpan - thumbSpan)
				local p = math.clamp(cur / avail, 0, 1)
				index = math.floor(p * maxIdx + 0.5)
			elseif state.holdDir ~= 0 and m1 then
				local nowT = F.now()
				if nowT - state.holdAt >= 0.28 then
					index = math.clamp(index + state.holdDir * state.step, 0, maxIdx)
				end
			end
		else
			sb.thm.Visible = false
		end
		if not m1 then
			state.dragging = false
			state.holdDir = 0
		end
		return math.clamp(index, 0, maxIdx)
	end

	-- Scroll states
	local scrExpV = { dragging = false, dragOffset = 0, holdDir = 0, holdAt = 0, step = 1 }
	local scrExpH = { dragging = false, dragOffset = 0, holdDir = 0, holdAt = 0, step = 20 }
	local scrPropV = { dragging = false, dragOffset = 0, holdDir = 0, holdAt = 0, step = 1 }

	-- Dragging & click state
	local drag = {
		prevM1 = false,
		prevM2 = false,
		m2Candidate = nil,
		mode = nil, -- "exp" | "prop" | "split" | "edge" | "viewer" | "settings"
		off = Vector2.new(0, 0),
		lastClickTime = 0,
		lastClickAddr = nil,
		winOrder = { "exp", "prop" }, -- front is last
	}

	local function bringWinFront(which)
		for i = #drag.winOrder, 1, -1 do
			if drag.winOrder[i] == which then table.remove(drag.winOrder, i) end
		end
		drag.winOrder[#drag.winOrder + 1] = which
	end

	local function layoutDockedPanes(curVP)
		local docked = {}
		if UI.expWin.visible and UI.expWin.docked then docked[#docked + 1] = UI.expWin end
		if UI.propWin.visible and UI.propWin.docked then docked[#docked + 1] = UI.propWin end
		if #docked == 0 then return end

		local px = (UI.paneSide == "Left") and 0 or (curVP.X - UI.rightPaneWidth)
		if #docked == 1 then
			docked[1].x = px
			docked[1].y = 0
			docked[1].w = UI.rightPaneWidth
			docked[1].h = curVP.Y
		else
			local h1 = math.floor(curVP.Y * UI.splitRatio)
			UI.expWin.x = px; UI.expWin.y = 0; UI.expWin.w = UI.rightPaneWidth; UI.expWin.h = h1
			UI.propWin.x = px; UI.propWin.y = h1; UI.propWin.w = UI.rightPaneWidth; UI.propWin.h = curVP.Y - h1
		end
	end

	local function getViewDropdownItems()
		return {
			{ label = (UI.expWin.visible and "[x] " or "[ ] ") .. "Explorer", cb = function()
				UI.expWin.visible = not UI.expWin.visible
				UI.viewsOpen = false
			end },
			{ label = (UI.propWin.visible and "[x] " or "[ ] ") .. "Properties", cb = function()
				UI.propWin.visible = not UI.propWin.visible
				UI.viewsOpen = false
			end },
			{ label = (S.viewer.visible and "[x] " or "[ ] ") .. "Script Viewer", cb = function()
				S.viewer.visible = not S.viewer.visible
				UI.viewsOpen = false
			end },
			{ label = "Dock Both Right", cb = function()
				UI.paneSide = "Right"
				UI.expWin.visible = true; UI.expWin.docked = true
				UI.propWin.visible = true; UI.propWin.docked = true
				UI.splitRatio = 0.50
				UI.viewsOpen = false
			end },
			{ label = "Refresh Explorer", cb = function()
				F.refreshExpandedTree()
				UI.viewsOpen = false
			end },
			{ label = "Hide UI (Delete)", cb = function()
				UI.uiHidden = true
				UI.viewsOpen = false
			end },
			{ label = "Unload Dex", cb = function()
				UI.viewsOpen = false
				if _G.DEX_MATCHA_CLEANUP then _G.DEX_MATCHA_CLEANUP() end
			end },
		}
	end

	local function getSettingsItems()
		return {
			{ label = "Refresh Tree", cb = function() F.refreshExpandedTree(); UI.settingsWin.visible = false end },
			{ label = "Collapse All", cb = function()
				S.expanded = { [S.rootNode.addr] = true }
				F.rebuildTreeList()
				UI.settingsWin.visible = false
			end },
			{ label = "Selection ESP: " .. (S.selectionEsp and "ON" or "OFF"), cb = function()
				S.selectionEsp = not S.selectionEsp
			end },
			{ label = "Click to Select: " .. (S.clickSelectMode and "ON" or "OFF"), cb = function()
				S.clickSelectMode = not S.clickSelectMode
				if S.clickSelectMode then
					F.refreshPickableParts()
					F.notify("Dex Pick", "Click a 3D part (Shift+Click for Model)", 3)
				else
					S.hoverPickTarget = nil
				end
			end },
			{ label = "Hidden Services: " .. (S.showHiddenServices and "ON" or "OFF"), cb = function()
				S.showHiddenServices = not S.showHiddenServices
				F.refreshExpandedTree()
			end },
			{ label = "Auto-Refresh: " .. (S.autoRefresh and "ON" or "OFF"), cb = function()
				S.autoRefresh = not S.autoRefresh
			end },
			{ label = "Dock Side: " .. UI.paneSide, cb = function()
				UI.paneSide = (UI.paneSide == "Right") and "Left" or "Right"
			end },
			{ label = "Reset Split & Width", cb = function()
				UI.rightPaneWidth = 300; UI.splitRatio = 0.50
			end },
		}
	end

	local function hideEspSlot(slot)
		for e = 1, 12 do slot.edges[e].Visible = false end
		slot.box2d.Visible = false
		slot.dot.Visible = false
		slot.tagBg.Visible = false
		slot.tagBd.Visible = false
		slot.tagTxt.Visible = false
	end

	local function drawEspTargetOnSlot(slot, t, refPos, curVP, customLabel)
		if not t then
			hideEspSlot(slot)
			return false
		end
		local corners = nil
		local centerPos = nil

		if t.kind == "part" and t.part then
			local okP, pos, sz, cf = pcall(function()
				return t.part.Position, t.part.Size, t.part.CFrame
			end)
			if okP and pos and sz and type(pos.X) == "number" then
				centerPos = pos
				local hx = math.max(0.1, sz.X * 0.5)
				local hy = math.max(0.1, sz.Y * 0.5)
				local hz = math.max(0.1, sz.Z * 0.5)
				if cf then
					local okC, R, U, L = pcall(function()
						return cf.RightVector, cf.UpVector, cf.LookVector
					end)
					if okC and R and U and L then
						local rx, ry, rz = R * hx, U * hy, L * hz
						corners = {
							pos - rx - ry - rz,
							pos + rx - ry - rz,
							pos + rx + ry - rz,
							pos - rx + ry - rz,
							pos - rx - ry + rz,
							pos + rx - ry + rz,
							pos + rx + ry + rz,
							pos - rx + ry + rz,
						}
					end
				end
				if not corners then
					corners = {
						pos + Vector3.new(-hx, -hy, -hz),
						pos + Vector3.new( hx, -hy, -hz),
						pos + Vector3.new( hx,  hy, -hz),
						pos + Vector3.new(-hx,  hy, -hz),
						pos + Vector3.new(-hx, -hy,  hz),
						pos + Vector3.new( hx, -hy,  hz),
						pos + Vector3.new( hx,  hy,  hz),
						pos + Vector3.new(-hx,  hy,  hz),
					}
				end
			end
		elseif t.kind == "model" and t.parts and #t.parts > 0 then
			local minX, minY, minZ = math.huge, math.huge, math.huge
			local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge
			local validCount = 0
			for _, p in ipairs(t.parts) do
				local okP, pos, sz = pcall(function() return p.Position, p.Size end)
				if okP and pos and sz and type(pos.X) == "number" then
					validCount = validCount + 1
					local hx, hy, hz = math.max(0.1, sz.X * 0.5), math.max(0.1, sz.Y * 0.5), math.max(0.1, sz.Z * 0.5)
					if pos.X - hx < minX then minX = pos.X - hx end
					if pos.Y - hy < minY then minY = pos.Y - hy end
					if pos.Z - hz < minZ then minZ = pos.Z - hz end
					if pos.X + hx > maxX then maxX = pos.X + hx end
					if pos.Y + hy > maxY then maxY = pos.Y + hy end
					if pos.Z + hz > maxZ then maxZ = pos.Z + hz end
				end
			end
			if validCount > 0 then
				centerPos = Vector3.new((minX + maxX) * 0.5, (minY + maxY) * 0.5, (minZ + maxZ) * 0.5)
				corners = {
					Vector3.new(minX, minY, minZ),
					Vector3.new(maxX, minY, minZ),
					Vector3.new(maxX, maxY, minZ),
					Vector3.new(minX, maxY, minZ),
					Vector3.new(minX, minY, maxZ),
					Vector3.new(maxX, minY, maxZ),
					Vector3.new(maxX, maxY, maxZ),
					Vector3.new(minX, maxY, maxZ),
				}
			end
		end

		if not (corners and centerPos) then
			hideEspSlot(slot)
			return false
		end

		local sp = {}
		local vis = {}
		local sMinX, sMinY = math.huge, math.huge
		local sMaxX, sMaxY = -math.huge, -math.huge
		local visCorners = 0

		for cIdx = 1, 8 do
			local okW, pt, onScr = pcall(WorldToScreen, corners[cIdx])
			if okW and pt and onScr then
				sp[cIdx] = pt
				vis[cIdx] = true
				visCorners = visCorners + 1
				if pt.X < sMinX then sMinX = pt.X end
				if pt.Y < sMinY then sMinY = pt.Y end
				if pt.X > sMaxX then sMaxX = pt.X end
				if pt.Y > sMaxY then sMaxY = pt.Y end
			else
				vis[cIdx] = false
			end
		end

		local okCen, cenPt, cenVis = pcall(WorldToScreen, centerPos)
		local hasCen = (okCen and cenPt and cenVis) or false
		if hasCen then
			if cenPt.X < sMinX then sMinX = cenPt.X end
			if cenPt.Y < sMinY then sMinY = cenPt.Y end
			if cenPt.X > sMaxX then sMaxX = cenPt.X end
			if cenPt.Y > sMaxY then sMaxY = cenPt.Y end
		end

		for eIdx = 1, 12 do
			local edge = CUBE_EDGES[eIdx]
			local a, b = edge[1], edge[2]
			local lnObj = slot.edges[eIdx]
			if vis[a] and vis[b] then
				lnObj.From = sp[a]
				lnObj.To = sp[b]
				lnObj.Visible = true
			else
				lnObj.Visible = false
			end
		end

		if visCorners > 0 or hasCen then
			local bw = sMaxX - sMinX
			local bh = sMaxY - sMinY
			if t.kind == "model" and visCorners >= 2 and bw >= 4 and bh >= 4 and bw <= curVP.X * 1.4 and bh <= curVP.Y * 1.4 then
				slot.box2d.Position = Vector2.new(sMinX - 2, sMinY - 2)
				slot.box2d.Size = Vector2.new(bw + 4, bh + 4)
				slot.box2d.Visible = true
			else
				slot.box2d.Visible = false
			end

			if hasCen then
				slot.dot.Position = cenPt
				slot.dot.Visible = true
			else
				slot.dot.Visible = false
			end

			local dist = refPos and math.floor((refPos - centerPos).Magnitude + 0.5) or 0
			local lbl = customLabel or string.format("%s [%s] (%dm)", tostring(t.name), tostring(t.className), dist)
			local tw = math.max(64, #lbl * 6.8 + 14)
			local th = 18
			local anchorX = hasCen and ((sMinX + sMaxX) * 0.5) or (sMinX + bw * 0.5)
			local anchorY = (visCorners > 0) and (sMinY - th - 4) or (hasCen and (cenPt.Y - th - 6) or 20)
			local txPos = math.clamp(anchorX - tw * 0.5, 4, math.max(4, curVP.X - tw - 4))
			local tyPos = math.clamp(anchorY, 4, math.max(4, curVP.Y - th - 4))

			slot.tagBg.Position = Vector2.new(txPos, tyPos)
			slot.tagBg.Size = Vector2.new(tw, th)
			slot.tagBg.Visible = true
			slot.tagBd.Position = Vector2.new(txPos, tyPos)
			slot.tagBd.Size = Vector2.new(tw, th)
			slot.tagBd.Visible = true
			slot.tagTxt.Position = Vector2.new(txPos + tw * 0.5, tyPos + 2)
			slot.tagTxt.Text = lbl
			slot.tagTxt.Visible = true
			return true
		else
			hideEspSlot(slot)
			return false
		end
	end

	local function renderSelectionEsp(curVP)
		if not WorldToScreen then
			for i = 1, MAX_ESP_SLOTS do hideEspSlot(ESP.slots[i]) end
			hideEspSlot(ESP.hover)
			return
		end

		local refPos = nil
		local hrp = F.getLocalRoot()
		if hrp then
			local okR, rp = pcall(function() return hrp.Position end)
			if okR and rp then refPos = rp end
		end
		if not refPos and S.Workspace then
			local okCam, cp = pcall(function()
				local cam = S.Workspace.CurrentCamera
				return cam and cam.Position or nil
			end)
			if okCam and cp then refPos = cp end
		end

		local usedSlots = 0
		if S.selectionEsp and S.espTargets then
			for _, t in ipairs(S.espTargets) do
				if usedSlots >= MAX_ESP_SLOTS then break end
				if drawEspTargetOnSlot(ESP.slots[usedSlots + 1], t, refPos, curVP, nil) then
					usedSlots = usedSlots + 1
				end
			end
		end
		for i = usedSlots + 1, MAX_ESP_SLOTS do
			hideEspSlot(ESP.slots[i])
		end

		if (S.clickSelectMode or F.isAltDown()) and S.hoverPickTarget then
			drawEspTargetOnSlot(ESP.hover, S.hoverPickTarget, refPos, curVP, S.hoverPickTarget.hoverLabel)
		else
			hideEspSlot(ESP.hover)
		end
	end

	function F.startRenderer()
		local reportedErr = false
		S.renderFrames = 0
		local function stepFrame()
			if not S.alive then return end
			S.renderFrames = S.renderFrames + 1
			local curVP = F.getViewport()
			local active = (not isrbxactive) or isrbxactive()
			local mPos = F.getMousePos()
			local inVP = active and mPos.X >= 0 and mPos.X <= curVP.X and mPos.Y >= 0 and mPos.Y <= curVP.Y
			local m1 = inVP and ((ismouse1pressed and ismouse1pressed()) or false)
			local m2 = inVP and ((ismouse2pressed and ismouse2pressed()) or false)
			local clicked1 = m1 and not drag.prevM1
			local released1 = (not m1) and drag.prevM1
			local clicked2 = m2 and not drag.prevM2
			local released2 = (not m2) and drag.prevM2
			drag.prevM1 = m1
			drag.prevM2 = m2

			renderSelectionEsp(curVP)

			if UI.uiHidden then
				hideGroup(TM); hideGroup(WL); hideGroup(EX); hideGroup(PR)
				hideGroup(SP); hideGroup(CT); hideGroup(ST); hideGroup(RN); hideGroup(SV)
				return
			end

			if UI.welcome.visible and UI.welcome.autoCloseAt and F.now() >= UI.welcome.autoCloseAt then
				UI.welcome.visible = false
				UI.welcome.autoCloseAt = nil
			end

			-- Handle ongoing drags
			if drag.mode == "exp" and m1 then
				if UI.expWin.docked then
					if math.abs(mPos.X - drag.startM.X) > 14 or math.abs(mPos.Y - drag.startM.Y) > 14 then
						UI.expWin.docked = false
						UI.expWin.w = UI.expWin.floatW
						UI.expWin.h = UI.expWin.floatH
						UI.expWin.x = math.clamp(mPos.X - UI.expWin.w * 0.5, 4, curVP.X - UI.expWin.w - 4)
						UI.expWin.y = math.clamp(mPos.Y - 12, 4, curVP.Y - 60)
						drag.off = mPos - Vector2.new(UI.expWin.x, UI.expWin.y)
					end
				else
					UI.expWin.x = math.clamp(mPos.X - drag.off.X, 0, curVP.X - UI.expWin.w)
					UI.expWin.y = math.clamp(mPos.Y - drag.off.Y, 0, curVP.Y - 40)
				end
			elseif drag.mode == "prop" and m1 then
				if UI.propWin.docked then
					if math.abs(mPos.X - drag.startM.X) > 14 or math.abs(mPos.Y - drag.startM.Y) > 14 then
						UI.propWin.docked = false
						UI.propWin.w = UI.propWin.floatW
						UI.propWin.h = UI.propWin.floatH
						UI.propWin.x = math.clamp(mPos.X - UI.propWin.w * 0.5, 4, curVP.X - UI.propWin.w - 4)
						UI.propWin.y = math.clamp(mPos.Y - 12, 4, curVP.Y - 60)
						drag.off = mPos - Vector2.new(UI.propWin.x, UI.propWin.y)
					end
				else
					UI.propWin.x = math.clamp(mPos.X - drag.off.X, 0, curVP.X - UI.propWin.w)
					UI.propWin.y = math.clamp(mPos.Y - drag.off.Y, 0, curVP.Y - 40)
				end
			elseif drag.mode == "split" and m1 then
				UI.splitRatio = math.clamp(mPos.Y / curVP.Y, 0.2, 0.8)
			elseif drag.mode == "edge" and m1 then
				local w = (UI.paneSide == "Right") and (curVP.X - mPos.X) or mPos.X
				UI.rightPaneWidth = math.clamp(w, 240, 520)
			elseif drag.mode == "viewer" and m1 then
				S.viewer.x = math.clamp(mPos.X - drag.off.X, 0, curVP.X - S.viewer.w)
				S.viewer.y = math.clamp(mPos.Y - drag.off.Y, 0, curVP.Y - 40)
			elseif drag.mode == "settings" and m1 then
				UI.settingsWin.x = math.clamp(mPos.X - drag.off.X, 0, curVP.X - UI.settingsWin.w)
				UI.settingsWin.y = math.clamp(mPos.Y - drag.off.Y, 0, curVP.Y - 40)
			end

			-- Dock snap on release
			if released1 then
				if (drag.mode == "exp" or drag.mode == "prop") then
					local win = (drag.mode == "exp") and UI.expWin or UI.propWin
					if not win.docked then
						if mPos.X >= curVP.X - 55 then
							UI.paneSide = "Right"; win.docked = true
						elseif mPos.X <= 55 then
							UI.paneSide = "Left"; win.docked = true
						end
					end
				end
				drag.mode = nil
			end

			layoutDockedPanes(curVP)

			-- Dock preview frame
			if (drag.mode == "exp" or drag.mode == "prop") and ((drag.mode == "exp" and not UI.expWin.docked) or (drag.mode == "prop" and not UI.propWin.docked)) then
				if mPos.X >= curVP.X - 55 then
					SP.dockPrev.Position = Vector2.new(curVP.X - UI.rightPaneWidth, 0)
					SP.dockPrev.Size = Vector2.new(UI.rightPaneWidth, curVP.Y)
					SP.dockPrev.Visible = true
				elseif mPos.X <= 55 then
					SP.dockPrev.Position = Vector2.new(0, 0)
					SP.dockPrev.Size = Vector2.new(UI.rightPaneWidth, curVP.Y)
					SP.dockPrev.Visible = true
				else
					SP.dockPrev.Visible = false
				end
			else
				SP.dockPrev.Visible = false
			end

			-- Click consumption flag (top-most modal wins!)
			local consumed = false

			-- ---------------------------------------------------------
			-- 1. Rename Modal (highest Z)
			-- ---------------------------------------------------------
			if UI.renameModal.visible then
				local rw, rh = 280, 96
				local rx, ry = math.floor(curVP.X * 0.5 - rw * 0.5), math.floor(curVP.Y * 0.5 - rh * 0.5)
				RN.bg.Position = Vector2.new(rx, ry); RN.bg.Size = Vector2.new(rw, rh); RN.bg.Visible = true
				RN.bd.Position = Vector2.new(rx, ry); RN.bd.Size = Vector2.new(rw, rh); RN.bd.Visible = true
				RN.title.Position = Vector2.new(rx + 10, ry + 8); RN.title.Text = "Rename Instance"; RN.title.Visible = true
				RN.box.Position = Vector2.new(rx + 10, ry + 32); RN.box.Size = Vector2.new(rw - 20, 22); RN.box.Visible = true
				RN.boxBd.Position = Vector2.new(rx + 10, ry + 32); RN.boxBd.Size = Vector2.new(rw - 20, 22); RN.boxBd.Visible = true
				local caret = (math.floor(F.now() * 2) % 2 == 0) and "|" or ""
				RN.input.Position = Vector2.new(rx + 14, ry + 36); RN.input.Text = F.fitText(UI.renameModal.text .. caret, rw - 28, 6.6); RN.input.Visible = true
				RN.okBg.Position = Vector2.new(rx + rw - 134, ry + 64); RN.okBg.Size = Vector2.new(58, 22); RN.okBg.Visible = true
				RN.okTx.Position = Vector2.new(rx + rw - 105, ry + 68); RN.okTx.Text = "OK"; RN.okTx.Visible = true
				RN.caBg.Position = Vector2.new(rx + rw - 68, ry + 64); RN.caBg.Size = Vector2.new(58, 22); RN.caBg.Visible = true
				RN.caTx.Position = Vector2.new(rx + rw - 39, ry + 68); RN.caTx.Text = "Cancel"; RN.caTx.Visible = true

				if clicked1 then
					consumed = true
					if F.pointInRect(mPos, rx + rw - 134, ry + 64, 58, 22) then
						local nd = UI.renameModal.node
						if nd and nd.obj and UI.renameModal.text ~= "" then
							pcall(function() nd.obj.Name = UI.renameModal.text end)
							nd.name = UI.renameModal.text
							F.rebuildTreeList()
							F.rebuildPropTree()
						end
						UI.renameModal.visible = false
						UI.focusTarget = nil
					elseif F.pointInRect(mPos, rx + rw - 68, ry + 64, 58, 22) or not F.pointInRect(mPos, rx, ry, rw, rh) then
						UI.renameModal.visible = false
						UI.focusTarget = nil
					end
				end
			else
				hideGroup(RN)
			end

			-- ---------------------------------------------------------
			-- 2. Context Menu
			-- ---------------------------------------------------------
			if UI.ctx.visible then
				local cx, cy, cw = UI.ctx.x, UI.ctx.y, UI.ctx.w
				local curY = 2
				local totalH = 4
				for _, it in ipairs(UI.ctx.items) do
					totalH = totalH + (it.divider and 10 or 20)
				end
				if cx + cw > curVP.X then cx = curVP.X - cw - 4 end
				if cy + totalH > curVP.Y then cy = math.max(4, curVP.Y - totalH - 4) end

				CT.bg.Position = Vector2.new(cx, cy); CT.bg.Size = Vector2.new(cw, totalH); CT.bg.Visible = true
				CT.bd.Position = Vector2.new(cx, cy); CT.bd.Size = Vector2.new(cw, totalH); CT.bd.Visible = true

				local ry = cy + 2
				for i = 1, MAX_CTX_ROWS do
					local row = CT.rows[i]
					local it = UI.ctx.items[i]
					if it then
						if it.divider then
							row.bg.Visible = false; row.icon.Visible = false; row.name.Visible = false; row.short.Visible = false
							row.div.From = Vector2.new(cx + 4, ry + 5); row.div.To = Vector2.new(cx + cw - 4, ry + 5); row.div.Visible = true
							ry = ry + 10
						else
							row.div.Visible = false
							local hov = (not consumed) and (not it.disabled) and F.pointInRect(mPos, cx, ry, cw, 20)
							row.bg.Position = Vector2.new(cx + 1, ry); row.bg.Size = Vector2.new(cw - 2, 20)
							row.bg.Color = hov and C_SEL or C_CTX_BG; row.bg.Visible = true
							row.icon.Position = Vector2.new(cx + 5, ry + 4); row.icon.Size = Vector2.new(12, 12)
							row.icon.Color = it.disabled and C_TXT_DIM or (it.color or C_BLUE); row.icon.Visible = true
							row.name.Position = Vector2.new(cx + 22, ry + 3); row.name.Text = it.name
							row.name.Color = it.disabled and C_TXT_RO or C_TXT; row.name.Visible = true
							if it.shortcut and it.shortcut ~= "" then
								row.short.Position = Vector2.new(cx + cw - 52, ry + 3); row.short.Text = it.shortcut
								row.short.Color = it.disabled and C_TXT_DIM or C_TXT_RO; row.short.Visible = true
							else
								row.short.Visible = false
							end
							if clicked1 and hov and it.cb then
								consumed = true
								UI.ctx.visible = false
								it.cb()
							end
							ry = ry + 20
						end
					else
						row.bg.Visible = false; row.icon.Visible = false; row.name.Visible = false; row.short.Visible = false; row.div.Visible = false
					end
				end

				if clicked1 and not consumed then
					if not F.pointInRect(mPos, cx, cy, cw, totalH) then
						UI.ctx.visible = false
					else
						consumed = true
					end
				end
			else
				hideGroup(CT)
			end

			-- ---------------------------------------------------------
			-- 3. TopMenu + Window Views Dropdown
			-- ---------------------------------------------------------
			local tmw, tmh = 260, 34
			local tmx = math.floor(curVP.X * 0.5 - tmw * 0.5)
			local tmy = 0
			TM.bg.Position = Vector2.new(tmx, tmy); TM.bg.Size = Vector2.new(tmw, tmh); TM.bg.Visible = true
			TM.wingL.PointA = Vector2.new(tmx - 18, tmy); TM.wingL.PointB = Vector2.new(tmx, tmy); TM.wingL.PointC = Vector2.new(tmx, tmy + tmh); TM.wingL.Visible = true
			TM.wingR.PointA = Vector2.new(tmx + tmw, tmy); TM.wingR.PointB = Vector2.new(tmx + tmw + 18, tmy); TM.wingR.PointC = Vector2.new(tmx + tmw, tmy + tmh); TM.wingR.Visible = true
			TM.title.Position = Vector2.new(tmx + 6, 2); TM.title.Text = "DEX"; TM.title.Visible = true
			TM.ver.Position = Vector2.new(tmx + 6, 17); TM.ver.Text = "1.1.0"; TM.ver.Visible = true

			local sbx, sby, sbw, sbh = tmx + 50, 4, 152, 26
			TM.slideBg.Position = Vector2.new(sbx, sby); TM.slideBg.Size = Vector2.new(sbw, sbh); TM.slideBg.Visible = true
			TM.slideBd.Position = Vector2.new(sbx, sby); TM.slideBd.Size = Vector2.new(sbw, sbh); TM.slideBd.Visible = true
			TM.slideTxt.Position = Vector2.new(sbx + 10, sby + 6); TM.slideTxt.Text = "Window Views"; TM.slideTxt.Visible = true
			TM.slideArrowBg.Position = Vector2.new(sbx + sbw - 18, sby + 1); TM.slideArrowBg.Size = Vector2.new(17, sbh - 2); TM.slideArrowBg.Visible = true
			setTriDir(TM.slideArrow, sbx + sbw - 17, sby + 5, 16, 16, UI.viewsOpen and "up" or "down", C_TXT)

			local abx, aby, abw, abh = tmx + tmw - 42, 4, 32, 26
			local hovAb = (not consumed) and F.pointInRect(mPos, abx, aby, abw, abh)
			TM.aboutBg.Position = Vector2.new(abx, aby); TM.aboutBg.Size = Vector2.new(abw, abh)
			TM.aboutBg.Color = hovAb and C_HOV or C_DARK; TM.aboutBg.Visible = true
			TM.aboutTxt.Position = Vector2.new(abx + 16, aby + 6); TM.aboutTxt.Text = "?"; TM.aboutTxt.Visible = true

			if clicked1 and not consumed then
				if F.pointInRect(mPos, sbx, sby, sbw, sbh) then
					UI.viewsOpen = not UI.viewsOpen
					consumed = true
				elseif hovAb then
					UI.welcome.visible = not UI.welcome.visible
					UI.welcome.autoCloseAt = nil
					UI.viewsOpen = false
					consumed = true
				end
			end

			if UI.viewsOpen then
				local vItems = getViewDropdownItems()
				local dx, dy, dw, dh = sbx, sby + sbh + 1, 174, #vItems * 22 + 4
				TM.dropBg.Position = Vector2.new(dx, dy); TM.dropBg.Size = Vector2.new(dw, dh); TM.dropBg.Visible = true
				TM.dropBd.Position = Vector2.new(dx, dy); TM.dropBd.Size = Vector2.new(dw, dh); TM.dropBd.Visible = true
				for i = 1, MAX_VIEW_MENU do
					local r = TM.dropRows[i]
					local it = vItems[i]
					if it then
						local ry = dy + 2 + (i - 1) * 22
						local hov = (not consumed) and F.pointInRect(mPos, dx, ry, dw, 22)
						r.bg.Position = Vector2.new(dx + 1, ry); r.bg.Size = Vector2.new(dw - 2, 22)
						r.bg.Color = hov and C_SEL or C_DARK; r.bg.Visible = true
						r.txt.Position = Vector2.new(dx + 8, ry + 4); r.txt.Text = it.label; r.txt.Visible = true
						if clicked1 and hov then
							consumed = true
							it.cb()
						end
					else
						r.bg.Visible = false; r.txt.Visible = false
					end
				end
				if clicked1 and not consumed then
					if not F.pointInRect(mPos, dx, dy, dw, dh) then
						UI.viewsOpen = false
					else
						consumed = true
					end
				end
			else
				TM.dropBg.Visible = false; TM.dropBd.Visible = false
				for i = 1, MAX_VIEW_MENU do
					TM.dropRows[i].bg.Visible = false; TM.dropRows[i].txt.Visible = false
				end
			end

			-- ---------------------------------------------------------
			-- 4. WelcomeFrame (About Splash)
			-- ---------------------------------------------------------
			if UI.welcome.visible then
				local ww, wh = 500, 300
				local wx, wy = math.floor(curVP.X * 0.5 - ww * 0.5), math.floor(curVP.Y * 0.5 - wh * 0.5)
				local mw = math.floor(ww * 0.6)
				WL.outerBd.Position = Vector2.new(wx - 4, wy - 4); WL.outerBd.Size = Vector2.new(ww + 8, wh + 8); WL.outerBd.Visible = true
				WL.mainBg.Position = Vector2.new(wx, wy); WL.mainBg.Size = Vector2.new(mw, wh); WL.mainBg.Visible = true
				WL.rightBg.Position = Vector2.new(wx + mw, wy); WL.rightBg.Size = Vector2.new(ww - mw, wh); WL.rightBg.Visible = true

				local hovClose = (not consumed) and F.pointInRect(mPos, wx, wy, 24, 24)
				WL.closeBg.Position = Vector2.new(wx, wy); WL.closeBg.Size = Vector2.new(24, 24)
				WL.closeBg.Color = hovClose and C_HOV or C_TOPBAR; WL.closeBg.Visible = true
				WL.closeTxt.Position = Vector2.new(wx + 12, wy + 4); WL.closeTxt.Text = "X"; WL.closeTxt.Visible = true

				WL.title.Position = Vector2.new(wx + 24, wy + 26); WL.title.Text = "DEX"; WL.title.Visible = true
				WL.ver.Position = Vector2.new(wx + 125, wy + 48); WL.ver.Text = "V1.1.0 ALPHA"; WL.ver.Visible = true
				WL.progLine.Position = Vector2.new(wx + 48, wy + 120); WL.progLine.Size = Vector2.new(2, 80); WL.progLine.Visible = true

				local progLabels = {
					"Fetching latest API...",
					"Fetching latest Reflection Metadata...",
					"Preparing Matcha bindings...",
					"Indexing tree list...",
					"Starting up...",
				}
				for i = 1, 5 do
					WL.prog[i].Position = Vector2.new(wx + 58, wy + 120 + (i - 1) * 16)
					WL.prog[i].Text = progLabels[i]
					WL.prog[i].Color = (UI.welcome.step >= i) and C_WHITE or C_TXT_DIM
					WL.prog[i].Visible = true
				end
				WL.credit.Position = Vector2.new(wx + 8, wy + wh - 24); WL.credit.Text = "Made by Moon & Courtney (Matcha Port)"; WL.credit.Visible = true

				WL.chgBg.Position = Vector2.new(wx + mw + 6, wy + 22); WL.chgBg.Size = Vector2.new(ww - mw - 12, wh - 78); WL.chgBg.Visible = true
				WL.chgBd.Position = Vector2.new(wx + mw + 6, wy + 22); WL.chgBd.Size = Vector2.new(ww - mw - 12, wh - 78); WL.chgBd.Visible = true
				WL.chgTitle.Position = Vector2.new(wx + mw + (ww - mw) * 0.5, wy + 4); WL.chgTitle.Text = "Changelog"; WL.chgTitle.Visible = true
				local chgNotes = {
					"- Matcha Drawing UI port",
					"- Live Explorer & Search",
					"  (class:, isa:, regex:, |)",
					"- Supported Properties",
					"  + Live Attribute Editor",
					"- Script Decompiler Viewer",
					"- Cut / Paste / Delete",
					"- Skipped: Clone / Create",
					"  (unsupported in Matcha)",
				}
				for i = 1, 9 do
					WL.chgLines[i].Position = Vector2.new(wx + mw + 12, wy + 30 + (i - 1) * 20)
					WL.chgLines[i].Text = chgNotes[i]; WL.chgLines[i].Visible = true
				end

				WL.botBg.Position = Vector2.new(wx + mw, wy + wh - 50); WL.botBg.Size = Vector2.new(ww - mw, 50); WL.botBg.Visible = true
				WL.logoOut.Position = Vector2.new(wx + mw + 8, wy + wh - 42); WL.logoOut.Size = Vector2.new(34, 34); WL.logoOut.Visible = true
				WL.logoIn.Position = Vector2.new(wx + mw + 25, wy + wh - 33); WL.logoIn.Text = "DX"; WL.logoIn.Visible = true
				WL.desc.Position = Vector2.new(wx + mw + 48, wy + wh - 42); WL.desc.Text = "Powerful and light"; WL.desc.Visible = true
				WL.subCred.Position = Vector2.new(wx + mw + 48, wy + wh - 22); WL.subCred.Text = "Matcha Edition"; WL.subCred.Visible = true

				if clicked1 and not consumed then
					if hovClose then
						UI.welcome.visible = false
						UI.welcome.autoCloseAt = nil
						consumed = true
					elseif F.pointInRect(mPos, wx, wy, ww, wh) then
						consumed = true
					end
				end
			else
				hideGroup(WL)
			end

			-- ---------------------------------------------------------
			-- 5. Settings Popup
			-- ---------------------------------------------------------
			if UI.settingsWin.visible then
				local sw, sh = UI.settingsWin.w, UI.settingsWin.h
				local sx, sy = UI.settingsWin.x, UI.settingsWin.y
				ST.bg.Position = Vector2.new(sx, sy); ST.bg.Size = Vector2.new(sw, sh); ST.bg.Visible = true
				ST.bd.Position = Vector2.new(sx, sy); ST.bd.Size = Vector2.new(sw, sh); ST.bd.Visible = true
				ST.bar.Position = Vector2.new(sx, sy); ST.bar.Size = Vector2.new(sw, 24); ST.bar.Visible = true
				ST.title.Position = Vector2.new(sx + 8, sy + 5); ST.title.Text = "Dex Settings"; ST.title.Visible = true
				ST.close.Position = Vector2.new(sx + sw - 12, sy + 5); ST.close.Text = "X"; ST.close.Visible = true

				local sItems = getSettingsItems()
				for i = 1, 8 do
					local r = ST.rows[i]
					local it = sItems[i]
					if it then
						local ry = sy + 28 + (i - 1) * 24
						local hov = (not consumed) and F.pointInRect(mPos, sx + 4, ry, sw - 8, 22)
						r.bg.Position = Vector2.new(sx + 4, ry); r.bg.Size = Vector2.new(sw - 8, 22)
						r.bg.Color = hov and C_SEL or C_BG; r.bg.Visible = true
						r.txt.Position = Vector2.new(sx + 10, ry + 4); r.txt.Text = it.label; r.txt.Visible = true
						if clicked1 and hov then
							consumed = true
							it.cb()
						end
					else
						r.bg.Visible = false; r.txt.Visible = false
					end
				end

				if clicked1 and not consumed and F.pointInRect(mPos, sx, sy, sw, sh) then
					consumed = true
					if F.pointInRect(mPos, sx + sw - 24, sy, 24, 24) then
						UI.settingsWin.visible = false
					elseif F.pointInRect(mPos, sx, sy, sw - 24, 24) then
						drag.mode = "settings"; drag.off = mPos - Vector2.new(sx, sy)
					end
				end
			else
				hideGroup(ST)
			end

			-- ---------------------------------------------------------
			-- 6. Script Viewer Window
			-- ---------------------------------------------------------
			if S.viewer.visible then
				local vx, vy, vw, vh = S.viewer.x, S.viewer.y, S.viewer.w, S.viewer.h
				SV.bg.Position = Vector2.new(vx, vy); SV.bg.Size = Vector2.new(vw, vh); SV.bg.Visible = true
				SV.bd.Position = Vector2.new(vx, vy); SV.bd.Size = Vector2.new(vw, vh); SV.bd.Visible = true
				SV.bar.Position = Vector2.new(vx, vy); SV.bar.Size = Vector2.new(vw, 26); SV.bar.Visible = true
				SV.title.Position = Vector2.new(vx + 8, vy + 6); SV.title.Text = F.fitText(S.viewer.title, vw - 180, 6.6); SV.title.Visible = true

				SV.copyBg.Position = Vector2.new(vx + vw - 134, vy + 3); SV.copyBg.Size = Vector2.new(48, 20); SV.copyBg.Visible = true
				SV.copyTx.Position = Vector2.new(vx + vw - 110, vy + 6); SV.copyTx.Text = "Copy"; SV.copyTx.Visible = true
				SV.upBg.Position = Vector2.new(vx + vw - 80, vy + 3); SV.upBg.Size = Vector2.new(24, 20); SV.upBg.Visible = true
				SV.upTx.Position = Vector2.new(vx + vw - 68, vy + 6); SV.upTx.Text = "^"; SV.upTx.Visible = true
				SV.dnBg.Position = Vector2.new(vx + vw - 52, vy + 3); SV.dnBg.Size = Vector2.new(24, 20); SV.dnBg.Visible = true
				SV.dnTx.Position = Vector2.new(vx + vw - 40, vy + 6); SV.dnTx.Text = "v"; SV.dnTx.Visible = true
				SV.closeBg.Position = Vector2.new(vx + vw - 24, vy + 2); SV.closeBg.Size = Vector2.new(22, 22); SV.closeBg.Visible = true
				SV.closeTx.Position = Vector2.new(vx + vw - 13, vy + 6); SV.closeTx.Text = "X"; SV.closeTx.Visible = true

				SV.codeBg.Position = Vector2.new(vx + 2, vy + 28); SV.codeBg.Size = Vector2.new(vw - 4, vh - 30); SV.codeBg.Visible = true

				local visLines = math.min(MAX_VIEW_ROWS, math.floor((vh - 34) / 15))
				local maxScr = math.max(0, #S.viewer.lines - visLines)
				S.viewer.scroll = math.clamp(S.viewer.scroll, 0, maxScr)

				for i = 1, MAX_VIEW_ROWS do
					local lr = SV.lines[i]
					local lineIdx = i + S.viewer.scroll
					local lineText = (i <= visLines) and S.viewer.lines[lineIdx] or nil
					if lineText ~= nil then
						local ly = vy + 32 + (i - 1) * 15
						lr.num.Position = Vector2.new(vx + 6, ly); lr.num.Text = string.format("%3d", lineIdx); lr.num.Visible = true
						lr.txt.Position = Vector2.new(vx + 38, ly); lr.txt.Text = F.fitText(lineText, vw - 46, 7.2); lr.txt.Visible = true
					else
						lr.num.Visible = false; lr.txt.Visible = false
					end
				end

				if clicked1 and not consumed and F.pointInRect(mPos, vx, vy, vw, vh) then
					consumed = true
					if F.pointInRect(mPos, vx + vw - 24, vy + 2, 22, 22) then
						S.viewer.visible = false
					elseif F.pointInRect(mPos, vx + vw - 134, vy + 3, 48, 20) then
						F.copyToClipboard(S.viewer.raw); F.notify("Script Viewer", "Source copied")
					elseif F.pointInRect(mPos, vx + vw - 80, vy + 3, 24, 20) then
						S.viewer.scroll = math.max(0, S.viewer.scroll - 5)
					elseif F.pointInRect(mPos, vx + vw - 52, vy + 3, 24, 20) then
						S.viewer.scroll = math.min(maxScr, S.viewer.scroll + 5)
					elseif F.pointInRect(mPos, vx, vy, vw - 140, 26) then
						drag.mode = "viewer"; drag.off = mPos - Vector2.new(vx, vy)
					end
				end
			else
				hideGroup(SV)
			end

			-- ---------------------------------------------------------
			-- 7. Splitter & Pane Resize Edge
			-- ---------------------------------------------------------
			local bothDocked = UI.expWin.visible and UI.expWin.docked and UI.propWin.visible and UI.propWin.docked
			if bothDocked then
				local sy = UI.expWin.y + UI.expWin.h - 2
				local sx = UI.expWin.x
				local sw = UI.expWin.w
				local hovSplit = (not consumed) and F.pointInRect(mPos, sx, sy - 3, sw, 8)
				SP.splitter.Position = Vector2.new(sx, sy); SP.splitter.Size = Vector2.new(sw, 4)
				SP.splitter.Color = (hovSplit or drag.mode == "split") and C_BLUE or C_BORDER; SP.splitter.Visible = true
				if clicked1 and hovSplit then
					drag.mode = "split"; consumed = true
				end
			else
				SP.splitter.Visible = false
			end

			if (UI.expWin.visible and UI.expWin.docked) or (UI.propWin.visible and UI.propWin.docked) then
				local ex = (UI.paneSide == "Right") and (curVP.X - UI.rightPaneWidth) or (UI.rightPaneWidth - 3)
				local hovEdge = (not consumed) and F.pointInRect(mPos, ex - 3, 0, 7, curVP.Y)
				SP.edgeGrip.Position = Vector2.new(ex, 0); SP.edgeGrip.Size = Vector2.new(3, curVP.Y)
				SP.edgeGrip.Color = (hovEdge or drag.mode == "edge") and C_BLUE or C_BORDER; SP.edgeGrip.Visible = true
				if clicked1 and hovEdge then
					drag.mode = "edge"; consumed = true
				end
			else
				SP.edgeGrip.Visible = false
			end

			-- ---------------------------------------------------------
			-- 8. ExplorerPanel Render + Interaction
			-- ---------------------------------------------------------
			if UI.expWin.visible then
				local x, y, w, h = UI.expWin.x, UI.expWin.y, UI.expWin.w, UI.expWin.h
				local topH = 50
				local listX, listY = x + 1, y + topH
				local needH = (S.nodeMaxWidth > (w - 20))
				local listW = w - 18
				local listH = h - topH - (needH and 17 or 1)
				local visRows = math.min(MAX_EXP_ROWS, math.max(1, math.floor(listH / 19)))

				if UI.expScrollTargetIdx ~= nil then
					UI.expScroll = UI.expScrollTargetIdx
					UI.expScrollTargetIdx = nil
				end
				UI.expScroll = math.clamp(UI.expScroll, 0, math.max(0, #S.treeList - visRows))

				EX.bg.Position = Vector2.new(x, y); EX.bg.Size = Vector2.new(w, h); EX.bg.Visible = true
				EX.bd.Position = Vector2.new(x, y); EX.bd.Size = Vector2.new(w, h); EX.bd.Visible = true
				EX.topBar.Position = Vector2.new(x + 1, y + 1); EX.topBar.Size = Vector2.new(w - 2, topH - 1); EX.topBar.Visible = true
				EX.title.Position = Vector2.new(x + w * 0.5, y + 4); EX.title.Text = "Explorer"; EX.title.Visible = true

				local hovPick = (not consumed) and F.pointInRect(mPos, x + 4, y + 2, 48, 21)
				EX.pickBg.Position = Vector2.new(x + 4, y + 2); EX.pickBg.Size = Vector2.new(48, 21)
				EX.pickBg.Color = S.clickSelectMode and C_BLUE or (hovPick and C_HOV or C_BG); EX.pickBg.Visible = true
				EX.pickBd.Position = Vector2.new(x + 4, y + 2); EX.pickBd.Size = Vector2.new(48, 21)
				EX.pickBd.Color = S.clickSelectMode and C_WHITE or C_CTX_BD; EX.pickBd.Visible = true
				EX.pickTxt.Position = Vector2.new(x + 28, y + 5)
				EX.pickTxt.Text = S.clickSelectMode and "Pick*" or "Pick"
				EX.pickTxt.Color = C_WHITE; EX.pickTxt.Visible = true

				local hovX = (not consumed) and F.pointInRect(mPos, x + w - 26, y + 1, 24, 24)
				EX.closeBg.Position = Vector2.new(x + w - 26, y + 1); EX.closeBg.Size = Vector2.new(24, 24)
				EX.closeBg.Color = hovX and C_HOV or C_TOPBAR; EX.closeBg.Visible = true
				EX.closeTxt.Position = Vector2.new(x + w - 14, y + 5); EX.closeTxt.Text = "X"; EX.closeTxt.Visible = true

				local hovSet = (not consumed) and F.pointInRect(mPos, x + w - 26, y + 25, 24, 24)
				EX.setBg.Position = Vector2.new(x + w - 26, y + 25); EX.setBg.Size = Vector2.new(24, 24)
				EX.setBg.Color = hovSet and C_HOV or C_TOPBAR; EX.setBg.Visible = true
				EX.setTxt.Position = Vector2.new(x + w - 14, y + 29); EX.setTxt.Text = "*"; EX.setTxt.Visible = true

				-- Search Box
				EX.sUnder.Position = Vector2.new(x + 4, y + 45); EX.sUnder.Size = Vector2.new(w - 31, 2); EX.sUnder.Visible = true
				local expFocus = (UI.focusTarget == "expSearch")
				EX.sActive.Position = Vector2.new(x + 4, y + 45); EX.sActive.Size = Vector2.new(expFocus and (w - 31) or 0, 2)
				EX.sActive.Visible = expFocus
				EX.sTxt.Position = Vector2.new(x + 6, y + 27)
				if expFocus or UI.expSearch.text ~= "" then
					local caret = expFocus and (math.floor(F.now() * 2) % 2 == 0 and "|" or "") or ""
					EX.sTxt.Text = F.fitText(UI.expSearch.text .. caret, w - 38, 6.6)
					EX.sTxt.Color = C_TXT
				else
					EX.sTxt.Text = "Search Workspace"
					EX.sTxt.Color = C_TXT_DIM
				end
				EX.sTxt.Visible = true

				-- TopBar click handling
				if clicked1 and not consumed and F.pointInRect(mPos, x, y, w, topH) then
					consumed = true
					bringWinFront("exp")
					if hovPick then
						S.clickSelectMode = not S.clickSelectMode
						if S.clickSelectMode then
							F.refreshPickableParts()
							F.notify("Dex Pick", "Click a 3D part (Shift+Click for Model)", 3)
						else
							S.hoverPickTarget = nil
							F.notify("Dex Pick", "Click-to-Select disabled", 2)
						end
					elseif hovX then
						UI.expWin.visible = false
					elseif hovSet then
						UI.settingsWin.visible = not UI.settingsWin.visible
						UI.settingsWin.x = math.max(8, x - UI.settingsWin.w - 6)
						UI.settingsWin.y = y + 26
					elseif F.pointInRect(mPos, x + 4, y + 25, w - 31, 22) then
						UI.focusTarget = "expSearch"
					else
						UI.focusTarget = nil
						drag.mode = "exp"
						drag.startM = mPos
						drag.off = mPos - Vector2.new(x, y)
					end
				end

				-- Scrollbars
				local vScrollX = x + w - 17
				local vScrollH = h - topH - (needH and 17 or 1)
				UI.expScroll = drawScrollbar(
					{ trk = EX.vTrk, thm = EX.vThm, b1 = EX.vUpBg, t1 = EX.vUpTri, b2 = EX.vDnBg, t2 = EX.vDnTri },
					vScrollX, listY, 16, vScrollH, #S.treeList + 1, visRows, UI.expScroll, false, mPos, m1, clicked1 and not consumed, scrExpV
				)
				if clicked1 and not consumed and F.pointInRect(mPos, vScrollX, listY, 16, vScrollH) then
					consumed = true
				end

				if needH then
					UI.expScrollH = drawScrollbar(
						{ trk = EX.hTrk, thm = EX.hThm, b1 = EX.hLtBg, t1 = EX.hLtTri, b2 = EX.hRtBg, t2 = EX.hRtTri },
						x + 1, y + h - 17, w - 18, 16, S.nodeMaxWidth, listW, UI.expScrollH, true, mPos, m1, clicked1 and not consumed, scrExpH
					)
					if clicked1 and not consumed and F.pointInRect(mPos, x + 1, y + h - 17, w - 18, 16) then
						consumed = true
					end
				else
					UI.expScrollH = 0
					EX.hTrk.Visible = false; EX.hThm.Visible = false; EX.hLtBg.Visible = false; EX.hLtTri.Visible = false; EX.hRtBg.Visible = false; EX.hRtTri.Visible = false
				end

				-- Cut map for tinting
				local cutMap = {}
				for _, cn in ipairs(S.clipboardCut) do cutMap[cn.addr] = true end

				-- Render Explorer Rows
				for i = 1, MAX_EXP_ROWS do
					local r = EX.rows[i]
					local node = (i <= visRows) and S.treeList[i + UI.expScroll] or nil
					if node then
						local ry = listY + 2 + (i - 1) * 19
						local isSel = S.selectionMap[node.addr] == true
						local rowHov = (not consumed) and F.pointInRect(mPos, listX, ry, listW, 18)

						if isSel or rowHov then
							r.bg.Position = Vector2.new(listX + 1, ry); r.bg.Size = Vector2.new(listW - 2, 18)
							r.bg.Color = isSel and C_SEL or C_HOV; r.bg.Visible = true
							r.bd.Position = Vector2.new(listX + 1, ry); r.bd.Size = Vector2.new(listW - 2, 18)
							r.bd.Visible = isSel
						else
							r.bg.Visible = false; r.bd.Visible = false
						end

						local indentX = listX + 4 + node.depth * 16 - UI.expScrollH
						local arrowX = indentX
						local iconX = indentX + 16
						local textX = indentX + 34

						local showArrow = node.hasChildren and (not S.searchResults or S.searchExpanded[node.addr] == 2 or node.hasChildren)
						if showArrow and arrowX >= listX and arrowX + 14 <= listX + listW then
							local isExp = (not S.searchResults and S.expanded[node.addr]) or (S.searchResults and S.searchExpanded[node.addr] == 2)
							local arrHov = F.pointInRect(mPos, arrowX, ry + 1, 16, 16)
							setTriDir(r.expTri, arrowX, ry + 1, 14, 16, isExp and "down" or "right", arrHov and C_WHITE or C_TXT)
						else
							r.expTri.Visible = false
						end

						if iconX >= listX and iconX + 14 <= listX + listW then
							local st = F.getIconStyle(node.className)
							r.iconBg.Position = Vector2.new(iconX, ry + 2); r.iconBg.Size = Vector2.new(13, 13)
							r.iconBg.Color = st.bg; r.iconBg.Visible = true
							r.iconTx.Position = Vector2.new(iconX + 6.5, ry + 2); r.iconTx.Text = st.g
							r.iconTx.Color = st.fg; r.iconTx.Visible = true
						else
							r.iconBg.Visible = false; r.iconTx.Visible = false
						end

						local availTxtW = (listX + listW) - textX - 2
						local showName = node.name
						local drawTextX = textX
						if drawTextX < listX + 2 then
							local skip = math.ceil((listX + 2 - drawTextX) / 6.6)
							showName = showName:sub(skip + 1)
							availTxtW = (listX + listW) - (listX + 2) - 2
							drawTextX = listX + 2
						end
						if availTxtW > 12 and #showName > 0 then
							r.label.Position = Vector2.new(drawTextX, ry + 2)
							r.label.Text = F.fitText(showName, availTxtW, 6.6)
							r.label.Color = cutMap[node.addr] and Color3.fromRGB(255, 195, 100) or (isSel and C_WHITE or C_TXT)
							r.label.Visible = true
						else
							r.label.Visible = false
						end

						if clicked1 and rowHov then
							consumed = true
							UI.focusTarget = nil
							bringWinFront("exp")
							if showArrow and F.pointInRect(mPos, arrowX - 2, ry, 18, 18) then
								F.toggleExpandNode(node)
							else
								local nowT = F.now()
								if drag.lastClickAddr == node.addr and (nowT - drag.lastClickTime) < 0.35 and node.hasChildren then
									F.toggleExpandNode(node)
									drag.lastClickTime = 0
								else
									if F.isShiftDown() and S.lastSelectedAddr then
										local idxA, idxB = nil, nil
										for ti, tn in ipairs(S.treeList) do
											if tn.addr == S.lastSelectedAddr then idxA = ti end
											if tn.addr == node.addr then idxB = ti end
										end
										if idxA and idxB then
											local lo, hi = math.min(idxA, idxB), math.max(idxA, idxB)
											local range = {}
											for ti = lo, hi do range[#range + 1] = S.treeList[ti] end
											F.setSelectionNodes(range)
										else
											F.setSelectionNodes({ node })
										end
									elseif F.isCtrlDown() then
										F.toggleSelectionNode(node)
									else
										F.setSelectionNodes({ node })
									end
									drag.lastClickAddr = node.addr
									drag.lastClickTime = nowT
									F.rebuildPropTree()
								end
							end
						elseif clicked2 and rowHov then
							drag.m2Candidate = node
						elseif released2 and rowHov and drag.m2Candidate and drag.m2Candidate.addr == node.addr then
							if not S.selectionMap[node.addr] then
								F.setSelectionNodes({ node })
								F.rebuildPropTree()
							end
							UI.ctx.items = F.buildContextMenu()
							UI.ctx.x = mPos.X; UI.ctx.y = mPos.Y; UI.ctx.visible = true
						end
					else
						r.bg.Visible = false; r.bd.Visible = false; r.expTri.Visible = false
						r.iconBg.Visible = false; r.iconTx.Visible = false; r.label.Visible = false
					end
				end

				if clicked1 and not consumed and F.pointInRect(mPos, x, y, w, h) then
					UI.focusTarget = nil
					consumed = true
				end
			else
				hideGroup(EX)
			end

			-- ---------------------------------------------------------
			-- 9. PropertiesPanel Render + Interaction
			-- ---------------------------------------------------------
			if UI.propWin.visible then
				local x, y, w, h = UI.propWin.x, UI.propWin.y, UI.propWin.w, UI.propWin.h
				local topH = 50
				local listX, listY = x + 1, y + topH
				local listW = w - 18
				local listH = h - topH - 1
				local visRows = math.min(MAX_PROP_ROWS, math.max(1, math.floor(listH / 22)))

				UI.propScroll = math.clamp(UI.propScroll, 0, math.max(0, #S.propTree - visRows))

				PR.bg.Position = Vector2.new(x, y); PR.bg.Size = Vector2.new(w, h); PR.bg.Visible = true
				PR.bd.Position = Vector2.new(x, y); PR.bd.Size = Vector2.new(w, h); PR.bd.Visible = true
				PR.topBar.Position = Vector2.new(x + 1, y + 1); PR.topBar.Size = Vector2.new(w - 2, topH - 1); PR.topBar.Visible = true

				local pTitle = "Properties"
				if #S.selectionList == 1 then
					pTitle = "Properties - " .. S.selectionList[1].className
				elseif #S.selectionList > 1 then
					pTitle = "Properties (" .. #S.selectionList .. ")"
				end
				PR.title.Position = Vector2.new(x + w * 0.5, y + 4); PR.title.Text = F.fitText(pTitle, w - 58, 6.6); PR.title.Visible = true

				local hovX = (not consumed) and F.pointInRect(mPos, x + w - 26, y + 1, 24, 24)
				PR.closeBg.Position = Vector2.new(x + w - 26, y + 1); PR.closeBg.Size = Vector2.new(24, 24)
				PR.closeBg.Color = hovX and C_HOV or C_TOPBAR; PR.closeBg.Visible = true
				PR.closeTxt.Position = Vector2.new(x + w - 14, y + 5); PR.closeTxt.Text = "X"; PR.closeTxt.Visible = true

				local hovSet = (not consumed) and F.pointInRect(mPos, x + w - 26, y + 25, 24, 24)
				PR.setBg.Position = Vector2.new(x + w - 26, y + 25); PR.setBg.Size = Vector2.new(24, 24)
				PR.setBg.Color = hovSet and C_HOV or C_TOPBAR; PR.setBg.Visible = true
				PR.setTxt.Position = Vector2.new(x + w - 14, y + 29); PR.setTxt.Text = "*"; PR.setTxt.Visible = true

				PR.sUnder.Position = Vector2.new(x + 4, y + 45); PR.sUnder.Size = Vector2.new(w - 31, 2); PR.sUnder.Visible = true
				local pFocus = (UI.focusTarget == "propSearch")
				PR.sActive.Position = Vector2.new(x + 4, y + 45); PR.sActive.Size = Vector2.new(pFocus and (w - 31) or 0, 2)
				PR.sActive.Visible = pFocus
				PR.sTxt.Position = Vector2.new(x + 6, y + 27)
				if pFocus or UI.propSearch.text ~= "" then
					local caret = pFocus and (math.floor(F.now() * 2) % 2 == 0 and "|" or "") or ""
					PR.sTxt.Text = F.fitText(UI.propSearch.text .. caret, w - 38, 6.6)
					PR.sTxt.Color = C_TXT
				else
					PR.sTxt.Text = "Search Properties"
					PR.sTxt.Color = C_TXT_DIM
				end
				PR.sTxt.Visible = true

				if clicked1 and not consumed and F.pointInRect(mPos, x, y, w, topH) then
					consumed = true
					bringWinFront("prop")
					if hovX then
						UI.propWin.visible = false
					elseif hovSet then
						UI.settingsWin.visible = not UI.settingsWin.visible
						UI.settingsWin.x = math.max(8, x - UI.settingsWin.w - 6)
						UI.settingsWin.y = y + 26
					elseif F.pointInRect(mPos, x + 4, y + 25, w - 31, 22) then
						UI.focusTarget = "propSearch"
					else
						UI.focusTarget = nil
						drag.mode = "prop"
						drag.startM = mPos
						drag.off = mPos - Vector2.new(x, y)
					end
				end

				local vScrollX = x + w - 17
				local vScrollH = h - topH - 1
				UI.propScroll = drawScrollbar(
					{ trk = PR.vTrk, thm = PR.vThm, b1 = PR.vUpBg, t1 = PR.vUpTri, b2 = PR.vDnBg, t2 = PR.vDnTri },
					vScrollX, listY, 16, vScrollH, #S.propTree + 1, visRows, UI.propScroll, false, mPos, m1, clicked1 and not consumed, scrPropV
				)
				if clicked1 and not consumed and F.pointInRect(mPos, vScrollX, listY, 16, vScrollH) then
					consumed = true
				end

				local sepX = listX + S.propNameWidth + 16
				local valX = sepX + 4
				local valW = (listX + listW) - valX - 2

				for i = 1, MAX_PROP_ROWS do
					local r = PR.rows[i]
					local item = (i <= visRows) and S.propTree[i + UI.propScroll] or nil
					if item then
						local ry = listY + (i - 1) * 22
						local rowHov = (not consumed) and F.pointInRect(mPos, listX, ry, listW, 22)

						r.bg.Position = Vector2.new(listX, ry); r.bg.Size = Vector2.new(listW, 22)
						r.bg.Color = item.isCategory and C_BG or (rowHov and C_HOV or C_PROP_BG); r.bg.Visible = true
						r.bot.From = Vector2.new(listX, ry + 21); r.bot.To = Vector2.new(listX + listW, ry + 21); r.bot.Visible = true

						if item.isCategory then
							r.sep.Visible = false; r.valBg.Visible = false; r.valBd.Visible = false; r.swatch.Visible = false; r.valTxt.Visible = false
							setTriDir(r.expTri, listX + 2, ry + 3, 14, 16, S.propExpanded[item.refKey] and "down" or "right", C_TXT)
							r.nameTxt.Position = Vector2.new(listX + 18, ry + 4); r.nameTxt.Font = 2
							r.nameTxt.Text = item.name; r.nameTxt.Color = C_TXT; r.nameTxt.Visible = true

							if clicked1 and rowHov then
								consumed = true
								S.propExpanded[item.refKey] = not S.propExpanded[item.refKey]
								F.rebuildPropTree()
							end
						else
							r.sep.From = Vector2.new(sepX, ry); r.sep.To = Vector2.new(sepX, ry + 21); r.sep.Visible = true
							local isExpandable = (item.realType == "Vector3" or item.realType == "Vector2" or item.realType == "CFrame") and not item.spec.parentProp
							local nameIndent = (item.depth == 2) and 28 or 16
							if isExpandable then
								setTriDir(r.expTri, listX + 2, ry + 3, 14, 16, S.propExpanded[item.refKey] and "down" or "right", C_TXT)
							else
								r.expTri.Visible = false
							end

							r.nameTxt.Position = Vector2.new(listX + nameIndent, ry + 4); r.nameTxt.Font = 0
							r.nameTxt.Text = F.fitText(item.spec.name, sepX - (listX + nameIndent) - 3, 6.4)
							r.nameTxt.Color = item.spec.writable and C_TXT or C_TXT_RO; r.nameTxt.Visible = true

							local editingThis = (UI.focusTarget == "propEdit" and UI.propEdit.refKey == item.refKey)
							if editingThis then
								r.valBg.Position = Vector2.new(valX - 2, ry + 1); r.valBg.Size = Vector2.new(valW + 2, 19); r.valBg.Visible = true
								r.valBd.Position = Vector2.new(valX - 2, ry + 1); r.valBd.Size = Vector2.new(valW + 2, 19); r.valBd.Visible = true
								r.swatch.Visible = false
								local caret = (math.floor(F.now() * 2) % 2 == 0) and "|" or ""
								r.valTxt.Position = Vector2.new(valX + 2, ry + 4)
								r.valTxt.Text = F.fitText(UI.propEdit.text .. caret, valW - 4, 6.4)
								r.valTxt.Color = C_WHITE; r.valTxt.Visible = true
							elseif item.realType == "bool" or (item.realType == "auto" and type(item.val) == "boolean") then
								r.valBg.Visible = false; r.valBd.Visible = false
								r.swatch.Position = Vector2.new(valX + 2, ry + 5); r.swatch.Size = Vector2.new(12, 12)
								r.swatch.Color = item.val and C_BLUE or C_TOPBAR; r.swatch.Visible = true
								r.valTxt.Position = Vector2.new(valX + 19, ry + 4)
								r.valTxt.Text = item.val and "true" or "false"
								r.valTxt.Color = item.spec.writable and C_TXT or C_TXT_RO; r.valTxt.Visible = true
							elseif item.realType == "Color3" and item.val then
								r.valBg.Visible = false; r.valBd.Visible = false
								r.swatch.Position = Vector2.new(valX + 2, ry + 5); r.swatch.Size = Vector2.new(12, 12)
								r.swatch.Color = item.val; r.swatch.Visible = true
								r.valTxt.Position = Vector2.new(valX + 19, ry + 4)
								r.valTxt.Text = F.fitText(item.valStr, valW - 21, 6.4)
								r.valTxt.Color = item.spec.writable and C_TXT or C_TXT_RO; r.valTxt.Visible = true
							else
								r.valBg.Visible = false; r.valBd.Visible = false; r.swatch.Visible = false
								r.valTxt.Position = Vector2.new(valX + 2, ry + 4)
								r.valTxt.Text = F.fitText(item.valStr, valW - 4, 6.4)
								r.valTxt.Color = (item.realType == "Instance" and item.val) and Color3.fromRGB(130, 190, 255) or (item.spec.writable and C_TXT or C_TXT_RO)
								r.valTxt.Visible = true
							end

							if clicked1 and rowHov then
								consumed = true
								bringWinFront("prop")
								if isExpandable and F.pointInRect(mPos, listX, ry, 20, 22) then
									S.propExpanded[item.refKey] = not S.propExpanded[item.refKey]
									F.rebuildPropTree()
								elseif F.pointInRect(mPos, sepX, ry, valW + 8, 22) then
									if item.realType == "Instance" and item.val then
										local targetNode = F.revealInstance(item.val)
										if targetNode then F.setSelectionNodes({ targetNode }); F.rebuildPropTree() end
									elseif item.spec.writable then
										if item.realType == "bool" or (item.realType == "auto" and type(item.val) == "boolean") then
											F.writePropValue(item.spec, item.val and "false" or "true")
										else
											UI.focusTarget = "propEdit"
											UI.propEdit = { spec = item.spec, refKey = item.refKey, text = tostring(item.valStr == "nil" and "" or item.valStr) }
										end
									end
								else
									UI.focusTarget = nil
								end
							elseif clicked2 and rowHov then
								drag.m2Candidate = { propKey = item.refKey }
							elseif released2 and rowHov and drag.m2Candidate and drag.m2Candidate.propKey == item.refKey then
								local pItems = {
									{ name = "Copy Value", shortcut = "", disabled = false, color = C_BLUE, cb = function()
										F.copyToClipboard(item.valStr); F.notify("Dex", "Copied: " .. tostring(item.valStr):sub(1, 30))
									end },
									{ name = "Copy Name = Value", shortcut = "", disabled = false, color = C_TXT, cb = function()
										F.copyToClipboard(item.spec.name .. " = " .. tostring(item.valStr)); F.notify("Dex", "Copied property")
									end },
								}
								if item.spec.writable and item.realType == "Instance" then
									pItems[#pItems + 1] = { name = "Edit Value", shortcut = "", disabled = false, color = Color3.fromRGB(110, 190, 130), cb = function()
										UI.focusTarget = "propEdit"
										UI.propEdit = { spec = item.spec, refKey = item.refKey, text = tostring(item.valStr == "nil" and "" or item.valStr) }
									end }
								end
								UI.ctx.items = pItems
								UI.ctx.x = mPos.X; UI.ctx.y = mPos.Y; UI.ctx.visible = true
							end
						end
					else
						r.bg.Visible = false; r.bot.Visible = false; r.sep.Visible = false
						r.expTri.Visible = false; r.nameTxt.Visible = false
						r.valBg.Visible = false; r.valBd.Visible = false; r.swatch.Visible = false; r.valTxt.Visible = false
					end
				end

				if clicked1 and not consumed and F.pointInRect(mPos, x, y, w, h) then
					UI.focusTarget = nil
					consumed = true
				end
			else
				hideGroup(PR)
			end

			if released2 then drag.m2Candidate = nil end
			if clicked1 and not consumed then
				UI.focusTarget = nil
				if S.clickSelectMode or F.isAltDown() then
					F.selectWorldPartAt(mPos.X, mPos.Y)
				end
			end
		end
		F.trackConn(S.RunService.RenderStepped:Connect(function()
			local ok, err = pcall(stepFrame)
			if not ok and not reportedErr then
				reportedErr = true
				pcall(warn, "[Dex Render Error]", err)
				F.notify("Dex Error", tostring(err), 5)
			end
		end))
	end

	_G.DEX_MATCHA_CLEANUP = function()
		S.alive = false
		for _, c in ipairs(S.connections) do pcall(function() c:Disconnect() end) end
		S.connections = {}
		for _, d in ipairs(S.drawings) do pcall(function() d:Remove() end) end
		S.drawings = {}
	end
end)();

--=====================================================================
-- 8. KEYBOARD INPUT POLLING + HOTKEYS & LIVE REFRESH LOOPS
--=====================================================================
(function()
	local function handleKeyDown(vk)
		if not S.alive then return end

		if (vk == VK.DELETE and not F.isCtrlDown()) or vk == 0xA1 then -- Delete or RightShift toggles Dex UI
			UI.uiHidden = not UI.uiHidden
			UI.focusTarget = nil
			return
		end

		if UI.uiHidden then return end

		-- Text input targets
		if UI.focusTarget == "rename" and UI.renameModal.visible then
			if vk == VK.BACKSPACE then
				UI.renameModal.text = UI.renameModal.text:sub(1, math.max(0, #UI.renameModal.text - 1))
			elseif vk == VK.ENTER then
				local nd = UI.renameModal.node
				if nd and nd.obj and UI.renameModal.text ~= "" then
					pcall(function() nd.obj.Name = UI.renameModal.text end)
					nd.name = UI.renameModal.text
					F.rebuildTreeList(); F.rebuildPropTree()
				end
				UI.renameModal.visible = false; UI.focusTarget = nil
			elseif vk == VK.ESCAPE then
				UI.renameModal.visible = false; UI.focusTarget = nil
			else
				local ch = F.keyToChar(vk)
				if ch then UI.renameModal.text = UI.renameModal.text .. ch end
			end
			return
		end

		if UI.focusTarget == "propEdit" and UI.propEdit.spec then
			if vk == VK.BACKSPACE then
				UI.propEdit.text = UI.propEdit.text:sub(1, math.max(0, #UI.propEdit.text - 1))
			elseif vk == VK.ENTER then
				F.writePropValue(UI.propEdit.spec, UI.propEdit.text)
				UI.focusTarget = nil
			elseif vk == VK.ESCAPE then
				UI.focusTarget = nil
			else
				local ch = F.keyToChar(vk)
				if ch then UI.propEdit.text = UI.propEdit.text .. ch end
			end
			return
		end

		if UI.focusTarget == "expSearch" then
			if vk == VK.BACKSPACE then
				UI.expSearch.text = UI.expSearch.text:sub(1, math.max(0, #UI.expSearch.text - 1))
				F.scheduleExplorerSearch(UI.expSearch.text)
			elseif vk == VK.ENTER then
				F.runExplorerSearch(UI.expSearch.text)
				UI.focusTarget = nil
			elseif vk == VK.ESCAPE then
				UI.focusTarget = nil
			else
				local ch = F.keyToChar(vk)
				if ch then
					UI.expSearch.text = UI.expSearch.text .. ch
					F.scheduleExplorerSearch(UI.expSearch.text)
				end
			end
			return
		end

		if UI.focusTarget == "propSearch" then
			if vk == VK.BACKSPACE then
				UI.propSearch.text = UI.propSearch.text:sub(1, math.max(0, #UI.propSearch.text - 1))
				S.propSearch = UI.propSearch.text
				F.rebuildPropTree()
			elseif vk == VK.ENTER or vk == VK.ESCAPE then
				UI.focusTarget = nil
			else
				local ch = F.keyToChar(vk)
				if ch then
					UI.propSearch.text = UI.propSearch.text .. ch
					S.propSearch = UI.propSearch.text
					F.rebuildPropTree()
				end
			end
			return
		end

		-- Explorer Keyboard Navigation & Shortcuts when mouse hovers Explorer/Properties
		local mPos = F.getMousePos()
		local overExp = UI.expWin.visible and F.pointInRect(mPos, UI.expWin.x, UI.expWin.y, UI.expWin.w, UI.expWin.h)
		local overProp = UI.propWin.visible and F.pointInRect(mPos, UI.propWin.x, UI.propWin.y, UI.propWin.w, UI.propWin.h)
		local overViewer = S.viewer.visible and F.pointInRect(mPos, S.viewer.x, S.viewer.y, S.viewer.w, S.viewer.h)

		if overViewer then
			if vk == VK.UP or vk == VK.PGUP then S.viewer.scroll = math.max(0, S.viewer.scroll - (vk == VK.PGUP and 10 or 2))
			elseif vk == VK.DOWN or vk == VK.PGDN then S.viewer.scroll = S.viewer.scroll + (vk == VK.PGDN and 10 or 2) end
			return
		end

		if overProp then
			if vk == VK.UP or vk == VK.PGUP then UI.propScroll = math.max(0, UI.propScroll - (vk == VK.PGUP and 8 or 2))
			elseif vk == VK.DOWN or vk == VK.PGDN then UI.propScroll = UI.propScroll + (vk == VK.PGDN and 8 or 2) end
			return
		end

		if overExp then
			if F.isCtrlDown() then
				if vk == 0x58 then F.actionCut(); return -- Ctrl+X
				elseif vk == 0x42 or vk == 0x56 then F.actionPasteInto(); return -- Ctrl+B / Ctrl+V
				elseif vk == 0x52 then F.openRenameDialog(); return -- Ctrl+R
				elseif vk == 0x46 then UI.focusTarget = "expSearch"; return -- Ctrl+F
				elseif vk == 0x43 and S.selectionList[1] then -- Ctrl+C copies path
					F.copyToClipboard(F.safeFullName(S.selectionList[1].obj)); F.notify("Dex", "Path copied"); return
				elseif vk == VK.DELETE then -- Ctrl+Del unparents selection
					F.actionDelete(); return
				end
			end
			if vk == VK.PGUP then UI.expScroll = math.max(0, UI.expScroll - 10); return
			elseif vk == VK.PGDN then UI.expScroll = UI.expScroll + 10; return
			elseif vk == VK.UP or vk == VK.DOWN then
				local curIdx = 1
				local sel = S.selectionList[1]
				if sel then
					for i, n in ipairs(S.treeList) do
						if n.addr == sel.addr then curIdx = i; break end
					end
				end
				local nextIdx = math.clamp(curIdx + (vk == VK.DOWN and 1 or -1), 1, #S.treeList)
				local target = S.treeList[nextIdx]
				if target then
					F.setSelectionNodes({ target }); F.rebuildPropTree()
					UI.expScroll = math.clamp(UI.expScroll, math.max(0, nextIdx - 12), math.max(0, nextIdx - 1))
				end
				return
			elseif vk == VK.RIGHT and S.selectionList[1] then
				local sel = S.selectionList[1]
				if sel.hasChildren and not S.expanded[sel.addr] then F.toggleExpandNode(sel) end
				return
			elseif vk == VK.LEFT and S.selectionList[1] then
				local sel = S.selectionList[1]
				if S.expanded[sel.addr] then F.toggleExpandNode(sel)
				elseif sel.parent and sel.parent.addr ~= S.rootNode.addr then
					F.setSelectionNodes({ sel.parent }); F.rebuildPropTree()
				end
				return
			end
		end
	end

	function F.startLoops()
		-- Keyboard polling loop
		task.spawn(function()
			local prev = {}
			local bsHeld, bsNext = nil, 0
			while S.alive do
				local active = (not isrbxactive) or isrbxactive()
				if active then
					for k = 0x08, 0xDF do
						if k ~= 0x10 and k ~= 0xA0 and k ~= 0x11 and k ~= 0xA2 and k ~= 0xA3 and k ~= 0x12 and k ~= 0xA4 and k ~= 0xA5 then
							local down = F.isKeyDown(k)
							if down and not prev[k] then
								handleKeyDown(k)
								if k == VK.BACKSPACE or k == VK.UP or k == VK.DOWN then
									bsHeld = k; bsNext = F.now() + 0.32
								end
							elseif down and bsHeld == k and F.now() >= bsNext then
								handleKeyDown(k)
								bsNext = F.now() + 0.055
							elseif not down and bsHeld == k then
								bsHeld = nil
							end
							prev[k] = down
						end
					end
				else
					prev = {}; bsHeld = nil
				end
				task.wait(0.022)
			end
		end)

		-- Background Live Property, Hover Pick & Tree Refresh Loop
		task.spawn(function()
			local tickCount = 0
			while S.alive do
				task.wait(0.08)
				if not S.alive then break end
				if S.clickSelectMode or F.isAltDown() then
					local mPos = F.getMousePos()
					local overUI = false
					if not UI.uiHidden then
						if UI.expWin.visible and F.pointInRect(mPos, UI.expWin.x, UI.expWin.y, UI.expWin.w, UI.expWin.h) then overUI = true end
						if UI.propWin.visible and F.pointInRect(mPos, UI.propWin.x, UI.propWin.y, UI.propWin.w, UI.propWin.h) then overUI = true end
						if UI.ctx.visible then overUI = true end
						if UI.settingsWin.visible and F.pointInRect(mPos, UI.settingsWin.x, UI.settingsWin.y, UI.settingsWin.w, UI.settingsWin.h) then overUI = true end
						if S.viewer.visible and F.pointInRect(mPos, S.viewer.x, S.viewer.y, S.viewer.w, S.viewer.h) then overUI = true end
					end
					if not overUI and mPos.X >= 0 and mPos.Y >= 0 then
						local hitPart = F.raycastScreenPart(mPos.X, mPos.Y)
						if hitPart then
							local mdl = F.findTopModelOfPart(hitPart)
							local pName = F.safeName(hitPart)
							local mName = mdl and F.safeName(mdl) or nil
							if F.isShiftDown() and mdl then
								S.hoverPickTarget = {
									kind = "part",
									name = mName,
									className = F.safeClass(mdl),
									part = hitPart,
									hoverLabel = string.format("Click Model: %s (%s)", mName, pName),
								}
							else
								S.hoverPickTarget = {
									kind = "part",
									name = pName,
									className = F.safeClass(hitPart),
									part = hitPart,
									hoverLabel = mName and string.format("Click: %s [Shift: %s]", pName, mName) or string.format("Click: %s [%s]", pName, F.safeClass(hitPart)),
								}
							end
						else
							S.hoverPickTarget = nil
						end
					else
						S.hoverPickTarget = nil
					end
				else
					S.hoverPickTarget = nil
				end

				tickCount = tickCount + 1
				if not UI.uiHidden and tickCount % 3 == 0 then
					if UI.propWin.visible and UI.focusTarget ~= "propEdit" then
						F.refreshVisiblePropValues()
					end
					if S.autoRefresh and tickCount % 18 == 0 and UI.expWin.visible and S.searchResults == nil then
						F.refreshExpandedTree()
					end
				end
			end
		end)
	end
end)();

--=====================================================================
-- 9. STARTUP SEQUENCE (MATCHING WELCOME PROGRESS)
--=====================================================================
task.spawn(function()
	while S.alive and not (S.Players and S.RunService and S.UserInputService) do
		F.initServices()
		if S.Players and S.RunService and S.UserInputService then break end
		task.wait(0.2)
	end
	if not S.alive then return end

	F.startRenderer()
	F.startLoops()

	UI.welcome.step = 1; task.wait(0.15)
	UI.welcome.step = 2; task.wait(0.15)
	UI.welcome.step = 3; task.wait(0.15)
	UI.welcome.step = 4
	F.initTree()
	if S.rootNode and S.rootNode.children and S.rootNode.children[1] then
		F.setSelectionNodes({ S.rootNode.children[1] })
		F.rebuildPropTree()
	end
	task.wait(0.15)
	UI.welcome.step = 5
	UI.welcome.autoCloseAt = F.now() + 1.5

	F.notify("Dex Matcha v1.1.0", "Loaded! Delete or RightShift toggles UI.", 4)
end)
