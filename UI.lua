-- DinosPetSkills · Das Gesamt-Übersichtsfenster "Dino's Pet-Skills" (reine Sammlung + Direkt-Button zu Forever Bestiary)
local _, ns = ...

local W, H = 580, 520
local ROW_H = 20
local LIST_TOP, LIST_BOTTOM = 150, 42
local NUM_ROWS = math.floor((H - LIST_TOP - LIST_BOTTOM - 8) / ROW_H)

local frame, scroll, rowsUI, progress, progressText, petLine, footer, searchBox, bCollapse, bBestiary
local filterButtons = {}
local fontButtons = {}
local displayRows = {}
local expandedSkill = {} -- [Schlüssel] = true: Fähigkeit aufgeklappt (Standard: IMMER alle zugeklappt!)
ns.searchText = ""

local FONT_SIZES = { [1] = 10, [2] = 12, [3] = 14 }

local function applyFontSize()
  local idx = (DinosPetSkillsDB and DinosPetSkillsDB.ui and DinosPetSkillsDB.ui.fontSize) or 2
  local sz = FONT_SIZES[idx] or 12
  local face, _, flags = GameFontHighlightSmall:GetFont()
  if not face then return end
  for _, b in ipairs(rowsUI or {}) do
    b.left:SetFont(face, sz, flags)
    b.right:SetFont(face, sz, flags)
  end
  if petLine then petLine:SetFont(face, sz, flags) end
  if progressText then progressText:SetFont(face, sz, flags) end
  for k, btn in pairs(fontButtons) do
    if k == idx then btn:LockHighlight() else btn:UnlockHighlight() end
  end
end

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

-- ------------------------------------------------------------------ Hilfen
local function isSharedSkill(rec)
  return rec.kind == "general" or rec.kind == "common"
end

