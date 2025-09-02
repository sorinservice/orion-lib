-- Orion Library (Sorin Clean Build)
-- Mobile-friendly, FS-safe, neutral lock overlay, Footer API
-- Public API (stable):
--   local OrionLib = ...return...
--   local Window   = OrionLib:MakeWindow(opts)
--   local Tab      = Window:MakeTab(opts)
--   Tab:Add{Label,Paragraph,Button,Toggle,Slider,Dropdown,Bind,Textbox,Colorpicker}
--   Window:SetFooter(text, props?)  -- new
--   OrionLib:Init()
--   OrionLib:Destroy()

local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local LocalPlayer      = Players.LocalPlayer
local HttpService      = game:GetService("HttpService")

-- ====== Filesystem guard (executor dependent) ==============================
local FS_OK = (typeof(isfolder) == "function" and typeof(makefolder) == "function"
            and typeof(isfile)   == "function" and typeof(writefile) == "function"
            and typeof(readfile) == "function")

-- ====== Globals / Icons ====================================================
getgenv().gethui = function() return game.CoreGui end

local Icons = {
  main = "rbxassetid://133768243848629",
  info = "rbxassetid://77831165474864"
}
local function GetIcon(key) return Icons[key] end

-- ====== Core state =========================================================
local OrionLib = {
  Elements      = {},
  ThemeObjects  = {},
  Connections   = {},
  Flags         = {},
  Themes        = {
    Default = {
      Main     = Color3.fromRGB(20,20,20),
      Second   = Color3.fromRGB(30,33,30),
      Stroke   = Color3.fromRGB(90,0,120),
      Divider  = Color3.fromRGB(32,0,29),
      Text     = Color3.fromRGB(240,240,240),
      TextDark = Color3.fromRGB(150,150,150),
    }
  },
  SelectedTheme = "Default",
  Folder        = nil,
  SaveCfg       = false
}

-- ====== Single ScreenGui instance =========================================
local Orion = Instance.new("ScreenGui")
Orion.Name = (getgenv()._SorinWinCfg and getgenv()._SorinWinCfg.GuiName) or "SorinHub"
if syn then syn.protect_gui(Orion) end
Orion.Parent = gethui() or game.CoreGui

-- remove duplicates
for _, gui in ipairs((gethui() or game.CoreGui):GetChildren()) do
  if gui ~= Orion and gui.Name == Orion.Name then gui:Destroy() end
end

function OrionLib:IsRunning()
  if gethui then return Orion.Parent == gethui() end
  return Orion.Parent == game:GetService("CoreGui")
end

local function on(Signal, fn)
  if not OrionLib:IsRunning() then return end
  local c = Signal:Connect(fn); table.insert(OrionLib.Connections, c); return c
end

task.spawn(function()
  while OrionLib:IsRunning() do task.wait() end
  for _, c in ipairs(OrionLib.Connections) do pcall(function() c:Disconnect() end) end
end)

-- ====== Small helpers (deduped, minimal) ===================================
local function Create(name, props, kids)
  local o = Instance.new(name)
  if props then for k,v in pairs(props) do o[k]=v end end
  if kids then for _,ch in ipairs(kids) do ch.Parent=o end end
  return o
end

local function Make(name, fn) OrionLib.Elements[name] = fn end
local function E(name, ...) return OrionLib.Elements[name](...) end

local function propForTheme(obj)
  if obj:IsA("Frame") or obj:IsA("TextButton") then return "BackgroundColor3" end
  if obj:IsA("ScrollingFrame") then return "ScrollBarImageColor3" end
  if obj:IsA("UIStroke") then return "Color" end
  if obj:IsA("TextLabel") or obj:IsA("TextBox") then return "TextColor3" end
  if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then return "ImageColor3" end
end

local function themify(obj, role)
  OrionLib.ThemeObjects[role] = OrionLib.ThemeObjects[role] or {}
  table.insert(OrionLib.ThemeObjects[role], obj)
  local p = propForTheme(obj); if p then obj[p] = OrionLib.Themes[OrionLib.SelectedTheme][role] end
  return obj
end

local function Round(num, step)
  local r = math.floor(num/step + (math.sign(num)*0.5)) * step
  if r < 0 then r = r + step end; return r
end

local function PackColor(c) return {R=c.R*255,G=c.G*255,B=c.B*255} end
local function UnpackColor(t) return Color3.fromRGB(t.R, t.G, t.B) end

-- ====== Config I/O (safe) ==================================================
local function LoadCfg(json)
  local ok, data = pcall(function() return HttpService:JSONDecode(json) end)
  if not ok then warn("Config decode failed:", data); return end
  for k,v in pairs(data) do
    local f = OrionLib.Flags[k]
    if f then
      task.spawn(function()
        if f.Type=="Colorpicker" then f:Set(UnpackColor(v)) else f:Set(v) end
      end)
    else
      warn("Missing flag:", k)
    end
  end
end

local function SaveCfg(name)
  if not (FS_OK and OrionLib.Folder) then return end
  local data = {}
  for k,f in pairs(OrionLib.Flags) do
    if f.Save then data[k] = (f.Type=="Colorpicker") and PackColor(f.Value) or f.Value end
  end
  local ok, json = pcall(HttpService.JSONEncode, HttpService, data); if not ok then return end
  pcall(writefile, OrionLib.Folder.."/"..name..".txt", tostring(json))
end

-- ====== UI element factories ==============================================
Make("Corner", function(scale, offset) return Create("UICorner",{CornerRadius=UDim.new(scale or 0, offset or 10)}) end)
Make("Stroke", function(color, th) return Create("UIStroke",{Color=color or Color3.new(1,1,1),Thickness=th or 1}) end)
Make("List",   function(scale, off) return Create("UIListLayout",{SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(scale or 0, off or 0)}) end)
Make("Padding",function(b,l,r,t) return Create("UIPadding",{PaddingBottom=UDim.new(0,b or 4),PaddingLeft=UDim.new(0,l or 4),PaddingRight=UDim.new(0,r or 4),PaddingTop=UDim.new(0,t or 4)}) end)
Make("TFrame", function() return Create("Frame",{BackgroundTransparency=1}) end)
Make("Frame",  function(color) return Create("Frame",{BackgroundColor3=color or Color3.new(1,1,1), BorderSizePixel=0}) end)
Make("RoundFrame", function(color, scale, offset) return Create("Frame",{BackgroundColor3=color or Color3.new(1,1,1), BorderSizePixel=0},{Create("UICorner",{CornerRadius=UDim.new(scale or 0, offset or 10)})}) end)
Make("Button", function() return Create("TextButton",{Text="",AutoButtonColor=false,BackgroundTransparency=1,BorderSizePixel=0}) end)
Make("ScrollFrame", function(color, width) return Create("ScrollingFrame",{
  BackgroundTransparency=0.9, MidImage="rbxassetid://7445543667", BottomImage="rbxassetid://7445543667", TopImage="rbxassetid://7445543667",
  ScrollBarImageColor3=color or Color3.new(1,1,1), BorderSizePixel=0, ScrollBarThickness=width or 5, CanvasSize=UDim2.new(0,0,0,0)
}) end)
Make("Image", function(id)
  local img = Create("ImageLabel",{Image=id, BackgroundTransparency=1})
  if GetIcon(id) then img.Image = GetIcon(id) end
  return img
end)
Make("ImageButton", function(id) return Create("ImageButton",{Image=id,BackgroundTransparency=1}) end)
Make("Label", function(text, size, tr)
  return Create("TextLabel",{Text=text or "",TextColor3=Color3.fromRGB(240,240,240),TextTransparency=tr or 0,TextSize=size or 15,Font=Enum.Font.Gotham,RichText=true,BackgroundTransparency=1,TextXAlignment=Enum.TextXAlignment.Left})
end)

