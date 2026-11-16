-- DinosPetSkills · Minimap-Button (Dino) & Direkt-Button am Fenster "Wildtierausbildung" (CraftFrame)
local _, ns = ...

local mini, craftBtn

-- ================================================================== Minimap-Button
local function minimapShape()
  if GetMinimapShape then
    local ok, s = pcall(GetMinimapShape)
    if ok and s then return s end
  end
  return "ROUND"
end

local function placeMinimapButton()
  if not mini or not Minimap then return end
  local angle = math.rad((DinosPetSkillsDB and DinosPetSkillsDB.minimap and DinosPetSkillsDB.minimap.angle) or 200)
  local x, y = math.cos(angle), math.sin(angle)
  local w = (Minimap:GetWidth() or 140) / 2 + 8
  local h = (Minimap:GetHeight() or 140) / 2 + 8
  if minimapShape() == "SQUARE" then
    local m = math.max(math.abs(x), math.abs(y))
    x, y = (x / m) * (w - 2), (y / m) * (h - 2)
  else
    x, y = x * w, y * h
  end
  mini:ClearAllPoints()
  mini:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local function showMinimapTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:SetText("Dino's Pet-Skills", 1, 1, 1)
  GameTooltip:AddLine("by X4rinia und Dino", 1, 0.82, 0)
  GameTooltip:AddLine("Zusatz Addon für Bestinary Forever", 0.8, 0.8, 0.8)
  local l, t = ns.Progress()
  local pct = t > 0 and math.floor(l * 100 / t) or 0
  GameTooltip:AddLine(("%d / %d Ränge dauerhaft erlernt (%d%%)"):format(l, t, pct), 0.45, 0.9, 0.45)
  if ns.activePetName then
    GameTooltip:AddLine("Aktuelles Pet: " .. ns.CYAN .. ns.activePetName .. "|r", 0.85, 0.85, 0.85)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Linksklick", "Gesamtliste öffnen / schließen", 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine("Rechtsklick", "Wildtierausbildung neu einlesen", 1, 0.82, 0, 1, 1, 1)
  GameTooltip:AddDoubleLine("Gedrückt halten & ziehen", "Minimap-Button verschieben", 1, 0.82, 0, 1, 1, 1)
  GameTooltip:Show()
end

function ns.UpdateMinimapTooltip()
  if mini and GameTooltip:IsOwned(mini) then showMinimapTooltip(mini) end
end

function ns.UpdateMinimapButton()
  if not mini then return end
  if DinosPetSkillsDB and DinosPetSkillsDB.minimap and DinosPetSkillsDB.minimap.hide then
    mini:Hide()
  else
    mini:Show()
  end
end

function ns.SetupMinimapButton()
  if mini or not Minimap then return end
  local b = CreateFrame("Button", "DinosPetSkillsMinimapButton", Minimap)
  mini = b
  b:SetSize(32, 32)
  b:SetFrameStrata("MEDIUM")
  b:SetFrameLevel(8)
  b:EnableMouse(true)
  b:SetMovable(true)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton", "RightButton")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(22, 22)
  bg:SetPoint("CENTER")

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(ns.DINO_ICON)
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER")
  icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  b.icon = icon
  pcall(function()
    local m = b:CreateMaskTexture()
    m:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    m:SetAllPoints(icon)
    icon:AddMaskTexture(m)
  end)

  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(54, 54)
  border:SetPoint("TOPLEFT")
  b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, -1) end)
  b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 0) end)
  b:SetScript("OnClick", function(self, button)
    if self.dragging then return end
    if button == "RightButton" then
      ns.ScanCraft()
      ns.ScanActivePet()
      ns.Refresh()
      ns.Print("Aktueller Stand eingelesen.")
    else
      ns.Toggle()
    end
  end)
  b:SetScript("OnDragStart", function(self)
    self.dragging = true
    GameTooltip:Hide()
    self:SetScript("OnUpdate", function()
      local mx, my = Minimap:GetCenter()
      local px, py = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      px, py = px / scale, py / scale
      DinosPetSkillsDB.minimap.angle = math.deg(math.atan2(py - my, px - mx)) % 360
      placeMinimapButton()
    end)
  end)
  b:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    ns.After(0.05, function() self.dragging = false end)
  end)
  b:SetScript("OnEnter", function(self)
    if not self.dragging then showMinimapTooltip(self) end
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)

  placeMinimapButton()
  ns.UpdateMinimapButton()
end

-- Addon-Abteil neben der Minimap (falls der Client es hat)
function DinosPetSkills_OnCompartmentClick(_, button)
  if button == "RightButton" then
    ns.ScanCraft(); ns.ScanActivePet(); ns.Refresh()
  else
    ns.Toggle()
  end
end
function DinosPetSkills_OnCompartmentEnter(_, owner)
  showMinimapTooltip(owner or UIParent)
end
function DinosPetSkills_OnCompartmentLeave() GameTooltip:Hide() end

-- ================================================================== Direkt-Button an der "Wildtierausbildung"
function ns.UpdateCraftButton()
  if not craftBtn then return end
  if ns.IsPetTrainingCraft() then craftBtn:Show() else craftBtn:Hide() end
end

function ns.SetupCraftButton()
  if craftBtn or not CraftFrame then return end
  local b = CreateFrame("Button", "DinosPetSkillsCraftButton", CraftFrame, "UIPanelButtonTemplate")
  craftBtn = b
  b:SetSize(134, 20)
  b:SetPoint("TOPRIGHT", CraftFrame, "TOPRIGHT", -42, -13)
  b:SetFrameLevel((CraftFrame:GetFrameLevel() or 1) + 10)

  local ico = b:CreateTexture(nil, "ARTWORK")
  ico:SetSize(14, 14)
  ico:SetPoint("LEFT", 6, 0)
  ico:SetTexture(ns.DINO_ICON)
  ico:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b:SetText("   Dino's Pet-Skills")

  b:SetScript("OnClick", function()
    ns.ScanCraft()
    ns.ScanActivePet()
    ns.Toggle()
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Dino's Pet-Skills", 1, 1, 1)
    local l, t = ns.Progress()
    GameTooltip:AddLine(("%d / %d Ränge dauerhaft gespeichert"):format(l, t), 0.45, 0.9, 0.45)
    GameTooltip:AddLine("Zeigt alle je von deinem Jäger gelernten Fähigkeiten & Ränge – auch die, die dein aktuelles Pet nicht kann.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", GameTooltip_Hide)

  CraftFrame:HookScript("OnShow", function()
    ns.After(0.05, ns.UpdateCraftButton)
  end)
  ns.UpdateCraftButton()
end