local function famList(rec, max)
  if rec.key == "Cower" then
    return "|cff66ddff[Alle Pets]|r"
  elseif rec.kind == "common" then
    return "|cff66ddff[Fast alle Pets · " .. #(rec.fams or {}) .. " Familien]|r"
  end
  local names = {}
  for i, slug in ipairs(rec.fams) do
    if i > (max or 3) then names[#names + 1] = "..." break end
    names[#names + 1] = ns.FamilyName(slug)
  end
  if #names == 0 then return "" end
  return table.concat(names, ", ")
end

local function famListFull(rec)
  if rec.key == "Cower" then return "Alle Pet-Familien" end
  local names = {}
  for _, slug in ipairs(rec.fams or {}) do
    names[#names + 1] = ns.FamilyName(slug)
  end
  return table.concat(names, ", ")
end

local function skillMatches(rec, q)
  for _, k in ipairs({ "en", "de", "es", "fr" }) do
    if rec[k] and ns.norm(rec[k]):find(q, 1, true) then return true end
  end
  for _, slug in ipairs(rec.fams or {}) do
    if ns.norm(ns.FamilyName(slug)):find(q, 1, true) then return true end
  end
  return ns.norm(ns.SkillName(rec)):find(q, 1, true) ~= nil
end

local function petHint()
  return ns.CYAN .. "[Aktuelles Pet: " .. tostring(ns.activePetName) .. "]|r"
end

local function makeButton(parent, text, w)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  return b
end

local function openForeverBestiary(query)
  local cmd = SlashCmdList and SlashCmdList["FBPETHUNTER"]
  if cmd then
    pcall(cmd, query or "")
  else
    ns.Print("Forever Bestiary (Pet Hunter) ist nicht geladen.")
  end
end

-- ------------------------------------------------------------------ Zeilen aufbauen (mit Abschnitts-Überschriften)
local function buildRows()
  wipe(displayRows)
  local db = DinosPetSkillsDB
  local mode = db.ui.filter or "all"
  local q = ns.norm(ns.searchText or "")
  local addedSharedHeader, addedSpecialHeader = false, false

  for _, rec in ipairs(ns.skills) do
    if mode ~= "pet" or ns.PetCanUse(rec) then
      if q == "" or skillMatches(rec, q) then
        local rankRows = {}
        for _, r in ipairs(ns.RankList(rec)) do
          local learned = ns.IsLearned(rec.key, r)
          if (mode == "all") or (mode == "pet") or (mode == "learned" and learned) or (mode == "missing" and not learned) then
            rankRows[#rankRows + 1] = { kind = "rank", rec = rec, r = r, learned = learned }
          end
        end
        if #rankRows > 0 then
          if isSharedSkill(rec) then
            if not addedSharedHeader then
              addedSharedHeader = true
              displayRows[#displayRows + 1] = {
                kind = "header",
                title = "|cff66ddffAllgemeine Fähigkeiten (für fast alle Pets)|r",
              }
            end
          else
            if not addedSpecialHeader then
              addedSpecialHeader = true
              displayRows[#displayRows + 1] = {
                kind = "header",
                title = "|cffffd100Familien-Spezialfähigkeiten (je nach Tierart)|r",
              }
            end
          end

          displayRows[#displayRows + 1] = { kind = "skill", rec = rec }
          if q ~= "" or expandedSkill[rec.key] then
            for _, rr in ipairs(rankRows) do
              displayRows[#displayRows + 1] = rr
            end
          end
        end
      end
    end
  end
end

-- ------------------------------------------------------------------ Tooltips
local function rankTooltip(owner, row)
  local rec, r = row.rec, row.r
  local rk = rec.ranks[r] or {}
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(ns.SkillName(rec) .. " " .. ns.GREY .. "(Rang " .. r .. ")|r")
  local desc = rk[ns.langKey] or rk.de or rk.en
  if desc then GameTooltip:AddLine(desc, 1, 1, 1, true) end
  if rk.l then GameTooltip:AddLine("Benötigt Pet-Stufe " .. rk.l, 0.8, 0.8, 0.8) end
  GameTooltip:AddLine(" ")
  if ns.IsLearned(rec.key, r) then
    GameTooltip:AddLine(ns.CHECK .. " In deiner Sammlung (dauerhaft erlernt)", 0, 1, 0)
  else
    GameTooltip:AddLine(ns.CROSS .. " Noch nicht in deiner Sammlung", 1, 0.27, 0.27)
  end
  if ns.PetHas(rec.key, r) then
    GameTooltip:AddLine("Dein aktuelles Pet (" .. tostring(ns.activePetName) .. ") beherrscht diesen Rang.", 0, 0.8, 1, true)
  end
  GameTooltip:Show()
end

-- ------------------------------------------------------------------ Hauptliste rendern
local function renderRow(btn, row)
  btn.row = row
  btn.icon:Hide(); btn.toggle:Hide()
  btn.left:ClearAllPoints(); btn.right:SetText("")
  btn.bg:Hide()
  if row.kind == "header" then
    btn.bg:SetColorTexture(0.15, 0.25, 0.35, 0.35)
    btn.bg:Show()
    btn.left:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btn.left:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.left:SetText(row.title)
  elseif row.kind == "skill" then
    local rec = row.rec
    if isSharedSkill(rec) then
      btn.bg:SetColorTexture(0.15, 0.65, 1, 0.14)
    else
      btn.bg:SetColorTexture(1, 0.82, 0, 0.08)
    end
    btn.bg:Show()
    btn.icon:SetTexture(ns.IconPath(rec.icon)); btn.icon:Show()
    local isOpen = expandedSkill[rec.key]
    btn.toggle:SetTexture(isOpen and "Interface\\Buttons\\UI-MinusButton-Up" or "Interface\\Buttons\\UI-PlusButton-Up")
    btn.toggle:Show()
    btn.left:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
    btn.left:SetPoint("RIGHT", btn.right, "LEFT", -8, 0)
    local maxLearned = 0
    for _, r in ipairs(ns.RankList(rec)) do
      if ns.IsLearned(rec.key, r) and r > maxLearned then maxLearned = r end
    end
    local tagStr = ""
    if maxLearned == 1 then
      tagStr = "  " .. ns.CHECK_SMALL .. " " .. ns.GREEN .. "Rang 1|r"
    elseif maxLearned > 1 then
      tagStr = "  " .. ns.CHECK_SMALL .. " " .. ns.GREEN .. "Rang 1–" .. maxLearned .. "|r"
    end
    local fam = famList(rec, 2)
    btn.left:SetText(ns.GOLD .. ns.SkillName(rec) .. "|r" .. (fam ~= "" and ("  " .. ns.GREY .. fam .. "|r") or "") .. tagStr)
    local n, total = ns.LearnedCount(rec), #ns.RankList(rec)
    local col = (n == total and total > 0) and ns.GREEN or (n > 0 and "|cffffffff" or ns.GREY)
    btn.right:SetText(col .. n .. " / " .. total .. "|r" .. (ns.PetHas(rec.key) and ("  " .. ns.CYAN .. "[Pet]|r") or ""))
  elseif row.kind == "rank" then
    local rec, r = row.rec, row.r
    local rk = rec.ranks[r] or {}
    btn.left:SetPoint("LEFT", btn, "LEFT", 32, 0)
    btn.left:SetPoint("RIGHT", btn.right, "LEFT", -8, 0)
    local status = row.learned and (ns.CHECK .. " " .. ns.GREEN .. "Rang " .. r .. " · Erlernt|r")
      or (ns.CROSS .. " " .. ns.RED .. "Rang " .. r .. " · Fehlt|r")
    local pet = ns.PetHas(rec.key, r) and ("  " .. petHint()) or ""
    btn.left:SetText(status .. pet)
    btn.right:SetText(rk.l and (ns.GREY .. "ab Pet-Stufe " .. rk.l .. "|r") or "")
  end
  btn:Show()
end

local function updateList()
  if not scroll then return end
  FauxScrollFrame_Update(scroll, #displayRows, NUM_ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)
  for i = 1, NUM_ROWS do
    local row = displayRows[offset + i]
    if row then renderRow(rowsUI[i], row) else rowsUI[i]:Hide(); rowsUI[i].row = nil end
  end
end

local function onRowClick(btn)
  local row = btn.row
  if not row then return end
  if row.kind == "skill" then
    expandedSkill[row.rec.key] = (not expandedSkill[row.rec.key]) or nil
    if bCollapse then
      bCollapse:SetText(next(expandedSkill) and "Alle zuklappen" or "Alle aufklappen")
    end
    buildRows()
    updateList()
  end
end

local function onRowEnter(btn)
  local row = btn.row
  if not row then return end
  if row.kind == "rank" then
    rankTooltip(btn, row)
  elseif row.kind == "skill" then
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.SkillName(row.rec))
    if isSharedSkill(row.rec) then
      GameTooltip:AddLine("Allgemeine Pet-Fähigkeit (für mehrere Tierfamilien)", 0.4, 0.87, 1, true)
    end
    local fam = famListFull(row.rec)
    if fam ~= "" then GameTooltip:AddLine("Familien: " .. fam, 0.85, 0.85, 0.85, true) end
    GameTooltip:AddLine(("%d von %d Rängen dauerhaft erlernt"):format(ns.LearnedCount(row.rec), #ns.RankList(row.rec)), 1, 1, 1)
    GameTooltip:AddLine("Klicken: Ränge auf-/zuklappen", 0.5, 0.5, 0.5)
    GameTooltip:Show()
  end
end

-- ------------------------------------------------------------------ Kopfbereich
local function updateHeader()
  local l, t = ns.Progress()
  progress:SetMinMaxValues(0, math.max(t, 1))
  progress:SetValue(l)
  local pct = t > 0 and math.floor(l * 100 / t) or 0
  progressText:SetText(("%d / %d Ränge dauerhaft erlernt  (%d%%)"):format(l, t, pct))
  if ns.activePetName then
    petLine:SetText(("Aktuelles Pet: %s%s|r %s(%s)|r"):format(ns.CYAN, ns.activePetName,
      ns.GREY, ns.activePetFamily and ns.FamilyName(ns.activePetFamily) or (UnitCreatureFamily and UnitCreatureFamily("pet") or "?")))
  else
    petLine:SetText(ns.GREY .. "Kein Pet aktiv – deine gelernten Ränge bleiben dauerhaft gespeichert.|r")
  end
  local mode = DinosPetSkillsDB.ui.filter or "all"
  for key, b in pairs(filterButtons) do
    if key == mode then b:LockHighlight() else b:UnlockHighlight() end
  end
  footer:SetText(ns.GREY .. "Klick auf eine Fähigkeit = Ränge auf-/zuklappen|r")
end

function ns.RefreshUI()
  if not frame or not frame:IsShown() then return end
  applyFontSize()
  updateHeader()
  buildRows()
  updateList()
end

-- ------------------------------------------------------------------ Hauptfenster bauen
local function build()
  local db = DinosPetSkillsDB
  frame = CreateFrame("Frame", "DinosPetSkillsFrame", UIParent, BACKDROP)
  frame:SetSize(W, H)
  frame:SetFrameStrata("HIGH")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint()
    db.ui.point = { p, rp, x, y }
  end)
  local pt = db.ui.point
  if type(pt) == "table" and pt[1] then
    frame:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
  else
    frame:SetPoint("CENTER")
  end
  if frame.SetBackdrop then
    frame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  frame:Hide()
  tinsert(UISpecialFrames, "DinosPetSkillsFrame")   -- ESC schließt das Fenster
  frame:SetScript("OnShow", function()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_OPEN) end
    wipe(expandedSkill)
    if bCollapse then bCollapse:SetText("Alle aufklappen") end
    ns.ImportFromFBPH()
    ns.ScanCraft()
    ns.ScanActivePet()
    ns.RefreshUI()
  end)
  frame:SetScript("OnHide", function()
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE then pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_CLOSE) end
  end)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- Schriftgröße-Umschalter (3 Stufen: S / M / L) oben rechts
  local fLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  fLabel:SetText("Schrift:")
  local FONT_LABELS = { { 1, "S", "Klein (10 pt)" }, { 2, "M", "Mittel (12 pt)" }, { 3, "L", "Groß (14 pt)" } }
  local prevBtn
  for i = #FONT_LABELS, 1, -1 do
    local info = FONT_LABELS[i]
    local fb = makeButton(frame, info[2], 24)
    fb:SetHeight(18)
    if not prevBtn then
      fb:SetPoint("TOPRIGHT", close, "TOPLEFT", -4, -7)
    else
      fb:SetPoint("RIGHT", prevBtn, "LEFT", -2, 0)
    end
    fb:SetScript("OnClick", function()
      db.ui.fontSize = info[1]
      applyFontSize()
      ns.RefreshUI()
    end)
    fb:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine("Schriftgröße: " .. info[3], 1, 0.82, 0)
      GameTooltip:Show()
    end)
    fb:SetScript("OnLeave", GameTooltip_Hide)
    fontButtons[info[1]] = fb
    prevBtn = fb
  end
  fLabel:SetPoint("RIGHT", prevBtn, "LEFT", -5, 0)

  -- Maskottchen: Dino, der Ankylosaurus
  local badge = CreateFrame("Frame", nil, frame, BACKDROP)
  badge:SetSize(64, 64)
  badge:SetPoint("TOPLEFT", 16, -16)
  if badge.SetBackdrop then
    badge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    badge:SetBackdropBorderColor(1, 0.82, 0, 1)
  end
  local dino = badge:CreateTexture(nil, "ARTWORK")
  dino:SetPoint("TOPLEFT", 4, -4)
  dino:SetPoint("BOTTOMRIGHT", -4, 4)
  dino:SetTexture(ns.DINO_ICON)
  badge:EnableMouse(true)
  badge:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("by X4rinia und Dino", 1, 0.82, 0)
    GameTooltip:AddLine("Zusatz Addon für Bestinary Forever", 1, 1, 1)
    GameTooltip:Show()
  end)
  badge:SetScript("OnLeave", GameTooltip_Hide)

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  title:SetPoint("TOPLEFT", badge, "TOPRIGHT", 12, -4)
  title:SetText("Dino's Pet-Skills")
  local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  sub:SetText("by X4rinia und Dino · Zusatz Addon für Bestinary Forever")

  local barFrame = CreateFrame("Frame", nil, frame, BACKDROP)
  barFrame:SetSize(360, 22)
  barFrame:SetPoint("TOPLEFT", sub, "BOTTOMLEFT", -3, -6)
  if barFrame.SetBackdrop then
    barFrame:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    barFrame:SetBackdropColor(0, 0, 0, 0.6)
  end
  progress = CreateFrame("StatusBar", nil, barFrame)
  progress:SetPoint("TOPLEFT", 4, -4)
  progress:SetPoint("BOTTOMRIGHT", -4, 4)
  progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  progress:SetStatusBarColor(0.15, 0.75, 0.2)
  progressText = progress:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  progressText:SetPoint("CENTER")

  petLine = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  petLine:SetPoint("TOPLEFT", 20, -92)
  petLine:SetPoint("RIGHT", frame, "RIGHT", -20, 0)
  petLine:SetJustifyH("LEFT")

  -- Filter
  local function setFilter(mode)
    db.ui.filter = mode
    if scroll then FauxScrollFrame_SetOffset(scroll, 0); scroll:SetVerticalScroll(0) end
    ns.RefreshUI()
  end
  local bAll = makeButton(frame, "Alle", 70)
  bAll:SetPoint("TOPLEFT", 18, -112)
  bAll:SetScript("OnClick", function() setFilter("all") end)
  local bLearned = makeButton(frame, "Gelernt " .. ns.CHECK, 90)
  bLearned:SetPoint("LEFT", bAll, "RIGHT", 4, 0)
  bLearned:SetScript("OnClick", function() setFilter("learned") end)
  local bMiss = makeButton(frame, "Fehlend " .. ns.CROSS, 90)
  bMiss:SetPoint("LEFT", bLearned, "RIGHT", 4, 0)
  bMiss:SetScript("OnClick", function() setFilter("missing") end)
  local bPet = makeButton(frame, "Aktuelles Pet", 102)
  bPet:SetPoint("LEFT", bMiss, "RIGHT", 4, 0)
  bPet:SetScript("OnClick", function() setFilter("pet") end)
  filterButtons.all, filterButtons.learned, filterButtons.missing, filterButtons.pet = bAll, bLearned, bMiss, bPet

  local ok, sb = pcall(CreateFrame, "EditBox", "DinosPetSkillsSearchBox", frame, "SearchBoxTemplate")
  if not ok or not sb then
    sb = CreateFrame("EditBox", "DinosPetSkillsSearchBox", frame, "InputBoxTemplate")
    local ph = sb:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 4, 0)
    sb.Instructions = ph
    sb:HookScript("OnTextChanged", function(self) ph:SetShown(self:GetText() == "") end)
  end
  searchBox = sb
  sb:SetSize(160, 20)
  sb:SetAutoFocus(false)
  sb:SetPoint("TOPRIGHT", -22, -113)
  if sb.Instructions then sb.Instructions:SetText("Suchen…") end
  sb:HookScript("OnTextChanged", function(self)
    ns.searchText = self:GetText() or ""
    if scroll then FauxScrollFrame_SetOffset(scroll, 0); scroll:SetVerticalScroll(0) end
    ns.RefreshUI()
  end)
  sb:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sb:HookScript("OnEnterPressed", function(self) self:ClearFocus() end)

  -- Liste
  local list = CreateFrame("Frame", nil, frame, BACKDROP)
  list:SetPoint("TOPLEFT", 14, -LIST_TOP + 6)
  list:SetPoint("BOTTOMRIGHT", -14, LIST_BOTTOM)
  if list.SetBackdrop then
    list:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    list:SetBackdropColor(0, 0, 0, 0.55)
    list:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end
  scroll = CreateFrame("ScrollFrame", "DinosPetSkillsScroll", list, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -5)
  scroll:SetPoint("BOTTOMRIGHT", -28, 5)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, updateList)
  end)

  rowsUI = {}
  for i = 1, NUM_ROWS do
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 6, -6 - (i - 1) * ROW_H)
    b:SetPoint("RIGHT", list, "RIGHT", -30, 0)
    b:RegisterForClicks("LeftButtonUp")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.5)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(1, 0.82, 0, 0.08)
    b.toggle = b:CreateTexture(nil, "ARTWORK")
    b.toggle:SetSize(14, 14)
    b.toggle:SetPoint("LEFT", 2, 0)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetPoint("LEFT", 20, 0)
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT", -4, 0)
    b.right:SetJustifyH("RIGHT")
    b.left = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.left:SetJustifyH("LEFT")
    if b.left.SetWordWrap then b.left:SetWordWrap(false) end
    b.left:SetHeight(ROW_H)
    b:SetScript("OnClick", onRowClick)
    b:SetScript("OnEnter", onRowEnter)
    b:SetScript("OnLeave", GameTooltip_Hide)
    rowsUI[i] = b
  end
  applyFontSize()

  -- Fuß: Button zu Forever Bestiary + Auf-/Zuklappen
  bCollapse = makeButton(frame, "Alle aufklappen", 112)
  bCollapse:SetPoint("BOTTOMRIGHT", -16, 15)
  bCollapse:SetScript("OnClick", function(self)
    local anyOpen = next(expandedSkill) ~= nil
    wipe(expandedSkill)
    if not anyOpen then
      for _, rec in ipairs(ns.skills) do expandedSkill[rec.key] = true end
    end
    self:SetText(anyOpen and "Alle aufklappen" or "Alle zuklappen")
    ns.RefreshUI()
  end)

  bBestiary = makeButton(frame, "Forever Bestiary", 136)
  bBestiary:SetPoint("RIGHT", bCollapse, "LEFT", -6, 0)
  local fbIco = bBestiary:CreateTexture(nil, "ARTWORK")
  fbIco:SetSize(14, 14)
  fbIco:SetPoint("LEFT", 6, 0)
  fbIco:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
  fbIco:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  bBestiary:SetText("   Forever Bestiary")
  bBestiary:SetScript("OnClick", function() openForeverBestiary("") end)
  bBestiary:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Forever Bestiary öffnen", 1, 0.82, 0)
    GameTooltip:AddLine("Öffnet das Hauptfenster von Forever Bestiary (Pet Hunter), um Wildtiere & Fundorte nachzuschlagen.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  bBestiary:SetScript("OnLeave", GameTooltip_Hide)

  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 20, 21)
  footer:SetPoint("RIGHT", bBestiary, "LEFT", -8, 0)
  footer:SetJustifyH("LEFT")
end

function ns.Toggle()
  if not DinosPetSkillsDB then return end
  if not frame then build() end
  if frame:IsShown() then frame:Hide() else frame:Show() end
end

function ns.ShowFrame()
  if not frame then build() end
  frame:Show()
end
