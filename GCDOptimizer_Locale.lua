-- GCDOptimizer_Locale.lua
-- Lightweight localization with client-locale auto + manual override.
-- Keep keys stable; translations can be improved later without touching logic.

local _, NS = ...

NS.Locale = NS.Locale or {}
local L = NS.Locale

local MAP = {}

-- --- helpers ---
local function ClientLocale()
  local lc = (GetLocale and GetLocale()) or "enUS"
  if lc == "enGB" then return "enUS" end
  if lc == "ptPT" then return "ptBR" end
  return lc
end

local function GetOverride()
  if NS.GetConfig then
    local cfg = NS:GetConfig()
    return cfg and cfg.localeOverride
  end
  if _G.GCDOptimizerDB then
    return _G.GCDOptimizerDB.localeOverride
  end
  return nil
end

local function NormalizeLocale(code)
  if not code or code == "" then return "enUS" end
  if code == "auto" then return "auto" end
  if code == "enGB" then return "enUS" end
  if code == "ptPT" then return "ptBR" end
  return code
end

function L:GetActiveLocale()
  local ov = NormalizeLocale(GetOverride() or "auto")
  local lc = (ov ~= "auto") and ov or ClientLocale()
  if not MAP[lc] then return "enUS" end
  return lc
end

function L:Tr(key, fallback)
  local lc = self:GetActiveLocale()
  local t = MAP[lc] or MAP.enUS
  if t and t[key] ~= nil then return t[key] end
  local e = MAP.enUS
  if e and e[key] ~= nil then return e[key] end
  return fallback or key
end

-- Canonical verdict tags (internal keys are English strings used by existing logic).
local TAG_KEY = {
  ["OK"] = "TAG_OK",
  ["Low sample"] = "TAG_LOW_SAMPLE",
  ["Stop sleeping!"] = "TAG_STOP_SLEEPING",
  ["Bad management"] = "TAG_BAD_MANAGEMENT",
  ["Bad management!"] = "TAG_BAD_MANAGEMENT",
  ["Bad server!"] = "TAG_BAD_SERVER",
  ["Press faster!"] = "TAG_PRESS_FASTER",
}

function L:TrTag(tag)
  if not tag or tag == "" then return self:Tr("TAG_OK", "OK") end

  -- normalize variants: "Bad management (...)" etc.
  local base = tag
  if base:find("^Bad management") then base = "Bad management" end
  if base:find("^Press faster") then base = "Press faster!" end
  if base:find("^Stop sleeping") then base = "Stop sleeping!" end
  if base:find("^Low sample") then base = "Low sample" end
  if base:find("^Bad server") then base = "Bad server!" end

  local key = TAG_KEY[base] or TAG_KEY["OK"]
  local head = self:Tr(key, base)

  -- translate suffix tokens like "(resources)"
  local m = tag:match("^Bad management%s*%(([^)]+)%)!$")
  if m then
    local tok = m
    local tkey = "FAILTAG_" .. tok:upper()
    local tval = self:Tr(tkey, tok)
    return head .. " (" .. tval .. ")!"
  end

  if tag == "Bad management!" then return head .. "!" end
  return head
end

-- Public shorthand
function NS:L(key, fallback) return L:Tr(key, fallback) end
function NS:LT(tag) return L:TrTag(tag) end

-- --------------------------------------------------------------------
-- Translations
-- Keep short, UI-friendly, and unambiguous.
-- --------------------------------------------------------------------

-- =========================
-- English (base)
-- =========================
MAP.enUS = {
  OPT_LANGUAGE = "Language",
  OPT_LANGUAGE_AUTO = "Auto (client)",
  OPT_RELOAD = "Reload UI",
  OPT_APPLY = "Apply",
  OPT_CLOSE = "Close",

  HUD_GCD = "GCD",
  HUD_SQW = "Spell Queue Window",
  HUD_REC_SQW = "Recommended SQW",
  HUD_VERDICT = "Verdict",

  BTN_EXPAND = "Expand",
  BTN_COLLAPSE = "Collapse",
  MENU_START = "Start",
  MENU_STOP = "Stop",
  MENU_RESET = "Reset",
  MENU_EXPAND = "Expand",
  MENU_COLLAPSE = "Collapse",
  MENU_SET_SQW = "Set SQW",
  MENU_SHOW = "Show",
  MENU_HIDE = "Hide",
  MENU_CLOSE = "Close",

  SQW_TITLE = "Set Spell Queue Window",
  SQW_PROMPT = "Value (ms):",
  SQW_OK = "OK",
  SQW_RELOAD = "Reload UI",
  SQW_BAD_NUMBER = "Bad number",

  SEC_SUMMARY = "Summary",
  SEC_INPUT = "Queue & input",
  SEC_LATENCY = "Latency",
  SEC_LOSSES = "Losses",
  SEC_FAILS = "Failures",
  SEC_EXPLAIN = "Explain",

  MET_TIME = "Time",
  MET_SEGMENT = "Segment",
  MET_EFF = "Efficiency",
  MET_POSSIBLE = "Possible GCDs",
  MET_ACTUAL = "Actual GCDs",
  MET_LOST = "Lost GCDs",
  MET_WASTED = "Wasted GCDs",
  MET_WASTED_PM = "Wasted per min",
  MET_TAIL = "Tail GCD",
  MET_GAP_P90 = "Gap p90",
  MET_GAP_NOW = "Current gap",
  MET_QHIT = "Queue hits",
  MET_QCOV = "Queue coverage",
  MET_QUEUE_LEAD_P90 = "Queue lead p90",
  MET_SDQ_PLUS = "Start delay beyond cap",
  MET_AFK_DEN = "AFK samples",
  MET_NO_PRESS = "No-press share",
  MET_AFK_PRESS = "Pressing during gaps",
  MET_SDQ_P90 = "Queued-start delay p90",
  MET_SDW_MED = "Start delay median",
  MET_SDW_P90 = "Start delay p90",
  MET_LATE_MED = "Late press median",
  MET_LATE_P90 = "Late press p90",
  MET_AFTER_MED = "After-GCD press median",
  MET_AFTER_P90 = "After-GCD press p90",

  ANL_IDLE = "Idle",
  ANL_LOST_RATE = "Lost rate",

  MET_FAIL_TOTAL = "Total fails",
  MET_FAIL_TOP = "Top fail reason",
  MET_FAIL_TOP_SHARE = "Top share",
  MET_FAIL_RES_SHARE = "Resource share",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "Low sample",
  TAG_STOP_SLEEPING = "Stop sleeping!",
  TAG_BAD_MANAGEMENT = "Bad management",
  TAG_BAD_SERVER = "Bad server!",
  TAG_PRESS_FASTER = "Press faster!",

  FAILTAG_RESOURCES = "resources",
  FAILTAG_RES = "resources",
  FAILTAG_CD = "cooldowns",
  FAILTAG_TARGET = "target",
  FAILTAG_RANGE = "range",
  FAILTAG_LOS = "LoS",
  FAILTAG_MOVING = "moving",
  FAILTAG_OTHER = "other",
}