-- ====== Notifications ======================================================
local NotificationHolder = Create("Frame", {BackgroundTransparency=1, Position=UDim2.new(1,-25,1,-25), Size=UDim2.new(0,300,1,-25), AnchorPoint=Vector2.new(1,1), Parent=Orion}, {
  Create("UIListLayout",{HorizontalAlignment=Enum.HorizontalAlignment.Center, VerticalAlignment=Enum.VerticalAlignment.Bottom, SortOrder=Enum.SortOrder.LayoutOrder, Padding=UDim.new(0,5)})
})

function OrionLib:MakeNotification(cfg)
  task.spawn(function()
    cfg = cfg or {}; cfg.Name = cfg.Name or "Notification"; cfg.Content = cfg.Content or "Test"; cfg.Image = cfg.Image or "rbxassetid://87052561483042"; cfg.Time = cfg.Time or 10
    local parent = Create("Frame",{BackgroundTransparency=1, AutomaticSize=Enum.AutomaticSize.Y, Size=UDim2.new(1,0,0,0), Parent=NotificationHolder})
    local frame = Create("Frame",{BackgroundColor3=Color3.fromRGB(25,25,25), AutomaticSize=Enum.AutomaticSize.Y, Size=UDim2.new(1,0,0,0), Position=UDim2.new(1,-55,0,0)}, {
      E("Stroke", Color3.fromRGB(93,93,93), 1.2), E("Padding", 12,12,12,12),
      Create("ImageLabel",{Image=cfg.Image,BackgroundTransparency=1, Size=UDim2.new(0,20,0,20), ImageColor3=Color3.fromRGB(240,240,240), Name="Icon"}),
      Create("TextLabel",{Text=cfg.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-30,0,20), Position=UDim2.new(0,30,0,0), Name="Title", TextColor3=Color3.fromRGB(240,240,240)}),
      Create("TextLabel",{Text=cfg.Content, TextSize=14, Font=Enum.Font.GothamSemibold, BackgroundTransparency=1, Size=UDim2.new(1,0,0,0), Position=UDim2.new(0,0,0,25), AutomaticSize=Enum.AutomaticSize.Y, Name="Content", TextWrapped=true, TextColor3=Color3.fromRGB(200,200,200)})
    })
    TweenService:Create(frame, TweenInfo.new(0.5, Enum.EasingStyle.Quint), {Position=UDim2.new(0,0,0,0)}):Play()
    task.wait(cfg.Time - 0.88)
    TweenService:Create(frame, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {BackgroundTransparency=0.6}):Play()
    task.wait(0.35)
    TweenService:Create(frame, TweenInfo.new(0.8, Enum.EasingStyle.Quint), {Position=UDim2.new(1,20,0,0)}):Play()
    task.wait(1.35)
    frame:Destroy(); parent:Destroy()
  end)
end

function OrionLib:Init()
  if OrionLib.SaveCfg and FS_OK then
    pcall(function()
      local path = OrionLib.Folder.."/"..game.GameId..".txt"
      if isfile(path) then
        LoadCfg(readfile(path))
        OrionLib:MakeNotification({Name="Configuration", Content="Auto-loaded configuration for game "..game.GameId..".", Time=5})
      end
    end)
  end
end

-- ====== Dragging (touch + mouse, correct clamping for Scale) ===============
local function AddDragging(DragZone, Main)
  local dragging, dragInput = false, nil
  local dragStart = Vector2.zero
  local startPos  = UDim2.new()

  local function clampOffset(ox, oy)
    local ps = (Main.Parent and Main.Parent.AbsoluteSize) or (workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize) or Vector2.new(1920,1080)
    local ws = Main.AbsoluteSize
    local sx, sy = startPos.X.Scale, startPos.Y.Scale
    local minX = -ps.X * sx
    local maxX =  ps.X * (1 - sx) - ws.X
    local minY = -ps.Y * sy
    local maxY =  ps.Y * (1 - sy) - ws.Y
    return math.clamp(ox, minX, maxX), math.clamp(oy, minY, maxY)
  end

  local function update(input)
    if not dragging then return end
    local d = input.Position - dragStart
    local newOx = startPos.X.Offset + d.X
    local newOy = startPos.Y.Offset + d.Y
    newOx, newOy = clampOffset(newOx, newOy)
    Main.Position = UDim2.new(startPos.X.Scale, newOx, startPos.Y.Scale, newOy)
  end

  DragZone.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
      dragging  = true; dragStart = input.Position; startPos = Main.Position; dragInput = input
      input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then dragging = false end
      end)
    end
  end)

  DragZone.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
      dragInput = input
    end
  end)

  UserInputService.InputChanged:Connect(function(input)
    if input == dragInput and dragging then update(input) end
  end)
end

