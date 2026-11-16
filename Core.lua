-- DinosPetSkills · Kern: Speicher, Katalog aller Tierfähigkeiten, Einlesen der Wildtierausbildung, aktuelles Pet
local ADDON, ns = ...
ns.ADDON = ADDON
ns.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"
ns.DINO_ICON = ns.MEDIA .. "dino"

-- Status-Symbole. Die Standard-Schrift von WoW (Friz Quadrata) enthält die Zeichen ✔/✘ nicht (sie würden als
-- Kästchen erscheinen) – darum dieselben Haken-/Kreuz-Texturen wie im Tooltip von ForeverBestiaryPetHunter.
ns.CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14:14:0:0|t"
ns.CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:14:14:0:0|t"
ns.CHECK_SMALL = "|TInterface\\RaidFrame\\ReadyCheck-Ready:11:11:0:0|t"
ns.GREEN, ns.RED, ns.CYAN, ns.GREY, ns.GOLD = "|cff00ff00", "|cffff4444", "|cff00ccff", "|cff9d9d9d", "|cffffd100"

local LANGKEY = { deDE = "de", esES = "es", esMX = "es", frFR = "fr", ruRU = "ru", zhCN = "zh", zhTW = "zh" }
ns.langKey = LANGKEY[GetLocale and GetLocale() or "enUS"] or "en"

function ns.Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff7fd45fDino's Pet-Skills|r: " .. tostring(msg))
  end
end

local function after(sec, fn)
  if C_Timer and C_Timer.After then C_Timer.After(sec, fn) else fn() end
end
ns.After = after

function ns.InCombat() return InCombatLockdown and InCombatLockdown() and true or false end

-- ------------------------------------------------------------------ Text-Helfer
local ACCENTS = {
  ["ä"] = "a", ["ö"] = "o", ["ü"] = "u", ["Ä"] = "a", ["Ö"] = "o", ["Ü"] = "u", ["ß"] = "ss",
  ["á"] = "a", ["à"] = "a", ["â"] = "a", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
  ["í"] = "i", ["ì"] = "i", ["î"] = "i", ["ï"] = "i", ["ó"] = "o", ["ò"] = "o", ["ô"] = "o",
  ["ú"] = "u", ["ù"] = "u", ["û"] = "u", ["ñ"] = "n", ["ç"] = "c", ["É"] = "e", ["À"] = "a",
  ["’"] = "'", ["´"] = "'", ["`"] = "'",
}
function ns.norm(s)
  if type(s) ~= "string" then return "" end
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
  s = s:gsub("[%z\1-\127\194-\244][\128-\191]*", function(c) return ACCENTS[c] or c end)
  s = s:lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
  return s
end

-- "Rang 3", "Rank 3", "Rango 3", "Rang III", 3 -> 3
local ROMAN = { i = 1, ii = 2, iii = 3, iv = 4, v = 5, vi = 6, vii = 7, viii = 8, ix = 9, x = 10, xi = 11, xii = 12 }
function ns.ParseRank(sub)
  if type(sub) == "number" then return sub end
  if type(sub) ~= "string" or sub == "" then return nil end
  local n = sub:match("(%d+)")
  if n then return tonumber(n) end
  local w = (" " .. sub:lower()):match("%s([ivx]+)%s*%)?%s*$")
  return w and ROMAN[w] or nil
end

-- "Blitzschlagatem (Rang 3)" / "Lightning Breath Rank 3" -> "Blitzschlagatem", 3
function ns.SplitNameRank(text)
  if type(text) ~= "string" then return nil, nil end
  local name, inner = text:match("^(.-)%s*%((.-)%)%s*$")
  if name and name ~= "" and ns.ParseRank(inner) then return name, ns.ParseRank(inner) end
  local n2, r2 = text:match("^(.-)%s+[Rr][Aa][Nn][GgKk][Oo]?%s+(%d+)%s*$")
  if n2 and n2 ~= "" then return n2, tonumber(r2) end
  return text, nil
end

-- Name eines Zaubers über seine ID (Classic: GetSpellInfo -> Name; neuere Clients: C_Spell.GetSpellInfo -> Tabelle)
function ns.SpellName(id)
  if not id then return nil end
  if C_Spell and C_Spell.GetSpellInfo then
    local ok, info = pcall(C_Spell.GetSpellInfo, id)
    if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
  end
  if GetSpellInfo then
    local ok, name = pcall(GetSpellInfo, id)
    if ok and type(name) == "string" then return name end
  end
  return nil
end

function ns.IconPath(icon)
  if type(icon) == "number" then return icon end
  if type(icon) == "string" and icon ~= "" then
    if icon:find("\\", 1, true) then return icon end
    return "Interface\\Icons\\" .. icon
  end
  return "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- Die gespeicherten Daten von ForeverBestiaryPetHunter (nur lesend!)
function ns.FBPHDB()
  local db = rawget(_G, "ForeverBestiaryPetHunterDB")
  if type(db) == "table" then return db end
  return nil