-- =========================
-- Russian
-- =========================
MAP.ruRU = {
  OPT_LANGUAGE = "Язык",
  OPT_LANGUAGE_AUTO = "Авто (клиент)",
  OPT_RELOAD = "Перезагрузка UI",
  OPT_APPLY = "Применить",
  OPT_CLOSE = "Закрыть",

  HUD_GCD = "GCD",
  HUD_SQW = "Spell Queue Window",
  HUD_REC_SQW = "Рекоменд. SQW",
  HUD_VERDICT = "Вердикт",

  BTN_EXPAND = "Развернуть",
  BTN_COLLAPSE = "Свернуть",
  MENU_START = "Старт",
  MENU_STOP = "Стоп",
  MENU_RESET = "Сброс",
  MENU_EXPAND = "Развернуть",
  MENU_COLLAPSE = "Свернуть",
  MENU_SET_SQW = "Задать SQW",
  MENU_SHOW = "Показать",
  MENU_HIDE = "Скрыть",
  MENU_CLOSE = "Закрыть",

  SQW_TITLE = "Spell Queue Window",
  SQW_PROMPT = "Значение (мс):",
  SQW_OK = "ОК",
  SQW_RELOAD = "Перезагрузка",
  SQW_BAD_NUMBER = "Кривое число",

  SEC_SUMMARY = "Сводка",
  SEC_INPUT = "Очередь и ввод",
  SEC_LATENCY = "Задержки",
  SEC_LOSSES = "Потери",
  SEC_FAILS = "Фейлы",
  SEC_EXPLAIN = "Пояснение",

  MET_TIME = "Время",
  MET_SEGMENT = "Сегмент",
  MET_EFF = "Эффективность",
  MET_POSSIBLE = "Возможные GCD",
  MET_ACTUAL = "Фактические GCD",
  MET_LOST = "Потеря GCD",
  MET_WASTED = "Пустые GCD",
  MET_WASTED_PM = "Пустые в мин",
  MET_TAIL = "Хвост GCD",
  MET_GAP_P90 = "Пауза p90",
  MET_GAP_NOW = "Пауза сейчас",
  MET_QHIT = "Попадание в очередь",
  MET_QCOV = "Покрытие очередью",
  MET_QUEUE_LEAD_P90 = "Опережение очереди p90",
  MET_SDQ_PLUS = "Старт за пределом капа",
  MET_AFK_DEN = "AFK-замеров",
  MET_NO_PRESS = "Без нажатий",
  MET_AFK_PRESS = "Жмёшь в паузу",
  MET_SDQ_P90 = "Задержка старта p90",
  MET_SDW_MED = "Старт: медиана",
  MET_SDW_P90 = "Старт: p90",
  MET_LATE_MED = "Опоздание: медиана",
  MET_LATE_P90 = "Опоздание: p90",
  MET_AFTER_MED = "После GCD: медиана",
  MET_AFTER_P90 = "После GCD: p90",

  ANL_IDLE = "Простой",
  ANL_LOST_RATE = "Потеря",

  MET_FAIL_TOTAL = "Фейлов всего",
  MET_FAIL_TOP = "Главная причина",
  MET_FAIL_TOP_SHARE = "Доля причины",
  MET_FAIL_RES_SHARE = "Доля ресурсов",

  TAG_OK = "ОК",
  TAG_LOW_SAMPLE = "Мало данных",
  TAG_STOP_SLEEPING = "Хватит спать!",
  TAG_BAD_MANAGEMENT = "Плохая ротация",
  TAG_BAD_SERVER = "Плохой сервер!",
  TAG_PRESS_FASTER = "Жми чаще!",

  FAILTAG_RESOURCES = "ресурсы",
  FAILTAG_RES = "ресурсы",
  FAILTAG_CD = "кд",
  FAILTAG_TARGET = "таргет",
  FAILTAG_RANGE = "дистанция",
  FAILTAG_LOS = "линия обзора",
  FAILTAG_MOVING = "движение",
  FAILTAG_OTHER = "прочее",
}