-- ====== Window builder =====================================================
function OrionLib:MakeWindow(cfg)
  cfg = cfg or {}
  cfg.Name         = cfg.Name or "SorinHub"
  cfg.ConfigFolder = cfg.ConfigFolder or cfg.Name
  cfg.SaveConfig   = cfg.SaveConfig or false
  cfg.HidePremium  = cfg.HidePremium or false
  if cfg.IntroEnabled == nil then cfg.IntroEnabled = true end
  cfg.IntroText    = cfg.IntroText or "Loading SorinHub"
  cfg.CloseCallback= cfg.CloseCallback or function() end
  cfg.ShowIcon     = cfg.ShowIcon or false
  cfg.Icon         = cfg.Icon or "rbxassetid://8834748103"
  cfg.IntroIcon    = cfg.IntroIcon or "rbxassetid://122633020844347"

  OrionLib.Folder = cfg.ConfigFolder
  OrionLib.SaveCfg = cfg.SaveConfig
  if cfg.SaveConfig then
    if not FS_OK then
      OrionLib.SaveCfg = false
      OrionLib:MakeNotification({Name="Config", Content="Saving disabled: filesystem not available on this executor.", Time=6})
    elseif not isfolder(cfg.ConfigFolder) then makefolder(cfg.ConfigFolder) end
  end

  -- Left side: tabs container
  local TabHolder = themify(Create("ScrollingFrame",{
    BackgroundTransparency=0.9, ScrollBarThickness=4, Size=UDim2.new(1,0,1,-50), CanvasSize=UDim2.new(), BorderSizePixel=0
  },{
    E("List"), E("Padding", 8,0,0,8)
  }), "Divider")

  on(TabHolder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
    TabHolder.CanvasSize = UDim2.new(0,0,0, TabHolder.UIListLayout.AbsoluteContentSize.Y + 16)
  end)

  -- Buttons on top right
  local CloseBtn = Create("TextButton",{Text="",AutoButtonColor=false,BackgroundTransparency=1, Size=UDim2.new(0.5,0,1,0), Position=UDim2.new(0.5,0,0,0)},{
    themify(Create("ImageLabel",{Image="rbxassetid://7072725342", BackgroundTransparency=1, Position=UDim2.new(0,9,0,6), Size=UDim2.new(0,18,0,18)}),"Text")
  })
  local MinimizeBtn = Create("TextButton",{Text="",AutoButtonColor=false,BackgroundTransparency=1, Size=UDim2.new(0.5,0,1,0)},{
    themify(Create("ImageLabel",{Image="rbxassetid://7072719338", BackgroundTransparency=1, Position=UDim2.new(0,9,0,6), Size=UDim2.new(0,18,0,18), Name="Ico"}),"Text")
  })

  local DragZone = Create("Frame",{BackgroundTransparency=1, Size=UDim2.new(1,0,0,50)})

  local LeftPanel = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Size=UDim2.new(0,150,1,-50), Position=UDim2.new(0,0,0,50)},{
    themify(Create("Frame",{Size=UDim2.new(1,0,0,10)}),"Second"),
    themify(Create("Frame",{Size=UDim2.new(0,10,1,0), Position=UDim2.new(1,-10,0,0)}),"Second"),
    themify(Create("Frame",{Size=UDim2.new(0,1,1,0), Position=UDim2.new(1,-1,0,0)}),"Stroke"),
    TabHolder,
    Create("Frame",{BackgroundTransparency=1, Size=UDim2.new(1,0,0,50), Position=UDim2.new(0,0,1,-50)},{
      themify(Create("Frame",{Size=UDim2.new(1,0,0,1)}),"Stroke"),
      Create("Frame",{BackgroundTransparency=1, AnchorPoint=Vector2.new(0,0.5), Size=UDim2.new(0,32,0,32), Position=UDim2.new(0,10,0.5,0)},{
        Create("ImageLabel",{BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Image="https://www.roblox.com/headshot-thumbnail/image?userId="..LocalPlayer.UserId.."&width=420&height=420&format=png"}),
        themify(Create("ImageLabel",{BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), Image="rbxassetid://4031889928"}),"Second"),
        E("Corner",1)
      }),
      Create("Frame",{BackgroundTransparency=1, AnchorPoint=Vector2.new(0,0.5), Size=UDim2.new(0,32,0,32), Position=UDim2.new(0,10,0.5,0)},{
        themify(E("Stroke"),"Stroke"), E("Corner",1)
      }),
      themify(Create("TextLabel",{Text="SorinHub", TextSize=(cfg.HidePremium and 14 or 13), Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-60,0,13), Position=(cfg.HidePremium and UDim2.new(0,50,0,19) or UDim2.new(0,50,0,12)), ClipsDescendants=true}), "Text"),
      -- Footer placeholder (API-controlled)
      themify(Create("TextLabel",{Text="", Name="Footer", TextSize=11, Font=Enum.Font.Gotham, BackgroundTransparency=1, Size=UDim2.new(1,-60,0,12), Position=UDim2.new(0,50,1,-25), TextXAlignment=Enum.TextXAlignment.Left, TextTransparency=0.35, Visible=true}), "TextDark")
    })
  }), "Second")
  E("Corner",0,10).Parent = LeftPanel

  local TitleLabel = themify(Create("TextLabel",{Text=cfg.Name, TextSize=20, Font=Enum.Font.GothamBlack, BackgroundTransparency=1, Size=UDim2.new(1,-30,2,0), Position=UDim2.new(0,25,0,-24)}),"Text")
  local TopLine = themify(Create("Frame",{Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1)}),"Stroke")

  local MainWindow = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), BorderSizePixel=0, Parent=Orion, Position=UDim2.new(0.5,-307,0.5,-172), Size=UDim2.new(0,615,0,344), ClipsDescendants=true},{
    Create("Frame",{BackgroundTransparency=1, Size=UDim2.new(1,0,0,50), Name="TopBar"},{
      TitleLabel, TopLine,
      themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(0,70,0,30), Position=UDim2.new(1,-90,0,10)},{
        themify(E("Stroke"),"Stroke"),
        themify(Create("Frame",{Size=UDim2.new(0,1,1,0), Position=UDim2.new(0.5,0,0,0)}),"Stroke"),
        CloseBtn, MinimizeBtn
      }), "Second")
    }),
    DragZone,
    LeftPanel
  }), "Main")
  E("Corner",0,10).Parent = MainWindow

  -- small logo on topbar
  local Logo = Create("ImageLabel",{BackgroundTransparency=1, Image="rbxassetid://122633020844347", Size=UDim2.new(0,20,0,20), Position=UDim2.new(0,5,0,15)})
  Logo.Parent = MainWindow.TopBar
  TitleLabel.Position = UDim2.new(0,30,0,-24)

  if cfg.ShowIcon then
    TitleLabel.Position = UDim2.new(0,50,0,-24)
    local ic = Create("ImageLabel",{BackgroundTransparency=1, Image=cfg.Icon, Size=UDim2.new(0,20,0,20), Position=UDim2.new(0,25,0,15)})
    ic.Parent = MainWindow.TopBar
  end

  AddDragging(DragZone, MainWindow)

  -- Mobile reopen chip
  local ReopenChip=nil
  if UserInputService.TouchEnabled then
    ReopenChip = Create("TextButton",{Text="≡", Font=Enum.Font.GothamBold, TextSize=18, AutoButtonColor=true, BackgroundTransparency=0.25, Size=UDim2.new(0,32,0,32), Position=UDim2.new(0,8,0,8), Visible=false, Parent=Orion})
    ReopenChip.MouseButton1Click:Connect(function() MainWindow.Visible=true; ReopenChip.Visible=false end)
  end

  on(CloseBtn.MouseButton1Up, function()
    MainWindow.Visible=false
    OrionLib:MakeNotification({Name="Interface Hidden", Content=(UserInputService.TouchEnabled and "Tap ≡ to reopen" or "Press RightShift to reopen"), Time=5})
    if ReopenChip then ReopenChip.Visible=true end
    cfg.CloseCallback()
  end)
  on(UserInputService.InputBegan, function(i)
    if i.KeyCode==Enum.KeyCode.RightShift and not MainWindow.Visible then
      MainWindow.Visible=true; if ReopenChip then ReopenChip.Visible=false end
    end
  end)
  on(MinimizeBtn.MouseButton1Up, function()
    local minimized = (MainWindow.Size.Y.Offset <= 50+1)
    if minimized then
      TweenService:Create(MainWindow, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size=UDim2.new(0,615,0,344)}):Play()
      MinimizeBtn.Ico.Image = "rbxassetid://7072719338"; task.wait(.02)
      MainWindow.ClipsDescendants=false; LeftPanel.Visible=true; TopLine.Visible=true
    else
      MainWindow.ClipsDescendants=true; TopLine.Visible=false; MinimizeBtn.Ico.Image = "rbxassetid://7072720870"
      TweenService:Create(MainWindow, TweenInfo.new(0.5, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {Size=UDim2.new(0, TitleLabel.TextBounds.X + 140, 0, 50)}):Play()
      task.wait(0.1); LeftPanel.Visible=false
    end
  end)

  -- Optional intro
  local function Intro()
    MainWindow.Visible=false
    local logo = Create("ImageLabel",{Image=cfg.IntroIcon, BackgroundTransparency=1, AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,0,0.4,0), Size=UDim2.new(0,28,0,28), ImageColor3=Color3.new(1,1,1), ImageTransparency=1, Parent=Orion})
    local text = Create("TextLabel",{Text=cfg.IntroText, TextSize=14, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), AnchorPoint=Vector2.new(0.5,0.5), Position=UDim2.new(0.5,19,0.5,0), TextTransparency=1, Parent=Orion, TextColor3=Color3.new(1,1,1), TextXAlignment=Enum.TextXAlignment.Center})
    TweenService:Create(logo, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {ImageTransparency=0, Position=UDim2.new(0.5,0,0.5,0)}):Play()
    task.wait(0.8)
    TweenService:Create(logo, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position=UDim2.new(0.5, -(text.TextBounds.X/2), 0.5, 0)}):Play()
    task.wait(0.3)
    TweenService:Create(text, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency=0}):Play()
    task.wait(2)
    TweenService:Create(text, TweenInfo.new(.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {TextTransparency=1}):Play()
    MainWindow.Visible=true; logo:Destroy(); text:Destroy()
  end
  if cfg.IntroEnabled then Intro() end

  -- ================= Tabs & Controls ======================================
  local FirstTab = true

  local function MakeTab(tabCfg)
    tabCfg = tabCfg or {}; tabCfg.Name = tabCfg.Name or "Tab"; tabCfg.Icon = tabCfg.Icon or ""; tabCfg.PremiumOnly = tabCfg.PremiumOnly or false
    local TabBtn = Create("TextButton",{Text="",AutoButtonColor=false,BackgroundTransparency=1, Size=UDim2.new(1,0,0,30), Parent=TabHolder},{
      themify(Create("ImageLabel",{Image=tabCfg.Icon, BackgroundTransparency=1, AnchorPoint=Vector2.new(0,0.5), Size=UDim2.new(0,18,0,18), Position=UDim2.new(0,10,0.5,0), ImageTransparency=0.4, Name="Ico"}),"Text"),
      themify(Create("TextLabel",{Text=tabCfg.Name, TextSize=14, Font=Enum.Font.GothamSemibold, BackgroundTransparency=1, Size=UDim2.new(1,-35,1,0), Position=UDim2.new(0,35,0,0), TextTransparency=0.4, Name="Title"}),"Text")
    })
    if GetIcon(tabCfg.Icon) then TabBtn.Ico.Image = GetIcon(tabCfg.Icon) end

    local Container = themify(Create("ScrollingFrame",{BackgroundTransparency=0.9, ScrollBarThickness=5, Size=UDim2.new(1,-150,1,-50), Position=UDim2.new(0,150,0,50), Visible=false, Name="ItemContainer", Parent=MainWindow},{
      E("List",0,6), E("Padding",15,10,10,15)
    }), "Divider")
    on(Container.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
      Container.CanvasSize = UDim2.new(0,0,0, Container.UIListLayout.AbsoluteContentSize.Y + 30)
    end)

    -- Neutral lock overlay
    local LockOverlay = themify(Create("Frame",{BackgroundColor3=Color3.new(0,0,0), BackgroundTransparency=0.35, Size=Container.Size, Position=Container.Position, Visible=false, Name="LockOverlay", Parent=MainWindow},{
      themify(Create("TextLabel",{Text="Locked", TextSize=16, Font=Enum.Font.GothamBlack, BackgroundTransparency=1, Size=UDim2.new(1,-40,0,18), Position=UDim2.new(0,20,0,18)}),"Text"),
      themify(Create("TextLabel",{Text="This feature is currently restricted.", TextSize=14, Font=Enum.Font.Gotham, BackgroundTransparency=1, Size=UDim2.new(1,-40,0,16), Position=UDim2.new(0,20,0,42), Name="Reason", TextWrapped=true}),"TextDark")
    }), "Second")
    LockOverlay.ZIndex = 10; LockOverlay.ClipsDescendants = true

    if FirstTab then
      FirstTab=false
      TabBtn.Ico.ImageTransparency=0; TabBtn.Title.TextTransparency=0; TabBtn.Title.Font=Enum.Font.GothamBlack; Container.Visible=true
    end

    on(TabBtn.MouseButton1Click, function()
      for _, b in ipairs(TabHolder:GetChildren()) do
        if b:IsA("TextButton") then
          b.Title.Font = Enum.Font.GothamSemibold
          TweenService:Create(b.Ico, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency=0.4}):Play()
          TweenService:Create(b.Title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency=0.4}):Play()
        end
      end
      for _, c in ipairs(MainWindow:GetChildren()) do
        if c.Name=="ItemContainer" then c.Visible=false end
      end
      TweenService:Create(TabBtn.Ico, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {ImageTransparency=0}):Play()
      TweenService:Create(TabBtn.Title, TweenInfo.new(0.25, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {TextTransparency=0}):Play()
      TabBtn.Title.Font=Enum.Font.GothamBlack; Container.Visible=true
      LockOverlay.Position=Container.Position; LockOverlay.Size=Container.Size
    end)

    -- Control builders
    local Controls = {}

    function Controls:AddLabel(text)
      local f = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,30), BackgroundTransparency=0.7, Parent=Container},{
        themify(Create("TextLabel",{Text=text or "", TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,12,0,0), Name="Content"}),"Text"),
        themify(E("Stroke"),"Stroke")
      }), "Second")
      local api = {}; function api:Set(t) f.Content.Text=t end; return api
    end

    function Controls:AddParagraph(title, content)
      title=title or "Text"; content=content or "Content"
      local f = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,30), BackgroundTransparency=0.7, Parent=Container},{
        themify(Create("TextLabel",{Text=title, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,0,14), Position=UDim2.new(0,12,0,10), Name="Title"}),"Text"),
        themify(Create("TextLabel",{Text="", TextSize=13, Font=Enum.Font.GothamSemibold, BackgroundTransparency=1, Size=UDim2.new(1,-24,0,0), Position=UDim2.new(0,12,0,26), Name="Content", TextWrapped=true}),"TextDark"),
        themify(E("Stroke"),"Stroke")
      }), "Second")
      on(f.Content:GetPropertyChangedSignal("Text"), function()
        f.Content.Size = UDim2.new(1,-24,0, f.Content.TextBounds.Y)
        f.Size         = UDim2.new(1,0,0, f.Content.TextBounds.Y + 35)
      end)
      f.Content.Text = content
      local api = {}; function api:Set(t) f.Content.Text=t end; return api
    end

    function Controls:AddButton(cfgb)
      cfgb = cfgb or {}; cfgb.Name = cfgb.Name or "Button"; cfgb.Callback = cfgb.Callback or function() end; cfgb.Icon = cfgb.Icon or "rbxassetid://87081332654823"
      local Click = E("Button")
      local frame = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,33), Parent=Container},{
        themify(Create("TextLabel",{Text=cfgb.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,12,0,0), Name="Content"}),"Text"),
        themify(Create("ImageLabel",{Image=cfgb.Icon, BackgroundTransparency=1, Size=UDim2.new(0,20,0,20), Position=UDim2.new(1,-30,0,7)}),"TextDark"),
        themify(E("Stroke"),"Stroke"), Click
      }), "Second")
      on(Click.MouseEnter, function()
        TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {BackgroundColor3=Color3.fromRGB(33,36,33)}):Play()
      end)
      on(Click.MouseLeave, function()
        TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {BackgroundColor3=OrionLib.Themes.Default.Second}):Play()
      end)
      on(Click.MouseButton1Up, function()
        TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {BackgroundColor3=Color3.fromRGB(33,36,33)}):Play()
        task.spawn(cfgb.Callback)
      end)
      local api = {}; function api:Set(t) frame.Content.Text=t end; return api
    end

    function Controls:AddToggle(cfgt)
      cfgt = cfgt or {}; cfgt.Name = cfgt.Name or "Toggle"; cfgt.Default = cfgt.Default or false; cfgt.Callback = cfgt.Callback or function() end; cfgt.Color = cfgt.Color or Color3.fromRGB(9,99,195); cfgt.Flag = cfgt.Flag or nil; cfgt.Save = cfgt.Save or false
      local T = {Value=cfgt.Default, Save=cfgt.Save, Type="Toggle"}
      local Click = E("Button")
      local box = Create("Frame",{BackgroundColor3=cfgt.Color, Size=UDim2.new(0,24,0,24), Position=UDim2.new(1,-24,0.5,0), AnchorPoint=Vector2.new(0.5,0.5)},{
        Create("UIStroke",{Color=cfgt.Color, Transparency=0.5, Name="Stroke"}),
        Create("ImageLabel",{Image="rbxassetid://3944680095", BackgroundTransparency=1, Size=UDim2.new(0,20,0,20), Position=UDim2.new(0.5,0,0.5,0), AnchorPoint=Vector2.new(0.5,0.5), ImageColor3=Color3.new(1,1,1), Name="Ico"})
      })
      local frame = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,38), Parent=Container},{
        themify(Create("TextLabel",{Text=cfgt.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,12,0,0), Name="Content"}),"Text"),
        themify(E("Stroke"),"Stroke"), box, Click
      }), "Second")
      function T:Set(v)
        T.Value = v
        TweenService:Create(box, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {BackgroundColor3 = (T.Value and cfgt.Color or OrionLib.Themes.Default.Divider)}):Play()
        TweenService:Create(box.Stroke, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {Color = (T.Value and cfgt.Color or OrionLib-Themes and OrionLib.Themes.Default.Stroke) or OrionLib.Themes.Default.Stroke}):Play()
        TweenService:Create(box.Ico, TweenInfo.new(0.3, Enum.EasingStyle.Quint), {ImageTransparency = (T.Value and 0 or 1), Size = (T.Value and UDim2.new(0,20,0,20) or UDim2.new(0,8,0,8))}):Play()
        cfgt.Callback(T.Value)
      end
      T:Set(T.Value)
      on(Click.MouseButton1Up, function() SaveCfg(game.GameId); T:Set(not T.Value) end)
      if cfgt.Flag then OrionLib.Flags[cfgt.Flag] = T end
      return T
    end

    function Controls:AddSlider(cfgs)
      cfgs = cfgs or {}; cfgs.Name = cfgs.Name or "Slider"; cfgs.Min=cfgs.Min or 0; cfgs.Max=cfgs.Max or 100; cfgs.Increment=cfgs.Increment or 1; cfgs.Default=cfgs.Default or 50; cfgs.Callback=cfgs.Callback or function() end; cfgs.ValueName=cfgs.ValueName or ""; cfgs.Color=cfgs.Color or Color3.fromRGB(9,149,98); cfgs.Flag=cfgs.Flag or nil; cfgs.Save=cfgs.Save or false
      local S = {Value=cfgs.Default, Save=cfgs.Save, Type="Slider"}
      local drag = Create("Frame",{BackgroundColor3=cfgs.Color, BackgroundTransparency=0.3, Size=UDim2.new(0,0,1,0), ClipsDescendants=true},{
        themify(Create("TextLabel",{Text="value", TextSize=13, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,0,14), Position=UDim2.new(0,12,0,6), Name="Value"}),"Text")
      })
      local bar = Create("Frame",{BackgroundColor3=cfgs.Color, BackgroundTransparency=0.9, Size=UDim2.new(1,-24,0,26), Position=UDim2.new(0,12,0,30)},{
        Create("UIStroke",{Color=cfgs.Color}),
        themify(Create("TextLabel",{Text="value", TextSize=13, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,0,14), Position=UDim2.new(0,12,0,6), Name="Value", TextTransparency=0.8}),"Text"),
        drag
      })
      local frame = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,65), Parent=Container},{
        themify(Create("TextLabel",{Text=cfgs.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,0,14), Position=UDim2.new(0,12,0,10), Name="Content"}),"Text"),
        themify(E("Stroke"),"Stroke"), bar
      }), "Second")

      local dragging=false
      local function set(v)
        S.Value = math.clamp(Round(v, cfgs.Increment), cfgs.Min, cfgs.Max)
        TweenService:Create(drag, TweenInfo.new(.15, Enum.EasingStyle.Quad), {Size=UDim2.fromScale((S.Value - cfgs.Min)/(cfgs.Max - cfgs.Min), 1)}):Play()
        local txt = tostring(S.Value)..(cfgs.ValueName~="" and (" "..cfgs.ValueName) or "")
        bar.Value.Text = txt; drag.Value.Text = txt; cfgs.Callback(S.Value)
      end
      bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=true end end)
      bar.InputEnded:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then dragging=false end end)
      UserInputService.InputChanged:Connect(function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
          local s = math.clamp((i.Position.X - bar.AbsolutePosition.X)/bar.AbsoluteSize.X, 0,1)
          set(cfgs.Min + ((cfgs.Max - cfgs.Min)*s)); SaveCfg(game.GameId)
        end
      end)
      set(S.Value); if cfgs.Flag then OrionLib.Flags[cfgs.Flag]=S end; return S
    end

    function Controls:AddDropdown(cfgd)
      cfgd = cfgd or {}; cfgd.Name=cfgd.Name or "Dropdown"; cfgd.Options=cfgd.Options or {}; cfgd.Default=cfgd.Default or ""; cfgd.Callback=cfgd.Callback or function() end; cfgd.Flag=cfgd.Flag or nil; cfgd.Save=cfgd.Save or false
      local D = {Value=cfgd.Default, Options=cfgd.Options, Buttons={}, Toggled=false, Type="Dropdown", Save=cfgd.Save}
      if not table.find(D.Options, D.Value) then D.Value = "..." end
      local list = E("List")
      local container = themify(Create("ScrollingFrame",{BackgroundTransparency=0.9, ScrollBarThickness=4, Position=UDim2.new(0,0,0,38), Size=UDim2.new(1,0,1,-38), ClipsDescendants=true}, {list}), "Divider")
      local Click = E("Button")
      local frame = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,38), Parent=Container, ClipsDescendants=true},{
        container,
        Create("Frame",{BackgroundTransparency=1, Size=UDim2.new(1,0,0,38), Name="F"},{
          themify(Create("TextLabel",{Text=cfgd.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,12,0,0), Name="Content"}),"Text"),
          themify(Create("ImageLabel",{Image="rbxassetid://7072706796", BackgroundTransparency=1, Size=UDim2.new(0,20,0,20), AnchorPoint=Vector2.new(0,0.5), Position=UDim2.new(1,-30,0.5,0), Name="Ico", ImageColor3=Color3.fromRGB(240,240,240)}),"TextDark"),
          themify(Create("TextLabel",{Text="Selected", TextSize=13, Font=Enum.Font.Gotham, BackgroundTransparency=1, Size=UDim2.new(1,-40,1,0), Name="Selected", TextXAlignment=Enum.TextXAlignment.Right}),"TextDark"),
          themify(Create("Frame",{Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1), Name="Line", Visible=false}),"Stroke"),
          Click
        }),
        themify(E("Stroke"),"Stroke"), E("Corner")
      }), "Second")
      on(list:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        container.CanvasSize = UDim2.new(0,0,0, list.AbsoluteContentSize.Y)
      end)
      local function addOptions(opts)
        for _,opt in ipairs(opts) do
          local btn = themify(Create("TextButton",{Text="",BackgroundTransparency=1, Size=UDim2.new(1,0,0,28)},{
            E("Corner",0,6),
            themify(Create("TextLabel",{Text=opt, TextSize=13, Font=Enum.Font.Gotham, BackgroundTransparency=1, Position=UDim2.new(0,8,0,0), Size=UDim2.new(1,-8,1,0), Name="Title", TextTransparency=0.4}),"Text")
          }), "Divider")
          btn.Parent = container
          btn.MouseButton1Click:Connect(function() D:Set(opt); SaveCfg(game.GameId) end)
          D.Buttons[opt] = btn
        end
      end
      function D:Refresh(opts, purge)
        if purge then for _,b in pairs(D.Buttons) do b:Destroy() end; D.Options = {}; D.Buttons = {} end
        D.Options = opts; addOptions(D.Options)
      end
      function D:Set(val)
        if not table.find(D.Options, val) then
          D.Value="..."; frame.F.Selected.Text=D.Value
          for _,b in pairs(D.Buttons) do TweenService:Create(b, TweenInfo.new(.15, Enum.EasingStyle.Quad), {BackgroundTransparency=1}):Play(); TweenService:Create(b.Title, TweenInfo.new(.15, Enum.EasingStyle.Quad), {TextTransparency=0.4}):Play() end
          return
        end
        D.Value = val; frame.F.Selected.Text = D.Value
        for _,b in pairs(D.Buttons) do TweenService:Create(b, TweenInfo.new(.15, Enum.EasingStyle.Quad), {BackgroundTransparency=1}):Play(); TweenService:Create(b.Title, TweenInfo.new(.15, Enum.EasingStyle.Quad), {TextTransparency=0.4}):Play() end
        local b = D.Buttons[val]; if b then TweenService:Create(b, TweenInfo.new(.15, Enum.EasingStyle.Quad), {BackgroundTransparency=0}):Play(); TweenService:Create(b.Title, TweenInfo.new(.15, Enum.EasingStyle.Quad), {TextTransparency=0}):Play() end
        cfgd.Callback(D.Value)
      end
      on(Click.MouseButton1Click, function()
        D.Toggled = not D.Toggled; frame.F.Line.Visible = D.Toggled
        TweenService:Create(frame.F.Ico, TweenInfo.new(.15, Enum.EasingStyle.Quad), {Rotation = D.Toggled and 180 or 0}):Play()
        local targetH = (#D.Options > 5) and (38 + (5 * 28)) or (list.AbsoluteContentSize.Y + 38)
        TweenService:Create(frame, TweenInfo.new(.15, Enum.EasingStyle.Quad), {Size = D.Toggled and UDim2.new(1,0,0,targetH) or UDim2.new(1,0,0,38)}):Play()
      end)
      D:Refresh(D.Options, false); D:Set(D.Value)
      if cfgd.Flag then OrionLib.Flags[cfgd.Flag] = D end
      return D
    end

    function Controls:AddBind(cfgb)
      cfgb = cfgb or {}; cfgb.Name=cfgb.Name or "Bind"; cfgb.Default=cfgb.Default or Enum.KeyCode.Unknown; cfgb.Hold=cfgb.Hold or false; cfgb.Callback=cfgb.Callback or function() end; cfgb.Flag=cfgb.Flag or nil; cfgb.Save=cfgb.Save or false
      local B = {Value=nil, Binding=false, Type="Bind", Save=cfgb.Save}
      local Click = E("Button")
      local box = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(0,24,0,24), Position=UDim2.new(1,-12,0.5,0), AnchorPoint=Vector2.new(1,0.5)},{
        themify(E("Stroke"),"Stroke"),
        themify(Create("TextLabel",{Text=cfgb.Name, TextSize=14, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,0,1,0), TextXAlignment=Enum.TextXAlignment.Center, Name="Value"}),"Text")
      }), "Main")
      local frame = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,38), Parent=Container},{
        themify(Create("TextLabel",{Text=cfgb.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,12,0,0), Name="Content"}),"Text"),
        themify(E("Stroke"),"Stroke"), box, Click
      }), "Second")
      on(box.Value:GetPropertyChangedSignal("Text"), function()
        TweenService:Create(box, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {Size=UDim2.new(0, box.Value.TextBounds.X + 16, 0, 24)}):Play()
      end)
      on(Click.InputEnded, function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then if B.Binding then return end; B.Binding=true; box.Value.Text="" end end)
      on(UserInputService.InputBegan, function(i)
        if UserInputService:GetFocusedTextBox() then return end
        if (i.KeyCode.Name==B.Value or i.UserInputType.Name==B.Value) and not B.Binding then
          if cfgb.Hold then cfgb.Callback(true) else cfgb.Callback() end
        elseif B.Binding then
          local key
          if i.KeyCode and i.KeyCode ~= Enum.KeyCode.Unknown then key = i.KeyCode end
          if (not key) and (i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.MouseButton2 or i.UserInputType == Enum.UserInputType.MouseButton3) then key = i.UserInputType end
          key = key or B.Value; B:Set(key); SaveCfg(game.GameId)
        end
      end)
      on(UserInputService.InputEnded, function(i)
        if cfgb.Hold and (i.KeyCode.Name==B.Value or i.UserInputType.Name==B.Value) then cfgb.Callback(false) end
      end)
      function B:Set(key) B.Binding=false; B.Value = key or B.Value; B.Value = B.Value and (B.Value.Name or B.Value) or cfgb.Default; box.Value.Text=B.Value end
      B:Set(cfgb.Default); if cfgb.Flag then OrionLib.Flags[cfgb.Flag]=B end; return B
    end

    function Controls:AddTextbox(cfgt)
      cfgt = cfgt or {}; cfgt.Name=cfgt.Name or "Textbox"; cfgt.Default=cfgt.Default or ""; cfgt.TextDisappear=cfgt.TextDisappear or false; cfgt.Callback=cfgt.Callback or function() end
      local Click = E("Button")
      local box = themify(Create("TextBox",{Text="", ClearTextOnFocus=false, BackgroundTransparency=1, TextColor3=Color3.new(1,1,1), PlaceholderColor3=Color3.fromRGB(210,210,210), PlaceholderText="Input", Font=Enum.Font.GothamSemibold, TextXAlignment=Enum.TextXAlignment.Center, TextSize=14}), "Text")
      local container = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(0,24,0,24), Position=UDim2.new(1,-12,0.5,0), AnchorPoint=Vector2.new(1,0.5)},{
        themify(E("Stroke"),"Stroke"), box
      }), "Main")
      local frame = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,38), Parent=Container},{
        themify(Create("TextLabel",{Text=cfgt.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,12,0,0), Name="Content"}),"Text"),
        themify(E("Stroke"),"Stroke"), container, Click
      }), "Second")
      box:GetPropertyChangedSignal("Text"):Connect(function()
        TweenService:Create(container, TweenInfo.new(0.45, Enum.EasingStyle.Quint), {Size=UDim2.new(0, box.TextBounds.X + 16, 0, 24)}):Play()
      end)
      box.FocusLost:Connect(function() cfgt.Callback(box.Text); if cfgt.TextDisappear then box.Text="" end end)
      box.Text = cfgt.Default
      on(Click.MouseButton1Up, function() TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quint), {BackgroundColor3=Color3.fromRGB(33,36,33)}):Play(); box:CaptureFocus() end)
    end

    function Controls:AddColorpicker(cfgc)
      cfgc = cfgc or {}; cfgc.Name=cfgc.Name or "Colorpicker"; cfgc.Default=cfgc.Default or Color3.new(1,1,1); cfgc.Callback=cfgc.Callback or function() end; cfgc.Flag=cfgc.Flag or nil; cfgc.Save=cfgc.Save or false
      local ColorH, ColorS, ColorV = 1,1,1
      local C = {Value=cfgc.Default, Toggled=false, Type="Colorpicker", Save=cfgc.Save}
      local ColorSelection = Create("ImageLabel",{Size=UDim2.new(0,18,0,18), Position=UDim2.new(select(3, Color3.toHSV(C.Value))), ScaleType=Enum.ScaleType.Fit, AnchorPoint=Vector2.new(0.5,0.5), BackgroundTransparency=1, Image="http://www.roblox.com/asset/?id=4805639000"})
      local HueSelection   = Create("ImageLabel",{Size=UDim2.new(0,18,0,18), Position=UDim2.new(0.5,0,1 - select(1, Color3.toHSV(C.Value))), ScaleType=Enum.ScaleType.Fit, AnchorPoint=Vector2.new(0.5,0.5), BackgroundTransparency=1, Image="http://www.roblox.com/asset/?id=4805639000"})
      local ColorArea = Create("ImageLabel",{Size=UDim2.new(1,-25,1,0), Visible=false, Image="rbxassetid://4155801252"},{Create("UICorner",{CornerRadius=UDim.new(0,5)}), ColorSelection})
      local HueArea   = Create("Frame",{Size=UDim2.new(0,20,1,0), Position=UDim2.new(1,-20,0,0), Visible=false},{Create("UIGradient",{Rotation=270, Color=ColorSequence.new{
        ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255,0,4)), ColorSequenceKeypoint.new(0.20, Color3.fromRGB(234,255,0)),
        ColorSequenceKeypoint.new(0.40, Color3.fromRGB(21,255,0)), ColorSequenceKeypoint.new(0.60, Color3.fromRGB(0,255,255)),
        ColorSequenceKeypoint.new(0.80, Color3.fromRGB(0,17,255)), ColorSequenceKeypoint.new(0.90, Color3.fromRGB(255,0,251)),
        ColorSequenceKeypoint.new(1.00, Color3.fromRGB(255,0,4)) }}), Create("UICorner",{CornerRadius=UDim.new(0,5)}), HueSelection})
      local PickerBody = Create("Frame",{BackgroundTransparency=1, Position=UDim2.new(0,0,0,32), Size=UDim2.new(1,0,1,-32), ClipsDescendants=true},{HueArea, ColorArea, Create("UIPadding",{PaddingLeft=UDim.new(0,35),PaddingRight=UDim.new(0,35),PaddingBottom=UDim.new(0,10),PaddingTop=UDim.new(0,17)})})
      local Click = E("Button")
      local Box = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(0,24,0,24), Position=UDim2.new(1,-12,0.5,0), AnchorPoint=Vector2.new(1,0.5)}, {themify(E("Stroke"),"Stroke")}),"Main")
      local Frame = themify(Create("Frame",{BackgroundColor3=Color3.new(1,1,1), Size=UDim2.new(1,0,0,38), Parent=Container},{
        Create("Frame",{BackgroundTransparency=1, Size=UDim2.new(1,0,0,38), Name="F"},{
          themify(Create("TextLabel",{Text=cfgc.Name, TextSize=15, Font=Enum.Font.GothamBold, BackgroundTransparency=1, Size=UDim2.new(1,-12,1,0), Position=UDim2.new(0,12,0,0), Name="Content"}),"Text"),
          Box, Click, themify(Create("Frame",{Size=UDim2.new(1,0,0,1), Position=UDim2.new(0,0,1,-1), Name="Line", Visible=false}),"Stroke")
        }),
        PickerBody, themify(E("Stroke"),"Stroke")
      }), "Second")
      Click.MouseButton1Click:Connect(function()
        C.Toggled = not C.Toggled
        TweenService:Create(Frame, TweenInfo.new(.15, Enum.EasingStyle.Quad), {Size = C.Toggled and UDim2.new(1,0,0,148) or UDim2.new(1,0,0,38)}):Play()
        ColorArea.Visible = C.Toggled; HueArea.Visible = C.Toggled; Frame.F.Line.Visible = C.Toggled
      end)
      local function UpdateColor()
        Box.BackgroundColor3 = Color3.fromHSV(ColorH, ColorS, ColorV)
        ColorArea.BackgroundColor3 = Color3.fromHSV(ColorH, 1, 1)
        C:Set(Box.BackgroundColor3); cfgc.Callback(Box.BackgroundColor3); SaveCfg(game.GameId)
      end
      ColorH = 1 - (math.clamp(HueSelection.AbsolutePosition.Y - HueArea.AbsolutePosition.Y,0,HueArea.AbsoluteSize.Y) / HueArea.AbsoluteSize.Y)
      ColorS = (math.clamp(ColorSelection.AbsolutePosition.X - ColorArea.AbsolutePosition.X,0,ColorArea.AbsoluteSize.X) / ColorArea.AbsoluteSize.X)
      ColorV = 1 - (math.clamp(ColorSelection.AbsolutePosition.Y - ColorArea.AbsolutePosition.Y,0,ColorArea.AbsoluteSize.Y) / ColorArea.AbsoluteSize.Y)

      local activeColor, activeHue = nil, nil
      ColorArea.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
          if activeColor then activeColor:Disconnect() end
          activeColor = UserInputService.InputChanged:Connect(function(ch)
            if ch==i and i.UserInputState~=Enum.UserInputState.End then
              local x = math.clamp((i.Position.X - ColorArea.AbsolutePosition.X)/ColorArea.AbsoluteSize.X,0,1)
              local y = math.clamp((i.Position.Y - ColorArea.AbsolutePosition.Y)/ColorArea.AbsoluteSize.Y,0,1)
              ColorSelection.Position = UDim2.new(x,0,y,0); ColorS=x; ColorV=1-y; UpdateColor()
            end
          end)
        end
      end)
      ColorArea.InputEnded:Connect(function(i) if activeColor then activeColor:Disconnect(); activeColor=nil end end)

      HueArea.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
          if activeHue then activeHue:Disconnect() end
          activeHue = UserInputService.InputChanged:Connect(function(ch)
            if ch==i and i.UserInputState~=Enum.UserInputState.End then
              local y = math.clamp((i.Position.Y - HueArea.AbsolutePosition.Y)/HueArea.AbsoluteSize.Y,0,1)
              HueSelection.Position = UDim2.new(0.5,0,y,0); ColorH=1-y; UpdateColor()
            end
          end)
        end
      end)
      HueArea.InputEnded:Connect(function(i) if activeHue then activeHue:Disconnect(); activeHue=nil end end)

      function C:Set(val) C.Value=val; Box.BackgroundColor3=val; cfgc.Callback(val) end
      C:Set(C.Value); if cfgc.Flag then OrionLib.Flags[cfgc.Flag]=C end; return C
    end

    -- Section builder
    function Controls:AddSection(secCfg)
      secCfg = secCfg or {}; secCfg.Name = secCfg.Name or "Section"
      local section = Create("Frame",{BackgroundTransparency=1, Size=UDim2.new(1,0,0,26), Parent=Container},{
        themify(Create("TextLabel",{Text=secCfg.Name, TextSize=14, Font=Enum.Font.GothamSemibold, BackgroundTransparency=1, Size=UDim2.new(1,-12,0,16), Position=UDim2.new(0,0,0,3)}),"TextDark"),
        Create("Frame",{BackgroundTransparency=1, AnchorPoint=Vector2.new(0,0), Size=UDim2.new(1,0,1,-24), Position=UDim2.new(0,0,0,23), Name="Holder"}, {E("List",0,6)})
      })
      on(section.Holder.UIListLayout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        section.Size = UDim2.new(1,0,0, section.Holder.UIListLayout.AbsoluteContentSize.Y + 31)
        section.Holder.Size = UDim2.new(1,0,0, section.Holder.UIListLayout.AbsoluteContentSize.Y)
      end)
      local SectionAPI = {}
      -- inherit all controls but parent = section.Holder
      for k,v in pairs(Controls) do
        if type(v)=="function" then
          SectionAPI[k] = function(...) return Controls[k](...) end
        end
      end
      return SectionAPI
    end

    -- premium compatibility: show neutral overlay
    if tabCfg.PremiumOnly then LockOverlay.Reason.Text="Restricted section."; LockOverlay.Visible=true end

    function Controls:Lock(reason) LockOverlay.Reason.Text=reason or "Restricted."; LockOverlay.Position=Container.Position; LockOverlay.Size=Container.Size; LockOverlay.Visible=true end
    function Controls:Unlock() LockOverlay.Visible=false end

    return Controls
  end -- MakeTab

  -- Window API wrapper (simplified)
  local API = {}
  function API:MakeTab(c) return MakeTab(c) end
  function API:SetFooter(text, props)
    local footer = LeftPanel:FindFirstChild("Footer", true)
    if footer and footer:IsA("TextLabel") then
      footer.Text = text or ""
      if props and typeof(props)=="table" then
        if props.color then footer.TextColor3 = props.color end
        if props.transparency then footer.TextTransparency = props.transparency end
        if props.size then footer.TextSize = props.size end
      end
      footer.Visible = (footer.Text ~= "")
    end
  end

  return API
end

function OrionLib:Destroy() Orion:Destroy() end

return OrionLib