end

function ns.FBPHLoaded()
  local isLoaded = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
  if not isLoaded then return false end
  local ok, v = pcall(isLoaded, "ForeverBestiaryPetHunter")
  return ok and v and true or false
end

-- ------------------------------------------------------------------ Gespeicherte Daten (pro Charakter)
local DEFAULTS = {
  version = 2,
  learned = {},     -- [Fähigkeit (engl. Schlüssel)] = { [Rang] = true } – dauerhaft & kumulativ, wird NIE gelöscht
  names = {},       -- [Schlüssel] = Name, wie dein Client ihn zeigt
  custom = {},      -- (Reserviert)
  learnedAt = {},   -- [Schlüssel#Rang] = Zeitpunkt des ersten Einlesens
  minimap = { angle = 200, hide = false },
  ui = { filter = "all", fontSize = 2 },
}

local function applyDefaults(db, def)
  for k, v in pairs(def) do
    if db[k] == nil then
      if type(v) == "table" then
        local copy = {}
        applyDefaults(copy, v)
        db[k] = copy
      else
        db[k] = v
      end
    elseif type(v) == "table" and type(db[k]) == "table" then
      applyDefaults(db[k], v)
    end
  end
end

-- ------------------------------------------------------------------ Katalog: alle Fähigkeiten und Ränge
ns.skills = {}       -- sortierte Liste
ns.skillByKey = {}
ns.sources = {}      -- [Schlüssel][Rang] = { { b = Wildtier, flag, confirmed } }
local nameIndex = {} -- [normierter Name in jeder Sprache] = Schlüssel
local spellIndex = {} -- [Zauber-ID] = { Schlüssel, Rang }
local famIndex = {}  -- [normierter Familienname] = Familien-Slug

local function addName(name, key)
  if type(name) == "string" and name ~= "" then
    local k = ns.norm(name)
    if k ~= "" and not nameIndex[k] then nameIndex[k] = key end
  end
end

function ns.SkillName(rec)
  if not rec then return "?" end
  if rec[ns.langKey] and rec[ns.langKey] ~= "" then return rec[ns.langKey] end
  local live = DinosPetSkillsDB and DinosPetSkillsDB.names[rec.key]
  if type(live) == "string" and live ~= "" then return live end
  return rec.de or rec.en or rec.key
end

function ns.FamilyName(slug)
  if not slug then return "?" end
  local fdb = ns.FBPHDB()
  local seen = fdb and type(fdb.familyNames) == "table" and fdb.familyNames[slug]
  if type(seen) == "string" and seen ~= "" and ns.langKey ~= "en" then return seen end
  local f = ns.FBPH and ns.FBPH.families and ns.FBPH.families[slug]
  if not f then return tostring(slug) end
  return f[ns.langKey] or f.en or tostring(slug)
end

function ns.ZoneName(z)
  if not z then return "?" end
  local fdb = ns.FBPHDB()
  local seen = fdb and type(fdb.zoneNames) == "table" and fdb.zoneNames[z]
  if type(seen) == "string" and seen ~= "" and ns.langKey ~= "en" then return seen end
  if ns.langKey == "de" and ns.FBPH and ns.FBPH.zonesDE and ns.FBPH.zonesDE[z] then return ns.FBPH.zonesDE[z] end
  return z
end

function ns.MapName(mapId)
  if C_Map and C_Map.GetMapInfo then
    local ok, info = pcall(C_Map.GetMapInfo, mapId)
    if ok and type(info) == "table" and type(info.name) == "string" then return info.name end
  end
  return nil
end

function ns.BeastName(b)
  if not b then return "?" end
  if b.names then   -- von FBPH-Spielern aufgezeichnet (nicht in der festen Datenbank)
    local n = b.names
    return n[GetLocale()] or n.deDE or n.enUS or n.enGB or select(2, next(n)) or ("#" .. tostring(b.id))
  end
  return b[ns.langKey] or b.en or b.de or ("#" .. tostring(b.id))
end

function ns.BeastZones(b)
  local out = {}
  if b.z then
    for _, z in ipairs(b.z) do
      out[#out + 1] = ns.ZoneName(z.z) .. (z.i and " (Instanz)" or "")
    end
  elseif b.maps then
    for mid in pairs(b.maps) do
      local n = ns.MapName(mid)
      if n then out[#out + 1] = n end
    end
  end
  return out
end

-- Fehlende Ränge (z. B. von einem neuen Forever-Patch) werden ergänzt, nie entfernt
function ns.EnsureRank(rec, r)
  r = tonumber(r)
  if not rec or not r or r < 1 or r > 20 then return end
  if not rec.ranks[r] then
    rec.ranks[r] = { r = r, extra = true }
    if rec.origin ~= "fbph" then
      for i = 1, r - 1 do
        if not rec.ranks[i] then rec.ranks[i] = { r = i, extra = true } end
      end
    end
  end
  if r > rec.maxRank then rec.maxRank = r end
end

function ns.RankList(rec)
  local list = {}
  for r in pairs(rec.ranks) do list[#list + 1] = r end
  table.sort(list)
  return list
end

local function addSkill(key, a, origin)
  -- Nur Fähigkeiten, die man durch Wildtiere/Pets erhalten kann:
  -- - keine Angriffsgeschwindigkeits-Passiva ("passive")
  -- - keine reinen Ausbilder-Fähigkeiten wie Große Ausdauer, Natürliche Rüstung, Widerstände ("trainer")
  -- - kein Knurren ("Growl", bekommt jedes Pet beim Ausbilder)
  if a.kind == "passive" or a.kind == "trainer" or key == "Growl" then return end
  local rec = {
    key = key, en = a.en or key, de = a.de, es = a.es, fr = a.fr, ru = a.ru, zh = a.zh,
    icon = a.icon, kind = a.kind or "special", fams = a.fams or {}, ranks = {}, maxRank = 0, origin = origin,
  }
  for _, rk in ipairs(a.ranks or {}) do
    if rk.r then
      rec.ranks[rk.r] = { r = rk.r, l = rk.l, id = rk.id, en = rk.en, de = rk.de }
      if rk.r > rec.maxRank then rec.maxRank = rk.r end
      if rk.id then spellIndex[rk.id] = { key, rk.r } end
    end
  end
  ns.skillByKey[key] = rec
  ns.skills[#ns.skills + 1] = rec
  addName(key, key)
  for _, k in ipairs({ "en", "de", "es", "fr", "ru", "zh" }) do addName(rec[k], key) end
  return rec
end

function ns.BuildCatalog()
  wipe(ns.skills); wipe(ns.skillByKey); wipe(nameIndex); wipe(spellIndex); wipe(famIndex)
  local data = ns.FBPH or {}
  for key, a in pairs(data.abilities or {}) do addSkill(key, a, "fbph") end
  local db = DinosPetSkillsDB
  -- Bereinige alte Ausbilder-/Widerstands-Einträge aus früheren Sitzungen
  if db.custom then wipe(db.custom) end
  for k in pairs(db.learned) do
    if not ns.skillByKey[k] then db.learned[k] = nil end
  end
  -- Namen, die dein Client zeigt: aus FBPH (Pet-Zauberbuch), aus unseren Scans und über die Zauber-IDs
  local fdb = ns.FBPHDB()
  if fdb and type(fdb.abilityNames) == "table" then
    for en, loc in pairs(fdb.abilityNames) do
      if ns.skillByKey[en] then addName(loc, en) end
    end
  end
  for key, loc in pairs(db.names) do
    if ns.skillByKey[key] then addName(loc, key) end
  end
  for id, e in pairs(spellIndex) do addName(ns.SpellName(id), e[1]) end
  for key, ranks in pairs(db.learned) do
    local rec = ns.skillByKey[key]
    if rec then
      local maxR = 0
      for r in pairs(ranks) do
        r = tonumber(r) or 0
        if r > maxR then maxR = r end
        ns.EnsureRank(rec, r)
      end
      -- Wer einen höheren Rang beherrscht, hat alle niedrigeren Ränge automatisch auch
      for i = 1, maxR do ranks[i] = true end
    end
  end
  -- Familien (für das aktuelle Pet)
  for slug, f in pairs(data.families or {}) do
    famIndex[ns.norm(slug)] = slug
    if f.en then famIndex[ns.norm(f.en)] = slug end
    if f.de then famIndex[ns.norm(f.de)] = slug end
  end
  if fdb then
    for k, slug in pairs(type(fdb.famAlias) == "table" and fdb.famAlias or {}) do famIndex[k] = slug end
    for slug, n in pairs(type(fdb.familyNames) == "table" and fdb.familyNames or {}) do famIndex[ns.norm(n)] = slug end
  end
  -- Sortierung: Allgemeine für (fast) alle Pets zuerst ("common" / "general"), danach Familien-Spezialfähigkeiten
  local KIND_ORDER = { general = 1, common = 1, special = 2 }
  table.sort(ns.skills, function(a, b)
    local ka, kb = KIND_ORDER[a.kind] or 2, KIND_ORDER[b.kind] or 2
    if ka ~= kb then return ka < kb end
    return ns.norm(ns.SkillName(a)) < ns.norm(ns.SkillName(b))
  end)
  ns.BuildSources()
  ns.catalogDirty = false
end

--Hat der Charakter genau diesen NPC selbst gezähmt / besessen (laut FBPH-Historie oder unserer Liste)?
function ns.IsTamedByMe(npcId)
  npcId = tonumber(npcId)
  if not npcId then return false end
  if DinosPetSkillsDB and DinosPetSkillsDB.myBeasts and DinosPetSkillsDB.myBeasts[npcId] then return true end
  local fdb = ns.FBPHDB()
  if not fdb then return false end
  local name = UnitName("player") or "?"
  local realm = (GetRealmName and GetRealmName() or ""):gsub("%s", "")
  if type(fdb.history) == "table" then
    local h = fdb.history[npcId]
    if type(h) == "table" and (not h.c or h.c == name or h.c == (name .. "-" .. realm)) then return true end
  end
  if type(fdb.story) == "table" then
    local st = fdb.story[name] or fdb.story[name .. "-" .. realm]
    if type(st) == "table" then
      for _, p in pairs(type(st.pets) == "table" and st.pets or {}) do
        if type(p) == "table" and tonumber(p.id) == npcId then return true end
      end
    end
  end
  return false
end

-- Wildtiere, die einen Rang lehren: feste FBPH-Datenbank + was FBPH-Spieler in Forever bestätigt/aufgezeichnet haben
function ns.BuildSources()
  local S = {}
  local dup = {}
  local function push(key, rank, b, flag, confirmed)
    if not ns.skillByKey[key] or not rank then return end
    local id = (b.id or tostring(b)) .. "|" .. key .. "#" .. rank
    if dup[id] then
      if confirmed then dup[id].confirmed = true end
      return
    end
    S[key] = S[key] or {}
    S[key][rank] = S[key][rank] or {}
    local e = { b = b, flag = flag, confirmed = confirmed }
    dup[id] = e
    table.insert(S[key][rank], e)
    ns.EnsureRank(ns.skillByKey[key], rank)
  end
  local fdb = ns.FBPHDB()
  local obs = fdb and type(fdb.obs) == "table" and fdb.obs or {}
  local inData = {}
  for _, b in ipairs(ns.FBPH and ns.FBPH.beasts or {}) do
    local o = b.id and obs[b.id]
    local ab = type(o) == "table" and type(o.ab) == "table" and o.ab or nil
    for _, t in ipairs(b.t or {}) do
      local key, rank = t[1], tonumber(t[2])
      push(key, rank, b, t[3], ab and tonumber(ab[key]) == rank or false)
    end
    if ab then
      for key, rank in pairs(ab) do push(key, tonumber(rank), b, "t", true) end
    end
    if b.id then inData[b.id] = true end
  end
  -- Wildtiere, die nur FBPH-Spieler gefunden haben (nicht in der festen Datenbank)
  for id, o in pairs(obs) do
    if type(id) == "number" and not inData[id] and type(o) == "table" and type(o.ab) == "table" and o.f then
      local b = { id = id, f = o.f, l1 = tonumber(o.l1), l2 = tonumber(o.l2), names = type(o.n) == "table" and o.n or {},
        maps = type(o.p) == "table" and o.p or nil, community = true }
      for key, rank in pairs(o.ab) do push(key, tonumber(rank), b, "t", true) end
    end
  end
  for _, ranks in pairs(S) do
    for _, list in pairs(ranks) do
      table.sort(list, function(x, y)
        local lx, ly = x.b.l1 or 999, y.b.l1 or 999
        if lx ~= ly then return lx < ly end
        return ns.BeastName(x.b) < ns.BeastName(y.b)
      end)
    end
  end
  ns.sources = S
end

-- Name (beliebige Sprache) oder Zauber-ID -> Schlüssel, Rang
function ns.ResolveSkill(name, spellID)
  spellID = tonumber(spellID)
  if spellID and spellIndex[spellID] then return spellIndex[spellID][1], spellIndex[spellID][2] end
  if type(name) ~= "string" or name == "" then return nil end
  local key = nameIndex[ns.norm(name)]
  if key then return key, nil end
  return nil
end

function ns.FamilySlug(name)
  if type(name) ~= "string" then return nil end
  return famIndex[ns.norm(name)]
end

-- ------------------------------------------------------------------ Erlernte Ränge (dauerhaft, kumulativ)
function ns.IsLearned(key, rank)
  local t = DinosPetSkillsDB and DinosPetSkillsDB.learned[key]
  return t and t[rank] and true or false
end

function ns.LearnedCount(rec)
  local n = 0
  for r in pairs(rec.ranks) do if ns.IsLearned(rec.key, r) then n = n + 1 end end
  return n
end

-- Speichert einen Rang einer durch Pets erlernbaren Fähigkeit (inklusive aller niedrigeren Ränge 1..rank).
-- Gibt true zurück, wenn mindestens ein Rang neu war.
function ns.MarkLearned(localName, rank, spellID)
  local db = DinosPetSkillsDB
  local key, r2 = ns.ResolveSkill(localName, spellID)
  rank = tonumber(rank) or r2 or 1
  if not key or not ns.skillByKey[key] then return false end
  if type(localName) == "string" and localName ~= "" and ns.langKey ~= "en" and localName ~= key then
    db.names[key] = localName
  end
  db.learned[key] = db.learned[key] or {}
  local rec = ns.skillByKey[key]
  if rec then ns.EnsureRank(rec, rank) end
  local anyNew = false
  local now = time()
  for r = 1, rank do
    if not db.learned[key][r] then
      db.learned[key][r] = true
      db.learnedAt[key .. "#" .. r] = now
      anyNew = true
    end
  end
  return anyNew, key, rank
end

function ns.Progress()
  local learned, total = 0, 0
  for _, rec in ipairs(ns.skills) do
    for r in pairs(rec.ranks) do
      total = total + 1
      if ns.IsLearned(rec.key, r) then learned = learned + 1 end
    end
  end
  return learned, total
end

-- ------------------------------------------------------------------ Wildtierausbildung (CraftFrame) einlesen
local TRAINING_NAMES = {
  ["beast training"] = true, ["wildtierausbildung"] = true, ["adiestramiento de bestias"] = true,
  ["dressage des betes"] = true, ["dressage de betes"] = true,
}

function ns.IsPetTrainingCraft()
  if not (GetNumCrafts and GetCraftInfo) then return false end
  if CraftIsPetTraining then
    local ok, v = pcall(CraftIsPetTraining)
    if ok and v then return true end
  end
  if GetCraftName then
    local ok, n = pcall(GetCraftName)
    if ok and type(n) == "string" and TRAINING_NAMES[ns.norm(n)] then return true end
  end
  -- Prüfe die Einträge selbst: stehen dort bekannte Pet-Fähigkeiten (z. B. Knurren, Blitzschlagatem, Große Ausdauer)?
  local okN, num = pcall(GetNumCrafts)
  num = okN and tonumber(num) or 0
  for i = 1, math.min(num, 15) do
    local okI, name, sub, ctype = pcall(GetCraftInfo, i)
    if okI and type(name) == "string" and name ~= "" and ctype ~= "header" then
      local cleanName = (ns.SplitNameRank(name)) or name
      if ns.ResolveSkill(cleanName) then return true end
      if ns.ParseRank(sub) then return true end
    end
  end
  if GetCraftDisplaySkillLine then
    local ok, n = pcall(GetCraftDisplaySkillLine)
    if ok and type(n) == "string" and n ~= "" then return false end   -- ein Beruf (Verzauberkunst)
  end
  return false
end

ns.craftPet = {}   -- [Schlüssel] = { [Rang] = true }: was das aktuelle Pet laut Wildtierausbildung schon kann ("used")

function ns.ScanCraft()
  if not ns.IsPetTrainingCraft() then return 0 end
  local ok, n = pcall(GetNumCrafts)
  n = ok and tonumber(n) or 0
  if n == 0 then return 0 end
  local new, petHas = 0, {}
  for i = 1, n do
    local name, sub, ctype = GetCraftInfo(i)
    if type(name) == "string" and name ~= "" and ctype ~= "header" then
      local rank = ns.ParseRank(sub)
      if not rank then
        local n2, r2 = ns.SplitNameRank(name)
        if r2 then name, rank = n2, r2 end
      else
        name = (ns.SplitNameRank(name)) or name
      end
      rank = rank or 1
      local icon = GetCraftIcon and GetCraftIcon(i) or nil
      local isNew = ns.MarkLearned(name, rank, nil, icon)
      if isNew then
        new = new + 1
        ns.Print(("Neu gespeichert: %s %s %s"):format(ns.CHECK, name, ns.GREY .. "(Rang " .. rank .. ")|r"))
      end
      if ctype == "used" then
        local key = ns.ResolveSkill(name) or name
        petHas[key] = petHas[key] or {}
        petHas[key][rank] = true
      end
    end
  end
  -- "bereits bekannt" gilt nur für das Pet, für das das Fenster gerade offen ist
  if ns.craftOpen or (CraftFrame and CraftFrame:IsShown()) then
    ns.craftPet = petHas
    ns.craftPetName = UnitName("pet")
  end
  if ns.catalogDirty then ns.BuildCatalog() end
  return new
end

-- "Ihr habt eine neue Fähigkeit erlernt: Blitzschlagatem (Rang 3)." (Systemnachricht beim Lernen von einem Tier)
local learnPatterns
local function buildLearnPatterns()
  learnPatterns = {}
  for _, g in ipairs({ "ERR_LEARN_ABILITY_S", "ERR_LEARN_SPELL_S" }) do
    local s = rawget(_G, g)
    if type(s) == "string" and s:find("%s", 1, true) then
      local p = "^" .. s:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"):gsub("%%%%s", "(.+)") .. "$"
      learnPatterns[#learnPatterns + 1] = p
    end
  end
end

function ns.OnSystemMessage(msg)
  if type(msg) ~= "string" then return end
  if not learnPatterns then buildLearnPatterns() end
  for _, p in ipairs(learnPatterns) do
    local what = msg:match(p)
    if what then
      local name, rank = ns.SplitNameRank(what)
      local key = ns.ResolveSkill(name)
      -- nur echte Tierfähigkeiten (jeder andere neue Zauber des Jägers wird ignoriert)
      if key and ns.skillByKey[key] then
        if ns.MarkLearned(name, rank or 1) then
          ns.Print(("Neu gespeichert: %s %s (Rang %d)"):format(ns.CHECK, name, rank or 1))
          ns.Refresh()
        end
      end
      return
    end
  end
end

-- ------------------------------------------------------------------ Das aktuell beschworene Pet
ns.activePetSkills = {}   -- [Schlüssel] = { [Rang] = true } (Rang 0 = Rang unbekannt)
ns.activePetName, ns.activePetFamily = nil, nil

local function looksLikeRank(s)
  return type(s) == "string" and not s:find("[\\_/]") and ns.ParseRank(s) ~= nil
end

function ns.ScanActivePet()
  local skills = {}
  local function add(name, sub, spellID)
    local key, r = ns.ResolveSkill(name, spellID)
    if not key and type(name) == "string" and DinosPetSkillsDB.custom[name] then key = name end
    if not key or not ns.skillByKey[key] then return end
    local rank = r or (looksLikeRank(sub) and ns.ParseRank(sub)) or 0
    skills[key] = skills[key] or {}
    skills[key][rank] = true
    -- Wenn unser eigenes Pet diesen Rang gerade im Zauberbuch / auf der Leiste hat, beherrscht der Charakter ihn auch
    if rank and rank >= 1 then
      ns.MarkLearned(name or key, rank, spellID)
    end
  end
  local exists = UnitExists and UnitExists("pet")
  local petName = exists and UnitName("pet") or nil
  if not petName then
    ns.activePetSkills, ns.activePetName, ns.activePetFamily = {}, nil, nil
    return
  end
  -- 1) Pet-Zauberbuch (neue API, wie ForeverBestiaryPetHunter sie nutzt)
  local done = false
  if C_SpellBook and C_SpellBook.HasPetSpells and C_SpellBook.GetSpellBookItemInfo and Enum and Enum.SpellBookSpellBank then
    local ok, num = pcall(C_SpellBook.HasPetSpells)
    if ok and tonumber(num) and num > 0 then
      for i = 1, num do
        local ok2, info = pcall(C_SpellBook.GetSpellBookItemInfo, i, Enum.SpellBookSpellBank.Pet)
        if ok2 and type(info) == "table" then
          local sid = info.spellID or info.actionID
          local sub = info.subName
          if (not sub or sub == "") and sid and C_Spell and C_Spell.GetSpellSubtext then
            local ok3, s = pcall(C_Spell.GetSpellSubtext, sid)
            if ok3 then sub = s end
          end
          add(info.name, sub, sid)
          done = true
        end
      end
    end
  end
  -- 2) Pet-Zauberbuch (klassische API)
  if not done and HasPetSpells then
    local ok, num = pcall(HasPetSpells)
    num = ok and tonumber(num) or 0
    local book = BOOKTYPE_PET or "pet"
    for i = 1, num do
      local name, sub
      if GetSpellBookItemName then
        name, sub = GetSpellBookItemName(i, book)
      elseif GetSpellName then
        name, sub = GetSpellName(i, book)
      end
      local sid
      if GetSpellBookItemInfo then
        local ok2, _, id = pcall(GetSpellBookItemInfo, i, book)
        if ok2 then sid = id end
      end
      if name then add(name, sub, sid) end
    end
  end
  -- 3) Pet-Aktionsleiste
  if GetPetActionInfo then
    local function pack(...) return { n = select("#", ...), ... } end
    for slot = 1, (NUM_PET_ACTION_SLOTS or 10) do
      local v = pack(pcall(GetPetActionInfo, slot))
      if v[1] and type(v[2]) == "string" then
        local sub, sid
        for i = 3, v.n do
          local x = v[i]
          if not sub and looksLikeRank(x) then sub = x end
          if not sid and type(x) == "number" and spellIndex[x] then sid = x end
        end
        add(v[2], sub, sid)
      end
    end
  end
  -- 4) Was die geöffnete Wildtierausbildung als "bereits bekannt" zeigt
  if ns.craftPetName and ns.craftPetName == petName then
    for key, ranks in pairs(ns.craftPet) do
      if ns.skillByKey[key] then
        skills[key] = skills[key] or {}
        for r in pairs(ranks) do skills[key][r] = true end
      end
    end
  end
  -- Rang 0 (unbekannt) fällt weg, sobald ein echter Rang bekannt ist
  for _, ranks in pairs(skills) do
    if ranks[0] then
      for r in pairs(ranks) do if r > 0 then ranks[0] = nil break end end
    end
  end
  ns.activePetSkills = skills
  ns.activePetName = petName
  ns.activePetFamily = ns.FamilySlug(UnitCreatureFamily and UnitCreatureFamily("pet"))
end

function ns.PetHas(key, rank)
  local t = ns.activePetSkills[key]
  if not t then return false end
  if rank == nil then return next(t) ~= nil end
  return t[rank] and true or false
end

-- Kann das aktuelle Pet diese Fähigkeit überhaupt lernen? (Familie / Ausbilder-Fähigkeit / hat sie schon)
function ns.PetCanUse(rec)
  if not ns.activePetName then return false end
  if ns.PetHas(rec.key) then return true end
  if rec.kind == "general" or rec.kind == "trainer" or rec.kind == "custom" then return true end
  local fam = ns.activePetFamily
  if not fam then return false end
  for _, f in ipairs(rec.fams) do if f == fam then return true end end
  return false
end

-- ------------------------------------------------------------------ Übernahme aus ForeverBestiaryPetHunter
-- Übernimmt aus ForeverBestiaryPetHunterDB:
-- 1) Alle Wildtiere, die DIESER Charakter bereits gezähmt/besessen hat (`history[npcId].c == playerName` sowie
--    `story[playerName].pets` / `story[playerName].ev`): deren bekannte Fähigkeiten + Ränge (aus dem FBPH-Katalog
--    und aus `obs[npcId].ab`) werden automatisch als dauerhaft gelernt übernommen!
-- 2) Eventuelle direkte Skill-Tabellen (`learned`, `petSkills`, `knownSkills`, `trained`).
function ns.ImportFromFBPH()
  local fdb = ns.FBPHDB()
  if not fdb then return 0 end
  local n = 0
  local name = UnitName("player") or "?"
  local realm = (GetRealmName and GetRealmName() or ""):gsub("%s", "")

  -- 1) Eigene gezähmte / besessene Wildtiere aus FBPH-Historie & Story auslesen
  local myNpcs = {}
  if type(fdb.history) == "table" then
    for npcId, h in pairs(fdb.history) do
      if type(h) == "table" and (not h.c or h.c == name or h.c == (name .. "-" .. realm)) then
        myNpcs[tonumber(npcId) or npcId] = true
      end
    end
  end
  if type(fdb.story) == "table" then
    local st = fdb.story[name] or fdb.story[name .. "-" .. realm]
    if type(st) == "table" then
      for _, p in pairs(type(st.pets) == "table" and st.pets or {}) do
        if type(p) == "table" and p.id then myNpcs[tonumber(p.id) or p.id] = true end
      end
      for _, e in ipairs(type(st.ev) == "table" and st.ev or {}) do
        if type(e) == "table" and e.id and (e.k == "tame" or e.k == "had" or e.k == "stable") then
          myNpcs[tonumber(e.id) or e.id] = true
        end
      end
    end
  end

  if next(myNpcs) then
    local beastById = {}
    for _, b in ipairs(ns.FBPH and ns.FBPH.beasts or {}) do
      if b.id then beastById[b.id] = b end
    end
    local obs = type(fdb.obs) == "table" and fdb.obs or {}
    local famSpec = {}
    for slug, f in pairs(ns.FBPH and ns.FBPH.families or {}) do
      for _, ab in ipairs(f.abil or {}) do
        local rec = ns.skillByKey[ab]
        if rec and rec.kind == "special" and #(rec.fams or {}) == 1 then
          famSpec[slug] = ab
        end
      end
    end
    for npcId in pairs(myNpcs) do
      local b = beastById[npcId]
      for _, t in ipairs(b and b.t or {}) do
        local sk, rk = t[1], tonumber(t[2])
        if sk and rk and ns.skillByKey[sk] and ns.MarkLearned(sk, rk) then n = n + 1 end
      end
      local o = obs[npcId]
      if type(o) == "table" and type(o.ab) == "table" then
        for sk, rk in pairs(o.ab) do
          rk = tonumber(rk)
          if sk and rk and ns.skillByKey[sk] and ns.MarkLearned(sk, rk) then n = n + 1 end
        end
      end
      -- Familien-Spezialfähigkeit des gezähmten Tiers anhand seines Levels ergänzen (z. B. Spinne -> Gespinst)
      local fam = (b and b.f) or (type(o) == "table" and o.f)
      local lvl = (b and (b.l2 or b.l1)) or (type(o) == "table" and tonumber(o.l2 or o.l1))
      local spec = fam and famSpec[fam]
      if spec and lvl and ns.skillByKey[spec] then
        local bestR = 0
        for r, rk in pairs(ns.skillByKey[spec].ranks) do
          if rk.l and rk.l <= lvl and r > bestR then bestR = r end
        end
        if bestR > 0 and ns.MarkLearned(spec, bestR) then n = n + 1 end
      end
    end
  end

  -- 2) Direkte Skill-Tabellen (falls vorhanden)
  local function take(t)
    if type(t) ~= "table" then return end
    for skill, v in pairs(t) do
      if type(skill) == "string" and ns.ResolveSkill((ns.SplitNameRank(skill))) then
        if type(v) == "table" then
          for r, on in pairs(v) do
            if on and tonumber(r) and ns.MarkLearned(skill, tonumber(r)) then n = n + 1 end
          end
        elseif tonumber(v) then
          if ns.MarkLearned(skill, tonumber(v)) then n = n + 1 end
        end
      end
    end
  end
  for _, field in ipairs({ "learned", "petSkills", "knownSkills", "trained" }) do
    local t = fdb[field]
    if type(t) == "table" then
      local mine = t[name .. "-" .. realm] or t[name]
      if type(mine) == "table" then take(mine) elseif not t[name .. "-" .. realm] then take(t) end
    end
  end
  return n