-- =========================
-- Ukrainian (override / non-official)
-- =========================
MAP.ukUA = {
  OPT_LANGUAGE = "Мова",
  OPT_LANGUAGE_AUTO = "Авто (клієнт)",
  OPT_RELOAD = "Перезавантажити UI",
  OPT_APPLY = "Застосувати",
  OPT_CLOSE = "Закрити",

  HUD_GCD = "GCD",
  HUD_SQW = "Вікно черги заклять",
  HUD_REC_SQW = "Реком. SQW",
  HUD_VERDICT = "Вердикт",

  BTN_EXPAND = "Розгорнути",
  BTN_COLLAPSE = "Згорнути",
  MENU_START = "Старт",
  MENU_STOP = "Стоп",
  MENU_RESET = "Скинути",
  MENU_EXPAND = "Розгорнути",
  MENU_COLLAPSE = "Згорнути",
  MENU_SET_SQW = "Задати SQW",
  MENU_SHOW = "Показати",
  MENU_HIDE = "Сховати",
  MENU_CLOSE = "Закрити",

  SQW_TITLE = "Spell Queue Window",
  SQW_PROMPT = "Значення (мс):",
  SQW_OK = "ОК",
  SQW_RELOAD = "Перезавантаження",
  SQW_BAD_NUMBER = "Криве число",

  SEC_SUMMARY = "Зведення",
  SEC_INPUT = "Черга та ввід",
  SEC_LATENCY = "Затримки",
  SEC_LOSSES = "Втрати",
  SEC_FAILS = "Фейли",
  SEC_EXPLAIN = "Пояснення",

  MET_TIME = "Час",
  MET_SEGMENT = "Сегмент",
  MET_EFF = "Ефективність",
  MET_POSSIBLE = "Можливі GCD",
  MET_ACTUAL = "Фактичні GCD",
  MET_LOST = "Втрачено GCD",
  MET_WASTED = "Порожні GCD",
  MET_WASTED_PM = "Порожні за хв",
  MET_TAIL = "Хвіст GCD",
  MET_GAP_P90 = "Пауза p90",
  MET_GAP_NOW = "Пауза зараз",
  MET_QHIT = "Влучання в чергу",
  MET_QCOV = "Покриття чергою",
  MET_QUEUE_LEAD_P90 = "Випередження черги p90",
  MET_SDQ_PLUS = "Старт понад кап",
  MET_AFK_DEN = "AFK-вимірів",
  MET_NO_PRESS = "Без натискань",
  MET_AFK_PRESS = "Тиснеш у паузу",
  MET_SDQ_P90 = "Затримка старту p90",
  MET_SDW_MED = "Старт: медіана",
  MET_SDW_P90 = "Старт: p90",
  MET_LATE_MED = "Запізнення: медіана",
  MET_LATE_P90 = "Запізнення: p90",
  MET_AFTER_MED = "Після GCD: медіана",
  MET_AFTER_P90 = "Після GCD: p90",

  ANL_IDLE = "Простій",
  ANL_LOST_RATE = "Втрата",

  MET_FAIL_TOTAL = "Фейлів всього",
  MET_FAIL_TOP = "Головна причина",
  MET_FAIL_TOP_SHARE = "Частка причини",
  MET_FAIL_RES_SHARE = "Частка ресурсів",

  TAG_OK = "ОК",
  TAG_LOW_SAMPLE = "Мало даних",
  TAG_STOP_SLEEPING = "Досить спати!",
  TAG_BAD_MANAGEMENT = "Погана ротація",
  TAG_BAD_SERVER = "Поганий сервер!",
  TAG_PRESS_FASTER = "Тисни частіше!",

  FAILTAG_RESOURCES = "ресурси",
  FAILTAG_RES = "ресурси",
  FAILTAG_CD = "кд",
  FAILTAG_TARGET = "ціль",
  FAILTAG_RANGE = "дистанція",
  FAILTAG_LOS = "лінія видимості",
  FAILTAG_MOVING = "рух",
  FAILTAG_OTHER = "інше",
}

-- =========================
-- Polish (override / non-official)
-- =========================
MAP.plPL = {
  OPT_LANGUAGE = "Język",
  OPT_LANGUAGE_AUTO = "Auto (klient)",
  OPT_RELOAD = "Przeładuj UI",
  OPT_APPLY = "Zastosuj",
  OPT_CLOSE = "Zamknij",

  HUD_GCD = "GCD",
  HUD_SQW = "Okno kolejki czarów",
  HUD_REC_SQW = "Rekom. SQW",
  HUD_VERDICT = "Werdykt",

  BTN_EXPAND = "Rozwiń",
  BTN_COLLAPSE = "Zwiń",
  MENU_START = "Start",
  MENU_STOP = "Stop",
  MENU_RESET = "Reset",
  MENU_EXPAND = "Rozwiń",
  MENU_COLLAPSE = "Zwiń",
  MENU_SET_SQW = "Ustaw SQW",
  MENU_SHOW = "Pokaż",
  MENU_HIDE = "Ukryj",
  MENU_CLOSE = "Zamknij",

  SQW_TITLE = "Okno kolejki czarów",
  SQW_PROMPT = "Wartość (ms):",
  SQW_OK = "OK",
  SQW_RELOAD = "Przeładuj UI",
  SQW_BAD_NUMBER = "Krzywa liczba",

  SEC_SUMMARY = "Podsumowanie",
  SEC_INPUT = "Kolejka i wejście",
  SEC_LATENCY = "Opóźnienia",
  SEC_LOSSES = "Straty",
  SEC_FAILS = "Faily",
  SEC_EXPLAIN = "Wyjaśnienie",

  MET_TIME = "Czas",
  MET_SEGMENT = "Segment",
  MET_EFF = "Wydajność",
  MET_POSSIBLE = "Możliwe GCD",
  MET_ACTUAL = "Rzeczywiste GCD",
  MET_LOST = "Utracone GCD",
  MET_WASTED = "Puste GCD",
  MET_WASTED_PM = "Puste / min",
  MET_TAIL = "Ogon GCD",
  MET_GAP_P90 = "Przerwa p90",
  MET_GAP_NOW = "Aktualna przerwa",
  MET_QHIT = "Trafienia w kolejkę",
  MET_QCOV = "Pokrycie kolejką",
  MET_QUEUE_LEAD_P90 = "Wyprzedzenie kolejki p90",
  MET_SDQ_PLUS = "Start ponad limit",
  MET_AFK_DEN = "Próbki AFK",
  MET_NO_PRESS = "Udział bez kliku",
  MET_AFK_PRESS = "Klikanie w przerwach",
  MET_SDQ_P90 = "Opóźnienie startu p90",
  MET_SDW_MED = "Start: mediana",
  MET_SDW_P90 = "Start: p90",
  MET_LATE_MED = "Spóźnienie: mediana",
  MET_LATE_P90 = "Spóźnienie: p90",
  MET_AFTER_MED = "Po GCD: mediana",
  MET_AFTER_P90 = "Po GCD: p90",

  ANL_IDLE = "Przestój",
  ANL_LOST_RATE = "Utrata",

  MET_FAIL_TOTAL = "Faily razem",
  MET_FAIL_TOP = "Top powód",
  MET_FAIL_TOP_SHARE = "Udział top",
  MET_FAIL_RES_SHARE = "Udział zasobów",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "Mało danych",
  TAG_STOP_SLEEPING = "Nie śpij!",
  TAG_BAD_MANAGEMENT = "Słaba rotacja",
  TAG_BAD_SERVER = "Słaby serwer!",
  TAG_PRESS_FASTER = "Klikaj szybciej!",

  FAILTAG_RESOURCES = "zasoby",
  FAILTAG_RES = "zasoby",
  FAILTAG_CD = "cooldowny",
  FAILTAG_TARGET = "cel",
  FAILTAG_RANGE = "zasięg",
  FAILTAG_LOS = "linia widzenia",
  FAILTAG_MOVING = "ruch",
  FAILTAG_OTHER = "inne",
}

