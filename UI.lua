-- DinosPetSkills · Das Gesamt-Übersichtsfenster "Dino's Pet-Skills" + separates Wildtier-Quellen-Fenster
local _, ns = ...

local W, H = 580, 520
local ROW_H = 20
local LIST_TOP, LIST_BOTTOM = 150, 42
local NUM_ROWS = math.floor((H - LIST_TOP - LIST_BOTTOM - 8) / ROW_H)

local SUB_W, SUB_H = 380, 520
local SUB_ROW_H = 20
local SUB_TOP, SUB_BOTTOM = 58, 34
local SUB_NUM_ROWS = math.floor((SUB_H - SUB_TOP - SUB_BOTTOM - 8) / SUB_ROW_H)

local frame, scroll, rowsUI, progress, progressText, petLine, footer, searchBox, bCollapse
local beastFrame, beastScroll, beastRowsUI, beastTitle, beastSub, beastFooter
local selectedRank       -- { rec = rec, r = r, beasts = list }
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
  for _, b in ipairs(beastRowsUI or {}) do
    b.left:SetFont(face, sz, flags)
    b.right:SetFont(face, sz, flags)
  end
  if petLine then petLine:SetFont(face, sz, flags) end
  if progressText then progressText:SetFont(face, sz, flags) end
  if beastSub then beastSub:SetFont(face, sz, flags) end
  for k, btn in pairs(fontButtons) do
    if k == idx then btn:LockHighlight() else btn:UnlockHighlight() end
  end
end

local BACKDROP = BackdropTemplateMixin and "BackdropTemplate" or nil

local RARITY = {
  n = nil,
  r = { "|cffc0c0ff", "Rar" },
  e = { "|cffffa500", "Elite" },
  re = { "|cffff80ff", "Rar-Elite" },
}