end

-- ------------------------------------------------------------------ Ereignisse
local ev = CreateFrame("Frame")
local pending = {}
local function schedule(what, delay)
  if pending[what] then return end
  pending[what] = true
  after(delay or 0.3, function()
    pending[what] = nil
    if what == "craft" then
      ns.ImportFromFBPH()
      ns.ScanCraft()
      ns.ScanActivePet()
    elseif what == "pet" then
      ns.ImportFromFBPH()
      ns.ScanActivePet()
    end
    ns.Refresh()
  end)
end
ns.Schedule = schedule

function ns.Refresh()
  if ns.catalogDirty then ns.BuildCatalog() end
  if ns.RefreshUI then ns.RefreshUI() end
  if ns.UpdateMinimapTooltip then ns.UpdateMinimapTooltip() end
end

ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      DinosPetSkillsDB = type(DinosPetSkillsDB) == "table" and DinosPetSkillsDB or {}
      applyDefaults(DinosPetSkillsDB, DEFAULTS)
    elseif arg1 == "Blizzard_CraftUI" then
      if ns.SetupCraftButton then ns.SetupCraftButton() end
    end
  elseif event == "PLAYER_LOGIN" then
    ns.BuildCatalog()
    local imported = ns.ImportFromFBPH()
    if imported > 0 then
      ns.Print(("%d Ränge aus ForeverBestiaryPetHunter übernommen."):format(imported))
      ns.BuildCatalog()
    end
    if ns.SetupMinimapButton then ns.SetupMinimapButton() end
    if ns.SetupCraftButton then ns.SetupCraftButton() end
    for _, e in ipairs({ "CRAFT_SHOW", "CRAFT_UPDATE", "CRAFT_CLOSE", "SPELLS_CHANGED", "UNIT_PET", "PET_BAR_UPDATE",
      "PLAYER_LEVEL_UP", "CHAT_MSG_SYSTEM", "PLAYER_REGEN_ENABLED" }) do
      pcall(ev.RegisterEvent, ev, e)
    end
    after(3, function() schedule("craft", 0) end)
  elseif event == "CRAFT_SHOW" then
    ns.craftOpen = true
    if ns.SetupCraftButton then ns.SetupCraftButton() end
    schedule("craft", 0.2)
  elseif event == "CRAFT_UPDATE" or event == "SPELLS_CHANGED" then
    schedule("craft", 0.3)
  elseif event == "CRAFT_CLOSE" then
    ns.craftOpen = false
    if ns.UpdateCraftButton then ns.UpdateCraftButton() end
    schedule("pet", 0.2)
  elseif event == "UNIT_PET" then
    if arg1 == "player" then
      ns.craftPet, ns.craftPetName = {}, nil
      schedule("craft", 0.5)
    end
  elseif event == "PET_BAR_UPDATE" then
    schedule("pet", 0.5)
  elseif event == "PLAYER_LEVEL_UP" or event == "PLAYER_REGEN_ENABLED" then
    schedule("ui", 0.2)
  elseif event == "CHAT_MSG_SYSTEM" then
    ns.OnSystemMessage(arg1)
  end