-- =========================
-- German
-- =========================
MAP.deDE = {
  OPT_LANGUAGE = "Sprache",
  OPT_LANGUAGE_AUTO = "Auto (Client)",
  OPT_RELOAD = "UI neu laden",
  OPT_APPLY = "Anwenden",
  OPT_CLOSE = "Schließen",

  HUD_GCD = "GCD",
  HUD_SQW = "Spell-Queue-Fenster",
  HUD_REC_SQW = "Empf. SQW",
  HUD_VERDICT = "Fazit",

  BTN_EXPAND = "Erweitern",
  BTN_COLLAPSE = "Einklappen",
  MENU_START = "Start",
  MENU_STOP = "Stop",
  MENU_RESET = "Reset",
  MENU_EXPAND = "Erweitern",
  MENU_COLLAPSE = "Einklappen",
  MENU_SET_SQW = "SQW setzen",
  MENU_SHOW = "Anzeigen",
  MENU_HIDE = "Ausblenden",
  MENU_CLOSE = "Schließen",

  SQW_TITLE = "Spell-Queue-Fenster",
  SQW_PROMPT = "Wert (ms):",
  SQW_OK = "OK",
  SQW_RELOAD = "UI neu laden",
  SQW_BAD_NUMBER = "Ungültige Zahl",

  SEC_SUMMARY = "Übersicht",
  SEC_INPUT = "Queue & Eingabe",
  SEC_LATENCY = "Latenz",
  SEC_LOSSES = "Verluste",
  SEC_FAILS = "Fehlschläge",
  SEC_EXPLAIN = "Erklärung",

  MET_TIME = "Zeit",
  MET_SEGMENT = "Segment",
  MET_EFF = "Effizienz",
  MET_POSSIBLE = "Mögliche GCDs",
  MET_ACTUAL = "Tatsächliche GCDs",
  MET_LOST = "Verlorene GCDs",
  MET_WASTED = "Leere GCDs",
  MET_WASTED_PM = "Leer pro Min",
  MET_TAIL = "GCD-Schwanz",
  MET_GAP_P90 = "Lücke p90",
  MET_GAP_NOW = "Aktuelle Lücke",
  MET_QHIT = "Queue-Treffer",
  MET_QCOV = "Queue-Abdeckung",
  MET_QUEUE_LEAD_P90 = "Queue-Vorlauf p90",
  MET_SDQ_PLUS = "Startverzug über Cap",
  MET_AFK_DEN = "AFK-Samples",
  MET_NO_PRESS = "Ohne-Input Anteil",
  MET_AFK_PRESS = "Drücken in Lücken",
  MET_SDQ_P90 = "Queue-Startverzug p90",
  MET_SDW_MED = "Startverzug Median",
  MET_SDW_P90 = "Startverzug p90",
  MET_LATE_MED = "Spät-Input Median",
  MET_LATE_P90 = "Spät-Input p90",
  MET_AFTER_MED = "Nach-GCD Input Median",
  MET_AFTER_P90 = "Nach-GCD Input p90",

  ANL_IDLE = "Leerlauf",
  ANL_LOST_RATE = "Verlustquote",

  MET_FAIL_TOTAL = "Fehlschläge gesamt",
  MET_FAIL_TOP = "Top Grund",
  MET_FAIL_TOP_SHARE = "Top Anteil",
  MET_FAIL_RES_SHARE = "Ressourcen-Anteil",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "Wenig Daten",
  TAG_STOP_SLEEPING = "Nicht schlafen!",
  TAG_BAD_MANAGEMENT = "Schlechte Rotation",
  TAG_BAD_SERVER = "Schlechter Server!",
  TAG_PRESS_FASTER = "Schneller drücken!",

  FAILTAG_RESOURCES = "Ressourcen",
  FAILTAG_RES = "Ressourcen",
  FAILTAG_CD = "Cooldowns",
  FAILTAG_TARGET = "Ziel",
  FAILTAG_RANGE = "Reichweite",
  FAILTAG_LOS = "Sichtlinie",
  FAILTAG_MOVING = "Bewegung",
  FAILTAG_OTHER = "Sonstiges",
}