-- ------------------------------------------------------------------ Hilfen
local function famList(rec, max)
  if rec.key == "Cower" then return "Alle Familien (durch Wildtiere)" end
  local names = {}
  for i, slug in ipairs(rec.fams) do
    if i > (max or 3) then names[#names + 1] = "…" break end
    names[#names + 1] = ns.FamilyName(slug)
  end
  if #names == 0 then return "" end
  return table.concat(names, ", ")
end

local function skillMatches(rec, q)
  for _, k in ipairs({ "en", "de", "es", "fr" }) do
    if rec[k] and ns.norm(rec[k]):find(q, 1, true) then return true end
  end
  return ns.norm(ns.SkillName(rec)):find(q, 1, true) ~= nil
end

local function beastMatches(b, q)
  if ns.norm(ns.BeastName(b)):find(q, 1, true) then return true end
  if b.en and ns.norm(b.en):find(q, 1, true) then return true end
  if b.de and ns.norm(b.de):find(q, 1, true) then return true end
  if ns.norm(ns.FamilyName(b.f)):find(q, 1, true) then return true end
  for _, z in ipairs(ns.BeastZones(b)) do
    if ns.norm(z):find(q, 1, true) then return true end
  end
  return false
end

local function levelText(b)
  if not b.l1 then return "?" end
  if b.l2 and b.l2 ~= b.l1 then return b.l1 .. "-" .. b.l2 end
  return tostring(b.l1)
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

-- ------------------------------------------------------------------ Zeilen aufbauen (nur Skills & Ränge, keine Tiere dazwischen!)
local function buildRows()
  wipe(displayRows)
  local db = DinosPetSkillsDB
  local mode = db.ui.filter or "all"
  local q = ns.norm(ns.searchText or "")
  for _, rec in ipairs(ns.skills) do
    if mode ~= "pet" or ns.PetCanUse(rec) then
      local skillMatch = (q == "") or skillMatches(rec, q)
      local rankRows = {}
      for _, r in ipairs(ns.RankList(rec)) do
        local learned = ns.IsLearned(rec.key, r)
        if (mode == "all") or (mode == "pet") or (mode == "learned" and learned) or (mode == "missing" and not learned) then
          local list = ns.sources[rec.key] and ns.sources[rec.key][r] or {}
          local beasts, matchedBeast = list, false
          if q ~= "" and not skillMatch then
            beasts = {}
            for _, e in ipairs(list) do
              if beastMatches(e.b, q) then beasts[#beasts + 1] = e end
            end
            matchedBeast = #beasts > 0
          end
          if skillMatch or matchedBeast then
            rankRows[#rankRows + 1] = {
              kind = "rank", rec = rec, r = r, learned = learned,
              beasts = beasts, total = #list,
            }
          end
        end
      end
      if #rankRows > 0 then
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
    GameTooltip:AddLine(ns.CHECK .. " Von deinem Jäger dauerhaft erlernt", 0, 1, 0)
  else
    GameTooltip:AddLine(ns.CROSS .. " Noch nie erlernt", 1, 0.27, 0.27)
  end
  if ns.PetHas(rec.key, r) then
    GameTooltip:AddLine("Dein aktuelles Pet (" .. tostring(ns.activePetName) .. ") beherrscht diesen Rang.", 0, 0.8, 1, true)
  end
  if row.total > 0 then
    GameTooltip:AddLine(("%d Wildtier(e) lehren diesen Rang – klicken für die extra Tier-Liste."):format(row.total), 1, 0.82, 0, true)
  else
    GameTooltip:AddLine("Kein lehrendes Wildtier in der Datenbank bekannt.", 0.6, 0.6, 0.6, true)
  end
  GameTooltip:Show()
end

local function beastTooltip(owner, e, rec, r)
  local b = e.b
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  local rar = b.r and RARITY[b.r]
  GameTooltip:AddLine((rar and rar[1] or "|cffffffff") .. ns.BeastName(b) .. "|r")
  GameTooltip:AddLine(ns.FamilyName(b.f) .. " · Stufe " .. levelText(b) .. (rar and (" · " .. rar[2]) or ""), 0.8, 0.8, 0.8)
  local zones = ns.BeastZones(b)
  if #zones > 0 then GameTooltip:AddLine("Zone: " .. table.concat(zones, ", "), 1, 1, 1, true) end
  GameTooltip:AddLine("Lehrt: " .. ns.SkillName(rec) .. " (Rang " .. r .. ")", 1, 0.82, 0)
  local lvl = UnitLevel("player") or 0
  if not b.l1 or lvl >= b.l1 then
    GameTooltip:AddLine("Dein Level (" .. lvl .. ") reicht zum Zähmen.", 0, 1, 0)
  else
    GameTooltip:AddLine("Zum Zähmen brauchst du Stufe " .. b.l1 .. " (du bist " .. lvl .. ").", 1, 0.27, 0.27)
  end
  if SlashCmdList and SlashCmdList["FBPETHUNTER"] then
    GameTooltip:AddLine("Klicken: im Forever Bestiary öffnen", 0.5, 0.5, 0.5)
  end
  GameTooltip:Show()
end

-- ------------------------------------------------------------------ Separates Wildtier-Quellen-Fenster (rechts daneben)
local function updateBeastList()
  if not beastFrame or not beastFrame:IsShown() or not selectedRank then return end
  local list = selectedRank.beasts or {}
  local rec, r = selectedRank.rec, selectedRank.r
  beastTitle:SetText(ns.GOLD .. ns.SkillName(rec) .. " (Rang " .. r .. ")|r")
  local rk = rec.ranks[r] or {}
  beastSub:SetText((rk.l and ("Benötigt Pet-Stufe " .. rk.l .. " · ") or "")
    .. (#list == 1 and "1 mögliches Wildtier" or (#list .. " mögliche Wildtiere")))
  FauxScrollFrame_Update(beastScroll, #list, SUB_NUM_ROWS, SUB_ROW_H)
  local offset = FauxScrollFrame_GetOffset(beastScroll)
  local lvl = UnitLevel("player") or 0
  for i = 1, SUB_NUM_ROWS do
    local btn = beastRowsUI[i]
    local e = list[offset + i]
    if e then
      local b = e.b
      btn.entry = e
      local rar = b.r and RARITY[b.r]
      local name = (rar and rar[1] or "|cffffffff") .. ns.BeastName(b) .. "|r"
      local zones = ns.BeastZones(b)
      local zone = zones[1] and (zones[1] .. (#zones > 1 and (" +" .. (#zones - 1)) or "")) or "Zone unbekannt"
      btn.left:SetText("• " .. name .. ns.GREY .. " · " .. ns.FamilyName(b.f) .. " (" .. levelText(b) .. ") · " .. zone .. "|r")
      if not b.l1 or lvl >= b.l1 then
        btn.right:SetText(ns.GREEN .. "zähmbar|r")
      else
        btn.right:SetText(ns.RED .. "ab " .. b.l1 .. "|r")
      end
      btn:Show()
    else
      btn.entry = nil
      btn:Hide()
    end
  end
  if #list == 0 then
    beastFooter:SetText(ns.GREY .. "Für diesen Rang ist aktuell kein lehrendes Wildtier in der Datenbank verzeichnet.|r")
  else
    beastFooter:SetText(ns.GREY .. "Tipp: Klicke auf ein Wildtier, um es im Forever Bestiary auf der Karte zu zeigen.|r")
  end
end

local function buildBeastFrame()
  beastFrame = CreateFrame("Frame", "DinosPetSkillsBeastsFrame", frame, BACKDROP)
  beastFrame:SetSize(SUB_W, SUB_H)
  beastFrame:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
  beastFrame:SetFrameStrata("HIGH")
  beastFrame:EnableMouse(true)
  if beastFrame.SetBackdrop then
    beastFrame:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  local close = CreateFrame("Button", nil, beastFrame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function()
    selectedRank = nil
    beastFrame:Hide()
    ns.RefreshUI()
  end)

  beastTitle = beastFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  beastTitle:SetPoint("TOPLEFT", 18, -16)
  beastTitle:SetPoint("RIGHT", -36, 0)
  beastTitle:SetJustifyH("LEFT")

  beastSub = beastFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  beastSub:SetPoint("TOPLEFT", beastTitle, "BOTTOMLEFT", 0, -4)
  beastSub:SetJustifyH("LEFT")

  local list = CreateFrame("Frame", nil, beastFrame, BACKDROP)
  list:SetPoint("TOPLEFT", 14, -SUB_TOP)
  list:SetPoint("BOTTOMRIGHT", -14, SUB_BOTTOM)
  if list.SetBackdrop then
    list:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    list:SetBackdropColor(0, 0, 0, 0.55)
    list:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end

  beastScroll = CreateFrame("ScrollFrame", "DinosPetSkillsBeastsScroll", list, "FauxScrollFrameTemplate")
  beastScroll:SetPoint("TOPLEFT", 4, -5)
  beastScroll:SetPoint("BOTTOMRIGHT", -28, 5)
  beastScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, SUB_ROW_H, updateBeastList)
  end)

  beastRowsUI = {}
  for i = 1, SUB_NUM_ROWS do
    local b = CreateFrame("Button", nil, list)
    b:SetHeight(SUB_ROW_H)
    b:SetPoint("TOPLEFT", list, "TOPLEFT", 8, -6 - (i - 1) * SUB_ROW_H)
    b:SetPoint("RIGHT", list, "RIGHT", -30, 0)
    b:RegisterForClicks("LeftButtonUp")
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.45)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.right:SetPoint("RIGHT", -4, 0)
    b.right:SetJustifyH("RIGHT")
    b.left = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.left:SetPoint("LEFT", 4, 0)
    b.left:SetPoint("RIGHT", b.right, "LEFT", -6, 0)
    b.left:SetJustifyH("LEFT")
    if b.left.SetWordWrap then b.left:SetWordWrap(false) end
    b.left:SetHeight(SUB_ROW_H)
    b:SetScript("OnClick", function(self)
      if not self.entry then return end
      local cmd = SlashCmdList and SlashCmdList["FBPETHUNTER"]
      if cmd then pcall(cmd, "search " .. ns.BeastName(self.entry.b)) end
    end)
    b:SetScript("OnEnter", function(self)
      if self.entry and selectedRank then beastTooltip(self, self.entry, selectedRank.rec, selectedRank.r) end
    end)
    b:SetScript("OnLeave", GameTooltip_Hide)
    beastRowsUI[i] = b
  end

  beastFooter = beastFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  beastFooter:SetPoint("BOTTOMLEFT", 18, 14)
  beastFooter:SetPoint("RIGHT", -18, 0)
  beastFooter:SetJustifyH("LEFT")
  applyFontSize()
  beastFrame:Hide()
end

local function toggleBeastPanel(row)
  if not beastFrame then buildBeastFrame() end
  if selectedRank and selectedRank.rec == row.rec and selectedRank.r == row.r and beastFrame:IsShown() then
    selectedRank = nil
    beastFrame:Hide()
  else
    selectedRank = { rec = row.rec, r = row.r, beasts = row.beasts or {} }
    FauxScrollFrame_SetOffset(beastScroll, 0)
    beastScroll:SetVerticalScroll(0)
    beastFrame:Show()
    updateBeastList()
  end
end

-- ------------------------------------------------------------------ Hauptliste rendern
local function renderRow(btn, row)
  btn.row = row
  btn.icon:Hide(); btn.toggle:Hide()
  btn.left:ClearAllPoints(); btn.right:SetText("")
  btn.bg:Hide()
  if row.kind == "skill" then
    local rec = row.rec
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
    local isSel = selectedRank and selectedRank.rec == rec and selectedRank.r == r and beastFrame and beastFrame:IsShown()
    if isSel then
      btn.bg:SetColorTexture(0.2, 0.6, 1, 0.18)
      btn.bg:Show()
    else
      btn.bg:SetColorTexture(1, 0.82, 0, 0.08)
    end
    btn.left:SetPoint("LEFT", btn, "LEFT", 32, 0)
    btn.left:SetPoint("RIGHT", btn.right, "LEFT", -8, 0)
    local status = row.learned and (ns.CHECK .. " " .. ns.GREEN .. "Rang " .. r .. "|r")
      or (ns.CROSS .. " " .. ns.RED .. "Rang " .. r .. "|r")
    local lv = rk.l and (ns.GREY .. "  · Stufe " .. rk.l .. "|r") or ""
    local pet = ns.PetHas(rec.key, r) and ("  " .. petHint()) or ""
    btn.left:SetText(status .. lv .. pet)
    if row.total > 0 then
      btn.right:SetText((isSel and ns.CYAN or "|cffffd100") .. row.total .. (row.total == 1 and " Tier »|r" or " Tiere »|r"))
    else
      btn.right:SetText(ns.GREY .. "–|r")
    end
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
  elseif row.kind == "rank" then
    toggleBeastPanel(row)
  end
  buildRows()
  updateList()
end

local function onRowEnter(btn)
  local row = btn.row
  if not row then return end
  if row.kind == "rank" then
    rankTooltip(btn, row)
  elseif row.kind == "skill" then
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.SkillName(row.rec))
    local fam = famList(row.rec, 20)
    if fam ~= "" then GameTooltip:AddLine(fam, 0.8, 0.8, 0.8, true) end
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
    local n = 0
    for _ in pairs(ns.activePetSkills) do n = n + 1 end
    petLine:SetText(("Aktuelles Pet: %s%s|r %s(%s)|r"):format(ns.CYAN, ns.activePetName,
      ns.GREY, ns.activePetFamily and ns.FamilyName(ns.activePetFamily) or (UnitCreatureFamily and UnitCreatureFamily("pet") or "?")))
  else
    petLine:SetText(ns.GREY .. "Kein Pet aktiv – deine gelernten Ränge bleiben dauerhaft gespeichert.|r")
  end
  local mode = DinosPetSkillsDB.ui.filter or "all"
  for key, b in pairs(filterButtons) do
    if key == mode then b:LockHighlight() else b:UnlockHighlight() end
  end
  footer:SetText(ns.GREY .. "Klick auf Fähigkeit = Ränge zeigen · Klick auf Rang = Tiere im Seitenfenster|r")
end

function ns.RefreshUI()
  if not frame or not frame:IsShown() then return end
  applyFontSize()
  updateHeader()
  buildRows()
  updateList()
  if beastFrame and beastFrame:IsShown() then updateBeastList() end
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
    frame:SetPoint("CENTER", -80, 0)
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
    selectedRank = nil
    if beastFrame then beastFrame:Hide() end
    if bCollapse then bCollapse:SetText("Alle aufklappen") end
    ns.ImportFromFBPH()
    ns.ScanCraft()
    ns.ScanActivePet()
    ns.RefreshUI()
  end)
  frame:SetScript("OnHide", function()
    if beastFrame then beastFrame:Hide() end
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

  -- Fuß: Auf-/Zuklappen + Kurzhilfe
  bCollapse = makeButton(frame, "Alle aufklappen", 110)
  bCollapse:SetPoint("BOTTOMRIGHT", -18, 16)
  bCollapse:SetScript("OnClick", function(self)
    local anyOpen = next(expandedSkill) ~= nil
    wipe(expandedSkill)
    if not anyOpen then
      for _, rec in ipairs(ns.skills) do expandedSkill[rec.key] = true end
    end
    self:SetText(anyOpen and "Alle aufklappen" or "Alle zuklappen")
    ns.RefreshUI()
  end)
  footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  footer:SetPoint("BOTTOMLEFT", 20, 22)
  footer:SetPoint("RIGHT", bCollapse, "LEFT", -8, 0)
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