end)

-- ------------------------------------------------------------------ Chat-Befehle
SLASH_DINOSPETSKILLS1 = "/dinopets"
SLASH_DINOSPETSKILLS2 = "/dinoskills"
SlashCmdList["DINOSPETSKILLS"] = function(msg)
  local cmd = ns.norm(msg or "")
  if cmd == "" or cmd == "toggle" then
    ns.Toggle()
  elseif cmd == "scan" then
    local n = ns.ScanCraft()
    ns.ScanActivePet()
    ns.Refresh()
    ns.Print(ns.IsPetTrainingCraft() and ("Wildtierausbildung eingelesen: %d neue Ränge."):format(n)
      or "Öffne zuerst das Fenster \"Wildtierausbildung\".")
  elseif cmd == "minimap" then
    DinosPetSkillsDB.minimap.hide = not DinosPetSkillsDB.minimap.hide
    if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
    ns.Print("Minimap-Button " .. (DinosPetSkillsDB.minimap.hide and "ausgeblendet." or "eingeblendet."))
  elseif cmd == "status" or cmd == "debug" then
    local l, t = ns.Progress()
    ns.Print(("%d / %d Ränge dauerhaft erlernt · Pet: %s (%s) · FBPH geladen: %s · Wildtierausbildung offen: %s"):format(
      l, t, tostring(ns.activePetName or "-"), tostring(ns.activePetFamily or "-"), ns.FBPHLoaded() and "ja" or "nein",
      ns.IsPetTrainingCraft() and "ja" or "nein"))
  else
    ns.Print("/dinopets – Fenster ein/aus · /dinopets scan – Wildtierausbildung einlesen · /dinopets minimap – Minimap-Button ein/aus · /dinopets status")
  end
end