-- =========================
-- French
-- =========================
MAP.frFR = {
  OPT_LANGUAGE = "Langue",
  OPT_LANGUAGE_AUTO = "Auto (client)",
  OPT_RELOAD = "Recharger l'UI",
  OPT_APPLY = "Appliquer",
  OPT_CLOSE = "Fermer",

  HUD_GCD = "GCD",
  HUD_SQW = "Fenêtre de file",
  HUD_REC_SQW = "SQW conseillé",
  HUD_VERDICT = "Verdict",

  BTN_EXPAND = "Déplier",
  BTN_COLLAPSE = "Replier",
  MENU_START = "Démarrer",
  MENU_STOP = "Arrêter",
  MENU_RESET = "Reset",
  MENU_EXPAND = "Déplier",
  MENU_COLLAPSE = "Replier",
  MENU_SET_SQW = "Régler SQW",
  MENU_SHOW = "Afficher",
  MENU_HIDE = "Masquer",
  MENU_CLOSE = "Fermer",

  SQW_TITLE = "Fenêtre de file",
  SQW_PROMPT = "Valeur (ms) :",
  SQW_OK = "OK",
  SQW_RELOAD = "Recharger l'UI",
  SQW_BAD_NUMBER = "Nombre invalide",

  SEC_SUMMARY = "Résumé",
  SEC_INPUT = "File & saisie",
  SEC_LATENCY = "Latence",
  SEC_LOSSES = "Pertes",
  SEC_FAILS = "Échecs",
  SEC_EXPLAIN = "Explication",

  MET_TIME = "Temps",
  MET_SEGMENT = "Segment",
  MET_EFF = "Efficacité",
  MET_POSSIBLE = "GCD possibles",
  MET_ACTUAL = "GCD réels",
  MET_LOST = "GCD perdus",
  MET_WASTED = "GCD vides",
  MET_WASTED_PM = "Vides / min",
  MET_TAIL = "Queue GCD",
  MET_GAP_P90 = "Écart p90",
  MET_GAP_NOW = "Écart actuel",
  MET_QHIT = "Touches en file",
  MET_QCOV = "Couverture file",
  MET_QUEUE_LEAD_P90 = "Avance file p90",
  MET_SDQ_PLUS = "Retard au-delà du cap",
  MET_AFK_DEN = "Échantillons AFK",
  MET_NO_PRESS = "Part sans clic",
  MET_AFK_PRESS = "Clics pendant écarts",
  MET_SDQ_P90 = "Retard départ p90",
  MET_SDW_MED = "Retard départ médiane",
  MET_SDW_P90 = "Retard départ p90",
  MET_LATE_MED = "Clic tardif médiane",
  MET_LATE_P90 = "Clic tardif p90",
  MET_AFTER_MED = "Après-GCD médiane",
  MET_AFTER_P90 = "Après-GCD p90",

  ANL_IDLE = "Inactivité",
  ANL_LOST_RATE = "Taux perdu",

  MET_FAIL_TOTAL = "Échecs total",
  MET_FAIL_TOP = "Top raison",
  MET_FAIL_TOP_SHARE = "Part top",
  MET_FAIL_RES_SHARE = "Part ressources",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "Peu de données",
  TAG_STOP_SLEEPING = "Arrête de dormir!",
  TAG_BAD_MANAGEMENT = "Mauvaise rotation",
  TAG_BAD_SERVER = "Mauvais serveur!",
  TAG_PRESS_FASTER = "Appuie plus vite!",

  FAILTAG_RESOURCES = "ressources",
  FAILTAG_RES = "ressources",
  FAILTAG_CD = "recharges",
  FAILTAG_TARGET = "cible",
  FAILTAG_RANGE = "portée",
  FAILTAG_LOS = "ligne de vue",
  FAILTAG_MOVING = "en mouvement",
  FAILTAG_OTHER = "autre",
}

-- =========================
-- Spanish (ES)
-- =========================
MAP.esES = {
  OPT_LANGUAGE = "Idioma",
  OPT_LANGUAGE_AUTO = "Auto (cliente)",
  OPT_RELOAD = "Recargar IU",
  OPT_APPLY = "Aplicar",
  OPT_CLOSE = "Cerrar",

  HUD_GCD = "GCD",
  HUD_SQW = "Ventana de cola",
  HUD_REC_SQW = "SQW recomendado",
  HUD_VERDICT = "Veredicto",

  BTN_EXPAND = "Expandir",
  BTN_COLLAPSE = "Contraer",
  MENU_START = "Iniciar",
  MENU_STOP = "Detener",
  MENU_RESET = "Reiniciar",
  MENU_EXPAND = "Expandir",
  MENU_COLLAPSE = "Contraer",
  MENU_SET_SQW = "Ajustar SQW",
  MENU_SHOW = "Mostrar",
  MENU_HIDE = "Ocultar",
  MENU_CLOSE = "Cerrar",

  SQW_TITLE = "Ventana de cola",
  SQW_PROMPT = "Valor (ms):",
  SQW_OK = "OK",
  SQW_RELOAD = "Recargar IU",
  SQW_BAD_NUMBER = "Número inválido",

  SEC_SUMMARY = "Resumen",
  SEC_INPUT = "Cola y entrada",
  SEC_LATENCY = "Latencia",
  SEC_LOSSES = "Pérdidas",
  SEC_FAILS = "Fallos",
  SEC_EXPLAIN = "Explicación",

  MET_TIME = "Tiempo",
  MET_SEGMENT = "Segmento",
  MET_EFF = "Eficiencia",
  MET_POSSIBLE = "GCD posibles",
  MET_ACTUAL = "GCD reales",
  MET_LOST = "GCD perdidos",
  MET_WASTED = "GCD vacíos",
  MET_WASTED_PM = "Vacíos / min",
  MET_TAIL = "Cola GCD",
  MET_GAP_P90 = "Hueco p90",
  MET_GAP_NOW = "Hueco actual",
  MET_QHIT = "Aciertos en cola",
  MET_QCOV = "Cobertura cola",
  MET_QUEUE_LEAD_P90 = "Adelanto cola p90",
  MET_SDQ_PLUS = "Retraso sobre el cap",
  MET_AFK_DEN = "Muestras AFK",
  MET_NO_PRESS = "Sin pulsar",
  MET_AFK_PRESS = "Pulsas en huecos",
  MET_SDQ_P90 = "Retraso inicio p90",
  MET_SDW_MED = "Inicio: mediana",
  MET_SDW_P90 = "Inicio: p90",
  MET_LATE_MED = "Pulsación tarde mediana",
  MET_LATE_P90 = "Pulsación tarde p90",
  MET_AFTER_MED = "Tras GCD: mediana",
  MET_AFTER_P90 = "Tras GCD: p90",

  ANL_IDLE = "Inactivo",
  ANL_LOST_RATE = "Tasa perdida",

  MET_FAIL_TOTAL = "Fallos total",
  MET_FAIL_TOP = "Top motivo",
  MET_FAIL_TOP_SHARE = "Top %",
  MET_FAIL_RES_SHARE = "% recursos",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "Pocos datos",
  TAG_STOP_SLEEPING = "¡No te duermas!",
  TAG_BAD_MANAGEMENT = "Mala rotación",
  TAG_BAD_SERVER = "¡Mal servidor!",
  TAG_PRESS_FASTER = "¡Pulsa más rápido!",

  FAILTAG_RESOURCES = "recursos",
  FAILTAG_RES = "recursos",
  FAILTAG_CD = "enfriamientos",
  FAILTAG_TARGET = "objetivo",
  FAILTAG_RANGE = "alcance",
  FAILTAG_LOS = "línea de visión",
  FAILTAG_MOVING = "movimiento",
  FAILTAG_OTHER = "otro",
}

MAP.esMX = MAP.esES

