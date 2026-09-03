// /**
//  * @version   1.1
//  * @package   Omarchy Classic Desktop (OCD)
//  * @author    Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

// AppMatcher.js — appId -> {name, icon} resolution for ocd's dock/Exposé.
//
// Chromium web apps launched by Omarchy report WM_CLASS/appId in the form
// chrome-<host>_<path>-<Profile> (confirmed format, see AGENTS.md),
// which a normal desktop-entry-by-class lookup won't match. ocd keeps a
// small built-in seed map for Omarchy's stock web apps plus a user-editable
// override at ~/.config/omarchy/ocd/appid-overrides.json, which is merged
// on top of (and can override) the built-in seed.
//
// appid-overrides.json schema — a flat object keyed by the exact appId:
//   {
//     "chrome-mail.google.com_mail_u_0-Default": { "name": "Gmail", "icon": "gmail" },
//     "some-other-appid": { "desktopId": "org.some.App" }
//   }
// Either "desktopId" (resolved via DesktopEntries.byId, preferred — picks
// up the entry's real name/icon) or an explicit "name"/"icon" pair works;
// "desktopId" wins if both are present. Missing "icon" degrades to a
// generic icon, never to a missing/blank entry.
.pragma library

var DEFAULT_OVERRIDES = {
  "chrome-mail.google.com_mail_u_0-Default": { name: "Gmail", icon: "gmail" },
  "chrome-app.slack.com_-Default": { name: "Slack", icon: "slack" },
  "chrome-calendar.google.com_calendar_u_0_r-Default": { name: "Calendar", icon: "google-calendar" },
  "chrome-www.youtube.com_-Default": { name: "YouTube", icon: "youtube" }
}

var _overrides = null

function loadOverrides(rawJson) {
  var parsed = {}
  try {
    if (rawJson && rawJson.trim().length > 0) parsed = JSON.parse(rawJson)
  } catch (e) {
    parsed = {}
  }
  var merged = {}
  for (var k in DEFAULT_OVERRIDES) merged[k] = DEFAULT_OVERRIDES[k]
  for (var k2 in parsed) merged[k2] = parsed[k2]
  _overrides = merged
  return merged
}

// resolve(appId, title, desktopEntriesApi) -> { name, icon }
// desktopEntriesApi is the Quickshell.DesktopEntries singleton (or null).
// Never returns an empty name: falls back to the window title, then the
// raw appId, so a window never "vanishes" for lack of a match.
function resolve(appId, title, desktopEntriesApi) {
  var overrides = _overrides || DEFAULT_OVERRIDES
  var override = appId ? overrides[appId] : undefined

  if (override) {
    if (override.desktopId && desktopEntriesApi) {
      try {
        var entry = desktopEntriesApi.byId(override.desktopId)
        if (entry) return { name: entry.name || override.name || appId, icon: entry.icon || override.icon || "" }
      } catch (e) { /* fall through */ }
    }
    if (override.name || override.icon) {
      return { name: override.name || appId, icon: override.icon || "" }
    }
  }

  if (desktopEntriesApi && appId) {
    try {
      var direct = desktopEntriesApi.byId(appId)
      if (direct) return { name: direct.name || appId, icon: direct.icon || "" }
      if (desktopEntriesApi.heuristicLookup) {
        var heuristic = desktopEntriesApi.heuristicLookup(appId)
        if (heuristic) return { name: heuristic.name || appId, icon: heuristic.icon || "" }
      }
    } catch (e) { /* fall through to the generic fallback below */ }
  }

  return { name: (title && title.length > 0) ? title : (appId || "Unknown"), icon: "" }
}

function shQuote(s) {
  return "'" + String(s).replace(/'/g, "'\\''") + "'"
}
