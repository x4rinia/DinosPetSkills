# 🦕 Dino's Pet-Skills (`DinosPetSkills`)

**by X4rinia und Dino** · *Zusatz-Addon für Forever Bestiary (Pet Hunter)*

**Dino's Pet-Skills** erweitert **Forever Bestiary (Pet Hunter)** in **WoW Forever** um ein dauerhaftes, charakterweites Übersichtsfenster für alle Jäger-Pet-Fähigkeiten und Ränge – unabhängig davon, welches Pet du gerade aktiv bei dir hast.

---

## ⚠️ Voraussetzung (Abhängigkeit)

Dieses Addon benötigt **[Forever Bestiary (Pet Hunter)](https://www.curseforge.com/wow/addons/forever-bestiary-pet-hunter)** (Ordnername: `ForeverBestiaryPetHunter`, CurseForge-Projekt-ID `1712376`).
In der `DinosPetSkills.toc` ist diese Abhängigkeit fest über `## Dependencies: ForeverBestiaryPetHunter` (`RequiredDeps`) hinterlegt.

---

## 📦 Installation über WoWUp (Empfohlen)

1. Stelle sicher, dass **Forever Bestiary (Pet Hunter)** installiert ist.
2. Öffne die **WoWUp**-App.
3. Klicke auf **Addons holen** → **Von URL installieren** (*Install from URL*).
4. Füge folgende GitHub-URL ein:
   ```text
   https://github.com/x4rinia/DinosPetSkills
   ```
5. Klicke auf **Installieren**. WoWUp lädt automatisch das neueste Release herunter und hält das Addon aktuell.

---

## ✨ Features

- **Dauerhafte Speicherung (`SavedVariablesPerCharacter`):**
  Im Standard-Fenster „Wildtierausbildung“ siehst du immer nur die Fähigkeiten deines *aktuell gerufenen* Pets. `DinosPetSkills` speichert alle jemals gelernten Fähigkeiten & Ränge dauerhaft für deinen Jäger – selbst wenn du das Pet freilässt oder in den Stall stellst.
- **Automatische Übernahme aus Forever Bestiary:**
  Bereits gezähmte Wildtiere aus deiner `ForeverBestiaryPetHunter`-Historie werden automatisch erkannt und ihre Fähigkeiten (inklusive niedrigerer Ränge `Rang 1–X` und Familien-Spezialfähigkeiten) direkt als gelernt markiert.
- **Fokus auf echte Pet-Fähigkeiten:**
  Zeigt nur Fähigkeiten an, die man durch Wildtiere erhalten kann (keine Ausbilder-Widerstände, keine Rüstungs-/Ausdauer-Passiva, kein Knurren).
- **Kompakte, eingeklappte Übersicht + separates Wildtier-Seitenfenster:**
  Alle Fähigkeiten starten übersichtlich zugeklappt. Ein Klick auf einen Rang öffnet rechts daneben ein separates Seitenfenster mit allen möglichen Wildtieren (Familie, Level, Zone, Zähmbarkeit).

---

## 🎮 Öffnen im Spiel

- **Chat-Befehle:** `/dinopets` oder `/dinoskills` (weitere Befehle: `/dinopets scan`, `/dinopets minimap`, `/dinopets status`)
- **Minimap-Button:** Frei verschiebbarer Dino-Button am Minimap-Rand (Linksklick: Öffnen/Schließen, Rechtsklick: Neu scannen, Gedrückt halten: Verschieben)
- **Wildtierausbildung:** Direkt-Button **`Dino's Pet-Skills`** oben rechts im Jäger-Fenster „Wildtierausbildung“