-- =========================
-- Italian
-- =========================
MAP.itIT = {
  OPT_LANGUAGE = "Lingua",
  OPT_LANGUAGE_AUTO = "Auto (client)",
  OPT_RELOAD = "Ricarica IU",
  OPT_APPLY = "Applica",
  OPT_CLOSE = "Chiudi",

  HUD_GCD = "GCD",
  HUD_SQW = "Finestra coda",
  HUD_REC_SQW = "SQW consigliato",
  HUD_VERDICT = "Verdetto",

  BTN_EXPAND = "Espandi",
  BTN_COLLAPSE = "Comprimi",
  MENU_START = "Avvia",
  MENU_STOP = "Ferma",
  MENU_RESET = "Reset",
  MENU_EXPAND = "Espandi",
  MENU_COLLAPSE = "Comprimi",
  MENU_SET_SQW = "Imposta SQW",
  MENU_SHOW = "Mostra",
  MENU_HIDE = "Nascondi",
  MENU_CLOSE = "Chiudi",

  SQW_TITLE = "Finestra coda",
  SQW_PROMPT = "Valore (ms):",
  SQW_OK = "OK",
  SQW_RELOAD = "Ricarica IU",
  SQW_BAD_NUMBER = "Numero invalido",

  SEC_SUMMARY = "Riepilogo",
  SEC_INPUT = "Coda e input",
  SEC_LATENCY = "Latenza",
  SEC_LOSSES = "Perdite",
  SEC_FAILS = "Fallimenti",
  SEC_EXPLAIN = "Spiegazione",

  MET_TIME = "Tempo",
  MET_SEGMENT = "Segmento",
  MET_EFF = "Efficienza",
  MET_POSSIBLE = "GCD possibili",
  MET_ACTUAL = "GCD reali",
  MET_LOST = "GCD persi",
  MET_WASTED = "GCD vuoti",
  MET_WASTED_PM = "Vuoti / min",
  MET_TAIL = "Coda GCD",
  MET_GAP_P90 = "Gap p90",
  MET_GAP_NOW = "Gap attuale",
  MET_QHIT = "Colpi in coda",
  MET_QCOV = "Copertura coda",
  MET_QUEUE_LEAD_P90 = "Anticipo coda p90",
  MET_SDQ_PLUS = "Ritardo oltre cap",
  MET_AFK_DEN = "Campioni AFK",
  MET_NO_PRESS = "Quota senza tasto",
  MET_AFK_PRESS = "Premi nei gap",
  MET_SDQ_P90 = "Ritardo start p90",
  MET_SDW_MED = "Start: mediana",
  MET_SDW_P90 = "Start: p90",
  MET_LATE_MED = "Tasto in ritardo mediana",
  MET_LATE_P90 = "Tasto in ritardo p90",
  MET_AFTER_MED = "Dopo GCD: mediana",
  MET_AFTER_P90 = "Dopo GCD: p90",

  ANL_IDLE = "Inattivo",
  ANL_LOST_RATE = "Tasso perso",

  MET_FAIL_TOTAL = "Fallimenti totali",
  MET_FAIL_TOP = "Motivo top",
  MET_FAIL_TOP_SHARE = "Quota top",
  MET_FAIL_RES_SHARE = "Quota risorse",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "Pochi dati",
  TAG_STOP_SLEEPING = "Smetti di dormire!",
  TAG_BAD_MANAGEMENT = "Rotazione scarsa",
  TAG_BAD_SERVER = "Server scarso!",
  TAG_PRESS_FASTER = "Premi più veloce!",

  FAILTAG_RESOURCES = "risorse",
  FAILTAG_RES = "risorse",
  FAILTAG_CD = "ricariche",
  FAILTAG_TARGET = "bersaglio",
  FAILTAG_RANGE = "distanza",
  FAILTAG_LOS = "linea di vista",
  FAILTAG_MOVING = "movimento",
  FAILTAG_OTHER = "altro",
}

-- =========================
-- Portuguese (Brazil)
-- =========================
MAP.ptBR = {
  OPT_LANGUAGE = "Idioma",
  OPT_LANGUAGE_AUTO = "Auto (cliente)",
  OPT_RELOAD = "Recarregar IU",
  OPT_APPLY = "Aplicar",
  OPT_CLOSE = "Fechar",

  HUD_GCD = "GCD",
  HUD_SQW = "Janela da fila",
  HUD_REC_SQW = "SQW recomendado",
  HUD_VERDICT = "Veredito",

  BTN_EXPAND = "Expandir",
  BTN_COLLAPSE = "Recolher",
  MENU_START = "Iniciar",
  MENU_STOP = "Parar",
  MENU_RESET = "Reset",
  MENU_EXPAND = "Expandir",
  MENU_COLLAPSE = "Recolher",
  MENU_SET_SQW = "Definir SQW",
  MENU_SHOW = "Mostrar",
  MENU_HIDE = "Ocultar",
  MENU_CLOSE = "Fechar",

  SQW_TITLE = "Janela da fila",
  SQW_PROMPT = "Valor (ms):",
  SQW_OK = "OK",
  SQW_RELOAD = "Recarregar IU",
  SQW_BAD_NUMBER = "Número inválido",

  SEC_SUMMARY = "Resumo",
  SEC_INPUT = "Fila e entrada",
  SEC_LATENCY = "Latência",
  SEC_LOSSES = "Perdas",
  SEC_FAILS = "Falhas",
  SEC_EXPLAIN = "Explicação",

  MET_TIME = "Tempo",
  MET_SEGMENT = "Segmento",
  MET_EFF = "Eficiência",
  MET_POSSIBLE = "GCD possíveis",
  MET_ACTUAL = "GCD reais",
  MET_LOST = "GCD perdidos",
  MET_WASTED = "GCD vazios",
  MET_WASTED_PM = "Vazios / min",
  MET_TAIL = "Cauda GCD",
  MET_GAP_P90 = "Gap p90",
  MET_GAP_NOW = "Gap atual",
  MET_QHIT = "Acertos na fila",
  MET_QCOV = "Cobertura da fila",
  MET_QUEUE_LEAD_P90 = "Antecipação p90",
  MET_SDQ_PLUS = "Atraso acima do cap",
  MET_AFK_DEN = "Amostras AFK",
  MET_NO_PRESS = "Sem apertar",
  MET_AFK_PRESS = "Aperta nos gaps",
  MET_SDQ_P90 = "Atraso de início p90",
  MET_SDW_MED = "Início: mediana",
  MET_SDW_P90 = "Início: p90",
  MET_LATE_MED = "Aperto tarde mediana",
  MET_LATE_P90 = "Aperto tarde p90",
  MET_AFTER_MED = "Após GCD: mediana",
  MET_AFTER_P90 = "Após GCD: p90",

  ANL_IDLE = "Ocioso",
  ANL_LOST_RATE = "Taxa perdida",

  MET_FAIL_TOTAL = "Falhas totais",
  MET_FAIL_TOP = "Motivo top",
  MET_FAIL_TOP_SHARE = "Parte top",
  MET_FAIL_RES_SHARE = "Parte recursos",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "Poucos dados",
  TAG_STOP_SLEEPING = "Pare de dormir!",
  TAG_BAD_MANAGEMENT = "Rotação ruim",
  TAG_BAD_SERVER = "Servidor ruim!",
  TAG_PRESS_FASTER = "Aperte mais rápido!",

  FAILTAG_RESOURCES = "recursos",
  FAILTAG_RES = "recursos",
  FAILTAG_CD = "recargas",
  FAILTAG_TARGET = "alvo",
  FAILTAG_RANGE = "alcance",
  FAILTAG_LOS = "linha de visão",
  FAILTAG_MOVING = "movendo",
  FAILTAG_OTHER = "outro",
}

-- =========================
-- Korean
-- =========================
MAP.koKR = {
  OPT_LANGUAGE = "언어",
  OPT_LANGUAGE_AUTO = "자동(클라이언트)",
  OPT_RELOAD = "UI 재시작",
  OPT_APPLY = "적용",
  OPT_CLOSE = "닫기",

  HUD_GCD = "GCD",
  HUD_SQW = "주문 대기열 창",
  HUD_REC_SQW = "추천 SQW",
  HUD_VERDICT = "판정",

  BTN_EXPAND = "확장",
  BTN_COLLAPSE = "접기",
  MENU_START = "시작",
  MENU_STOP = "중지",
  MENU_RESET = "초기화",
  MENU_EXPAND = "확장",
  MENU_COLLAPSE = "접기",
  MENU_SET_SQW = "SQW 설정",
  MENU_SHOW = "표시",
  MENU_HIDE = "숨김",
  MENU_CLOSE = "닫기",

  SQW_TITLE = "주문 대기열 창",
  SQW_PROMPT = "값(ms):",
  SQW_OK = "확인",
  SQW_RELOAD = "UI 재시작",
  SQW_BAD_NUMBER = "잘못된 숫자",

  SEC_SUMMARY = "요약",
  SEC_INPUT = "대기열/입력",
  SEC_LATENCY = "지연",
  SEC_LOSSES = "손실",
  SEC_FAILS = "실패",
  SEC_EXPLAIN = "설명",

  MET_TIME = "시간",
  MET_SEGMENT = "세그먼트",
  MET_EFF = "효율",
  MET_POSSIBLE = "가능 GCD",
  MET_ACTUAL = "실제 GCD",
  MET_LOST = "잃은 GCD",
  MET_WASTED = "빈 GCD",
  MET_WASTED_PM = "분당 빈 GCD",
  MET_TAIL = "꼬리 GCD",
  MET_GAP_P90 = "공백 p90",
  MET_GAP_NOW = "현재 공백",
  MET_QHIT = "대기열 적중",
  MET_QCOV = "대기열 커버",
  MET_QUEUE_LEAD_P90 = "대기열 선행 p90",
  MET_SDQ_PLUS = "캡 초과 지연",
  MET_AFK_DEN = "AFK 샘플",
  MET_NO_PRESS = "무입력 비율",
  MET_AFK_PRESS = "공백 중 입력",
  MET_SDQ_P90 = "대기열 시작 지연 p90",
  MET_SDW_MED = "시작 지연 중위",
  MET_SDW_P90 = "시작 지연 p90",
  MET_LATE_MED = "늦은 입력 중위",
  MET_LATE_P90 = "늦은 입력 p90",
  MET_AFTER_MED = "GCD 후 입력 중위",
  MET_AFTER_P90 = "GCD 후 입력 p90",

  ANL_IDLE = "정지",
  ANL_LOST_RATE = "손실률",

  MET_FAIL_TOTAL = "실패 총합",
  MET_FAIL_TOP = "최다 원인",
  MET_FAIL_TOP_SHARE = "최다 비율",
  MET_FAIL_RES_SHARE = "자원 비율",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "데이터 부족",
  TAG_STOP_SLEEPING = "자지 마!",
  TAG_BAD_MANAGEMENT = "로테이션 불량",
  TAG_BAD_SERVER = "서버 문제!",
  TAG_PRESS_FASTER = "더 빨리!",

  FAILTAG_RESOURCES = "자원",
  FAILTAG_RES = "자원",
  FAILTAG_CD = "재사용 대기시간",
  FAILTAG_TARGET = "대상",
  FAILTAG_RANGE = "사거리",
  FAILTAG_LOS = "시야",
  FAILTAG_MOVING = "이동",
  FAILTAG_OTHER = "기타",
}

-- =========================
-- Chinese (Simplified)
-- =========================
MAP.zhCN = {
  OPT_LANGUAGE = "语言",
  OPT_LANGUAGE_AUTO = "自动(客户端)",
  OPT_RELOAD = "重载界面",
  OPT_APPLY = "应用",
  OPT_CLOSE = "关闭",

  HUD_GCD = "GCD",
  HUD_SQW = "技能队列窗口",
  HUD_REC_SQW = "推荐SQW",
  HUD_VERDICT = "结论",

  BTN_EXPAND = "展开",
  BTN_COLLAPSE = "收起",
  MENU_START = "开始",
  MENU_STOP = "停止",
  MENU_RESET = "重置",
  MENU_EXPAND = "展开",
  MENU_COLLAPSE = "收起",
  MENU_SET_SQW = "设置SQW",
  MENU_SHOW = "显示",
  MENU_HIDE = "隐藏",
  MENU_CLOSE = "关闭",

  SQW_TITLE = "技能队列窗口",
  SQW_PROMPT = "数值(ms):",
  SQW_OK = "确定",
  SQW_RELOAD = "重载界面",
  SQW_BAD_NUMBER = "数字不对",

  SEC_SUMMARY = "概要",
  SEC_INPUT = "队列与输入",
  SEC_LATENCY = "延迟",
  SEC_LOSSES = "损失",
  SEC_FAILS = "失败",
  SEC_EXPLAIN = "说明",

  MET_TIME = "时间",
  MET_SEGMENT = "段",
  MET_EFF = "效率",
  MET_POSSIBLE = "可能GCD",
  MET_ACTUAL = "实际GCD",
  MET_LOST = "丢失GCD",
  MET_WASTED = "空GCD",
  MET_WASTED_PM = "每分钟空GCD",
  MET_TAIL = "尾巴GCD",
  MET_GAP_P90 = "间隔p90",
  MET_GAP_NOW = "当前间隔",
  MET_QHIT = "队列命中",
  MET_QCOV = "队列覆盖",
  MET_QUEUE_LEAD_P90 = "队列提前p90",
  MET_SDQ_PLUS = "超上限起手延迟",
  MET_AFK_DEN = "AFK样本",
  MET_NO_PRESS = "无按键占比",
  MET_AFK_PRESS = "空档按键占比",
  MET_SDQ_P90 = "队列起手延迟p90",
  MET_SDW_MED = "起手延迟中位数",
  MET_SDW_P90 = "起手延迟p90",
  MET_LATE_MED = "迟按中位数",
  MET_LATE_P90 = "迟按p90",
  MET_AFTER_MED = "GCD后按键中位数",
  MET_AFTER_P90 = "GCD后按键p90",

  ANL_IDLE = "发呆",
  ANL_LOST_RATE = "损失率",

  MET_FAIL_TOTAL = "失败总数",
  MET_FAIL_TOP = "最多原因",
  MET_FAIL_TOP_SHARE = "最多占比",
  MET_FAIL_RES_SHARE = "资源占比",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "样本不足",
  TAG_STOP_SLEEPING = "别睡了！",
  TAG_BAD_MANAGEMENT = "循环很差",
  TAG_BAD_SERVER = "服务器问题！",
  TAG_PRESS_FASTER = "按快点！",

  FAILTAG_RESOURCES = "资源",
  FAILTAG_RES = "资源",
  FAILTAG_CD = "冷却",
  FAILTAG_TARGET = "目标",
  FAILTAG_RANGE = "距离",
  FAILTAG_LOS = "视线",
  FAILTAG_MOVING = "移动",
  FAILTAG_OTHER = "其他",
}

-- =========================
-- Chinese (Traditional)
-- =========================
MAP.zhTW = {
  OPT_LANGUAGE = "語言",
  OPT_LANGUAGE_AUTO = "自動(客戶端)",
  OPT_RELOAD = "重載介面",
  OPT_APPLY = "套用",
  OPT_CLOSE = "關閉",

  HUD_GCD = "GCD",
  HUD_SQW = "技能佇列視窗",
  HUD_REC_SQW = "推薦SQW",
  HUD_VERDICT = "結論",

  BTN_EXPAND = "展開",
  BTN_COLLAPSE = "收起",
  MENU_START = "開始",
  MENU_STOP = "停止",
  MENU_RESET = "重置",
  MENU_EXPAND = "展開",
  MENU_COLLAPSE = "收起",
  MENU_SET_SQW = "設定SQW",
  MENU_SHOW = "顯示",
  MENU_HIDE = "隱藏",
  MENU_CLOSE = "關閉",

  SQW_TITLE = "技能佇列視窗",
  SQW_PROMPT = "數值(ms):",
  SQW_OK = "確定",
  SQW_RELOAD = "重載介面",
  SQW_BAD_NUMBER = "數字不對",

  SEC_SUMMARY = "概要",
  SEC_INPUT = "佇列與輸入",
  SEC_LATENCY = "延遲",
  SEC_LOSSES = "損失",
  SEC_FAILS = "失敗",
  SEC_EXPLAIN = "說明",

  MET_TIME = "時間",
  MET_SEGMENT = "段",
  MET_EFF = "效率",
  MET_POSSIBLE = "可能GCD",
  MET_ACTUAL = "實際GCD",
  MET_LOST = "丟失GCD",
  MET_WASTED = "空GCD",
  MET_WASTED_PM = "每分鐘空GCD",
  MET_TAIL = "尾巴GCD",
  MET_GAP_P90 = "間隔p90",
  MET_GAP_NOW = "目前間隔",
  MET_QHIT = "佇列命中",
  MET_QCOV = "佇列覆蓋",
  MET_QUEUE_LEAD_P90 = "佇列提前p90",
  MET_SDQ_PLUS = "超上限起手延遲",
  MET_AFK_DEN = "AFK樣本",
  MET_NO_PRESS = "無按鍵占比",
  MET_AFK_PRESS = "空檔按鍵占比",
  MET_SDQ_P90 = "佇列起手延遲p90",
  MET_SDW_MED = "起手延遲中位數",
  MET_SDW_P90 = "起手延遲p90",
  MET_LATE_MED = "遲按中位數",
  MET_LATE_P90 = "遲按p90",
  MET_AFTER_MED = "GCD後按鍵中位數",
  MET_AFTER_P90 = "GCD後按鍵p90",

  ANL_IDLE = "發呆",
  ANL_LOST_RATE = "損失率",

  MET_FAIL_TOTAL = "失敗總數",
  MET_FAIL_TOP = "最多原因",
  MET_FAIL_TOP_SHARE = "最多占比",
  MET_FAIL_RES_SHARE = "資源占比",

  TAG_OK = "OK",
  TAG_LOW_SAMPLE = "樣本不足",
  TAG_STOP_SLEEPING = "別睡了！",
  TAG_BAD_MANAGEMENT = "循環很差",
  TAG_BAD_SERVER = "伺服器問題！",
  TAG_PRESS_FASTER = "按快點！",

  FAILTAG_RESOURCES = "資源",
  FAILTAG_RES = "資源",
  FAILTAG_CD = "冷卻",
  FAILTAG_TARGET = "目標",
  FAILTAG_RANGE = "距離",
  FAILTAG_LOS = "視線",
  FAILTAG_MOVING = "移動",
  FAILTAG_OTHER = "其他",
}
