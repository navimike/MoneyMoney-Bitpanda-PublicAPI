-- Bitpanda extension for MoneyMoney (https://moneymoney.app)
-- Reads fiat wallets, crypto, stocks, ETFs, ETCs, metals, indices and Cash Plus
-- through the Bitpanda Public API (https://docs.public.bitpanda.com).
--
-- Credentials: a Bitpanda API key, entered in the password field (the user name is
--   ignored; the key is also accepted there). Key scopes: "Balances" and "Transaction";
--   according to the Bitpanda docs "Trade (Read)" covers assets, currencies and tickers.
-- Accounts:    one cash account per fiat wallet plus depot accounts – either one depot per
--   asset group (GROUPS) or a single depot, see SPLIT_DEPOTS. MoneyMoney lists accounts
--   only when the bank access is created, so every depot group is created up front.
-- Behaviour:   API errors, missing fields and unexpected values abort the refresh with an
--   error message instead of delivering partial data; transient failures are retried.
--   Every transaction carries its Bitpanda transaction id in the purpose text so that
--   MoneyMoney's duplicate detection can tell equal-looking bookings apart.
--
-- MIT License
--
-- Copyright (c) 2026 Michael Kühn
-- Based on the legacy-API extension by GimliGloinsSon (Copyright (c) 2022),
-- https://github.com/GimliGloinsSon/MoneyMoney-bitpanda-Extension
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.

local SERVICE_NAME  = "Bitpanda (Public API)"
local BASE_URL      = "https://api.public.bitpanda.com/v1/"
local PAGE_SIZE     = 100            -- maximum the API accepts
local MAX_PAGES     = 500            -- hard stop for cursor pagination
local MAX_ATTEMPTS  = 3              -- attempts per request on transient failures
local SINCE_OVERLAP = 7 * 86400      -- re-request this much history before `since`; duplicates are dropped by MoneyMoney
local SPLIT_DEPOTS  = true           -- true: one depot per asset group (GROUPS), false: a single depot for all assets
local MARKET        = "Bitpanda"

WebBanking{
  version     = 2.04,
  url         = "https://web.bitpanda.com/",
  services    = {SERVICE_NAME},
  description = "Bitpanda: Fiat-Wallets, Krypto, Aktien, ETFs, ETCs, Metalle, Indizes und Cash Plus über die Bitpanda Public API"
}

local connection = Connection()
local apiKey

-- Filled in InitializeSession (MoneyMoney runs the script afresh for every session)
local currencyById  = {}   -- currency uuid -> {id, symbol, name}
local currencyBySym = {}   -- "EUR" -> currency uuid
local assetById     = {}   -- asset uuid -> {id, name, symbol, isin, group, type}
local portfolio     = nil  -- positions of GET /portfolio (data[])
local operationsCache = nil -- {from = <iso string or "">, data = operations[]}

-------------------------------------------------------------------------------
-- Depot accounts
-------------------------------------------------------------------------------
local GROUPS = {
  {key = "crypto",   name = "Bitpanda Krypto"},
  {key = "stock",    name = "Bitpanda Aktien"},
  {key = "etf",      name = "Bitpanda ETFs"},
  {key = "etc",      name = "Bitpanda ETCs"},
  {key = "metal",    name = "Bitpanda Metalle"},
  {key = "index",    name = "Bitpanda Indizes"},
  {key = "cashplus", name = "Bitpanda Cash Plus"},
  {key = "other",    name = "Bitpanda Sonstige"},
}
local SINGLE_DEPOT = {key = "all", name = "Bitpanda Depot"}

-- Observed type/group combinations of GET /assets (14 013 assets, Sept 2026):
--   equity_security / equity_stock, equity_etf, equity_complex_etf, equity_complex_etc
--   security        / stock, etf, etc, fiat_earn        (legacy derivative products)
--   cryptocoin      / coin, token, leveraged_token, security_token
--   index           / index
--   commodity       / metal
local function classifyAsset(asset)
  if type(asset) ~= "table" then return "other" end
  local t = string.lower(tostring(asset.type or ""))
  local g = string.lower(tostring(asset.group or ""))

  if t == "cryptocoin" then
    return "crypto"
  elseif t == "index" or g == "index" then
    return "index"
  elseif t == "commodity" or g == "metal" then
    return "metal"
  elseif g == "fiat_earn" or string.find(g, "cash", 1, true) then
    return "cashplus"
  elseif string.find(g, "etf", 1, true) then
    return "etf"
  elseif string.find(g, "etc", 1, true) then
    return "etc"
  elseif string.find(g, "stock", 1, true) then
    return "stock"
  elseif t == "security" or t == "equity_security" then
    return "stock"
  end
  return "other"
end

-------------------------------------------------------------------------------
-- Small utilities
-------------------------------------------------------------------------------
local function trim(s)
  if s == nil then return nil end
  return (string.match(tostring(s), "^%s*(.-)%s*$"))
end

-- Value of a Bitpanda money object {value = "12.34", currency_id = ...} as a number,
-- nil if missing or not numeric. A bare number/string is accepted as well.
local function moneyValue(m)
  if type(m) == "table" then m = m.value end
  return tonumber(m)
end

-- "2026-09-07T14:36:04.610Z" -> POSIX timestamp. Handles "Z" and "+hh:mm" offsets.
local function parseIso8601(s)
  if type(s) ~= "string" then return nil end
  local y, mo, d, h, mi, sec = string.match(s, "^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")
  if y == nil then return nil end
  -- os.time() interprets the fields as local time; isdst = false must stay, otherwise
  -- summer timestamps are off by one hour. The result is shifted to UTC afterwards.
  local t = os.time({year = tonumber(y), month = tonumber(mo), day = tonumber(d),
                     hour = tonumber(h), min = tonumber(mi), sec = tonumber(sec), isdst = false})
  if t == nil then return nil end
  t = t + (os.time(os.date("*t", t)) - os.time(os.date("!*t", t)))
  local sign, oh, om = string.match(s, "([%+%-])(%d%d):?(%d%d)$")
  if sign ~= nil then
    local off = tonumber(oh) * 3600 + tonumber(om) * 60
    if sign == "+" then t = t - off else t = t + off end
  end
  return t
end

local function toIso8601(ts)
  return os.date("!%Y-%m-%dT%H:%M:%S.000Z", math.floor(ts))
end

-- Currency symbol for a currency uuid, nil if unknown (never guessed).
local function currencySymbol(id)
  local c = currencyById[id]
  if c ~= nil then return c.symbol end
  return nil
end

local function assetName(id)
  local a = assetById[id]
  if a ~= nil and a.name ~= nil then return a.name end
  return "Unbekanntes Asset"
end

local function assetSymbol(id)
  local a = assetById[id]
  if a ~= nil then return a.symbol end
  return nil
end

-------------------------------------------------------------------------------
-- HTTP
-------------------------------------------------------------------------------
local function buildQuery(params)
  local parts = {}
  for k, v in pairs(params or {}) do
    table.insert(parts, k .. "=" .. MM.urlencode(tostring(v)))
  end
  table.sort(parts)
  return table.concat(parts, "&")
end

-- Error information of an API response body, nil if the body is not an error.
-- Observed shapes: {"errors":[{"code":"unauthorized","status":401,"title":"..."}]}
-- and {"error":{"code":"not_found"}}; {"message":"..."} is accepted for gateways.
-- Returns {status = number|nil, code = string|nil, text = string}.
local function apiErrorOf(json)
  if type(json) ~= "table" then return {text = "unerwartete Antwort"} end
  if type(json.errors) == "table" and type(json.errors[1]) == "table" then
    local e = json.errors[1]
    local parts = {}
    for _, k in ipairs({"status", "code", "title", "detail"}) do
      if e[k] ~= nil then table.insert(parts, tostring(e[k])) end
    end
    return {status = tonumber(e.status), code = e.code and tostring(e.code) or nil, text = table.concat(parts, " ")}
  end
  if type(json.error) == "table" then
    local e = json.error
    return {status = tonumber(e.status or json.status), code = e.code and tostring(e.code) or nil,
            text = tostring(e.code or e.message or "unbekannt")}
  elseif json.error ~= nil then
    return {status = tonumber(json.status), text = tostring(json.error)}
  end
  if json.data == nil and (json.message ~= nil or json.title ~= nil) then
    return {status = tonumber(json.status or json.statusCode), code = json.code and tostring(json.code) or nil,
            text = tostring(json.message or json.title)}
  end
  return nil
end

-- True for a rejected API key (401). A 403 (e.g. missing scope) is reported as a normal
-- error so that the user sees the reason instead of a generic "credentials wrong".
local function isUnauthorized(info)
  if type(info) ~= "table" then return false end
  if info.status == 401 then return true end
  local c = string.lower(tostring(info.code or ""))
  if c == "unauthorized" or c == "unauthenticated" or c == "invalid_api_key" or c == "invalid_token" then
    return true
  end
  if info.status == nil and info.code == nil then
    return string.find(string.lower(tostring(info.text or "")), "unauthori", 1, true) ~= nil
  end
  return false
end

-- One GET request. Returns (json, nil, nil) or (nil, errorText, errorInfo) with
-- errorInfo = {status=, code=, transient=}. A body without "data" is an error, never
-- "no data": an empty result would make MoneyMoney wipe the stored positions.
local function apiGetOnce(path, params)
  local url = BASE_URL .. path
  local query = buildQuery(params)
  if query ~= "" then url = url .. "?" .. query end

  local headers = {
    ["x-api-key"] = apiKey,
    ["Accept"]    = "application/json",   -- MoneyMoney then returns error bodies instead of aborting
  }

  local ok, content = pcall(function()
    return connection:request("GET", url, nil, nil, headers)
  end)
  if not ok then
    return nil, "Anfrage an " .. path .. " fehlgeschlagen: " .. tostring(content), {transient = true}
  end
  if content == nil or content == "" then
    return nil, "Leere Antwort von " .. path, {transient = true}
  end

  local okJson, json = pcall(function() return JSON(content):dictionary() end)
  if not okJson or type(json) ~= "table" then
    return nil, "Ungültiges JSON von " .. path .. ": " .. string.sub(tostring(content), 1, 120), {transient = true}
  end

  local err = apiErrorOf(json)
  if err ~= nil then
    local transient = err.status == 429 or (err.status ~= nil and err.status >= 500)
    return nil, "API-Fehler bei " .. path .. ": " .. err.text,
           {status = err.status, code = err.code, text = err.text, transient = transient}
  end
  if json.data == nil then
    return nil, "Unerwartete Antwort von " .. path .. " (kein data)", {transient = false}
  end

  return json, nil, nil
end

-- GET with retries for transient failures (transport, empty/invalid body, 429, 5xx).
local function apiGet(path, params)
  local json, err, info
  for attempt = 1, MAX_ATTEMPTS do
    json, err, info = apiGetOnce(path, params)
    if json ~= nil or info == nil or not info.transient or attempt == MAX_ATTEMPTS then
      break
    end
    MM.printStatus("Bitpanda: vorübergehender Fehler, Versuch " .. (attempt + 1) .. "/" .. MAX_ATTEMPTS .. " (" .. tostring(err) .. ")")
    MM.sleep(2 * attempt)
  end
  return json, err, info
end

-- Cursors of the Bitpanda API are base64-encoded credited_at timestamps. Decoded for
-- log and error messages only; anything that does not decode to a timestamp is
-- returned unchanged.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_VALUE = {}
for i = 1, #B64 do B64_VALUE[string.sub(B64, i, i)] = i - 1 end

local function cursorText(cursor)
  if cursor == nil or cursor == "" then return "(Anfang)" end
  local clean = string.gsub(tostring(cursor), "=", "")
  local bytes = {}
  for i = 1, #clean, 4 do
    local n, chars = 0, 0
    for j = 0, 3 do
      local ch = string.sub(clean, i + j, i + j)
      if ch == "" then
        n = n * 64
      else
        local v = B64_VALUE[ch]
        if v == nil then return cursor end
        n = n * 64 + v
        chars = chars + 1
      end
    end
    table.insert(bytes, string.char(math.floor(n / 65536) % 256))
    if chars >= 3 then table.insert(bytes, string.char(math.floor(n / 256) % 256)) end
    if chars >= 4 then table.insert(bytes, string.char(n % 256)) end
  end
  local decoded = table.concat(bytes)
  if string.match(decoded, "^%d%d%d%d%-%d%d%-%d%dT[%d:%.]+Z?$") then return decoded end
  return cursor
end

-- All items of a cursor-paginated endpoint. Returns (items, nil, nil) or (nil, errorText,
-- errorInfo); never partial data. Observed API behaviour (Sept 2026): the cursor is the
-- credited_at of the last item, the last page still carries a next_cursor although
-- has_next_page is false, and an unknown cursor silently returns page 1 again. A cycle
-- is therefore detected on the cursors themselves: a next_cursor that was already used
-- to fetch a page means the API restarted or is stuck, and the refresh is aborted with
-- the page numbers in the message. Every page after the first is logged so that the
-- MoneyMoney protocol shows where a long history breaks. The docs show the pagination
-- fields in camelCase while the API sends snake_case, so both spellings are accepted.
local function apiGetAll(path, params)
  local result = {}
  local usedCursors = {}   -- cursor -> number of the page it fetched
  local cursor = nil
  local pages = 0
  repeat
    local p = {}
    for k, v in pairs(params or {}) do p[k] = v end
    p.page_size = PAGE_SIZE
    if cursor ~= nil then p.cursor = cursor end

    local json, err, info = apiGet(path, p)
    if json == nil then return nil, err, info end

    local data = json.data
    if type(data) ~= "table" then
      return nil, "Unerwarteter Datentyp in der Antwort von " .. path, {transient = false}
    end
    pages = pages + 1
    usedCursors[cursor or ""] = pages
    if pages > 1 then
      MM.printStatus(string.format("%s: Seite %d, %d Einträge, Cursor %s", path, pages, #data, cursorText(cursor)))
    end
    for _, item in ipairs(data) do
      table.insert(result, item)
    end

    local hasNext = json.has_next_page
    if hasNext == nil then hasNext = json.hasNextPage end
    local nextCur = json.next_cursor
    if nextCur == nil then nextCur = json.nextCursor end
    if hasNext == nil and nextCur == nil and #data >= PAGE_SIZE then
      return nil, "Paginierungsfelder fehlen in der Antwort von " .. path, {transient = false}
    end
    if hasNext == true then
      if nextCur == nil or nextCur == "" then
        return nil, "Folgeseite ohne Cursor angekündigt von " .. path, {transient = false}
      end
      if usedCursors[nextCur] ~= nil then
        return nil, string.format(
          "Paginierung von %s wiederholt sich: Seite %d (%d Einträge) verweist mit Cursor %s auf Seite %d. " ..
          "Bitte das Protokoll an den Autor der Extension schicken.",
          path, pages, #data, cursorText(nextCur), usedCursors[nextCur]), {transient = false}
      end
      cursor = nextCur
    else
      cursor = nil
    end
    if cursor ~= nil and pages >= MAX_PAGES then
      return nil, "Zu viele Seiten von " .. path .. " (mehr als " .. MAX_PAGES .. ")", {transient = false}
    end
  until cursor == nil
  return result, nil, nil
end

-------------------------------------------------------------------------------
-- Master data
-------------------------------------------------------------------------------
-- Loads master data for asset ids in batches (the id filter takes a comma separated
-- list). Returns nil or an error text. A placeholder is stored only for ids that a
-- successful answer did not contain; a failed request leaves the cache untouched.
local ASSET_BATCH = 25
local function loadAssets(ids)
  local missing, seen = {}, {}
  for _, id in ipairs(ids) do
    if id ~= nil and assetById[id] == nil and not seen[id] then
      seen[id] = true
      table.insert(missing, id)
    end
  end
  local i = 1
  while i <= #missing do
    local batch = {}
    for j = i, math.min(i + ASSET_BATCH - 1, #missing) do table.insert(batch, missing[j]) end
    local data, err = apiGetAll("assets", {id = table.concat(batch, ",")})
    if data == nil then return err end
    for _, a in ipairs(data) do
      if type(a) == "table" and a.id ~= nil then assetById[a.id] = a end
    end
    for _, id in ipairs(batch) do
      if assetById[id] == nil then
        MM.printStatus("Bitpanda kennt Asset " .. tostring(id) .. " nicht – wird unter 'Sonstige' geführt")
        assetById[id] = {id = id, name = "Unbekanntes Asset " .. string.sub(tostring(id), 1, 8), group = "", type = ""}
      end
    end
    i = i + ASSET_BATCH
  end
  return nil
end

-- Current price via GET /tickers/{assetId}: price, currencySymbol – or nil, nil.
local function tickerPrice(assetId)
  local json = apiGet("tickers/" .. assetId)
  if json ~= nil and type(json.data) == "table" then
    local price = tonumber(json.data.price)
    local sym = currencySymbol(json.data.currency_id)
    if price ~= nil and sym ~= nil then return price, sym end
  end
  return nil, nil
end

-------------------------------------------------------------------------------
-- Session
-------------------------------------------------------------------------------
function SupportsBank(protocol, bankCode)
  return protocol == ProtocolWebBanking and bankCode == SERVICE_NAME
end

-- True if every valued position is valued in the given currency.
local function portfolioValuedIn(positions, currencyId)
  for _, pos in ipairs(positions) do
    local cb = pos.currency_balance
    if type(cb) == "table" and cb.currency_id ~= nil and cb.currency_id ~= currencyId then
      return false
    end
  end
  return true
end

function InitializeSession(protocol, bankCode, username, reserved, password)
  -- The API key is expected in the password field; the user name field is accepted as
  -- well because MoneyMoney shows a generic user name / password dialog for unsigned
  -- extensions. The field that worked last time is tried first (LocalStorage) so that
  -- a key in the "wrong" field does not cost a rejected request on every session.
  local candidates = {}
  for _, c in ipairs({{field = "password", key = password}, {field = "username", key = username}}) do
    local k = trim(c.key)
    if k ~= nil and k ~= "" then table.insert(candidates, {field = c.field, key = k}) end
  end
  if #candidates == 0 then return LoginFailed end
  if #candidates == 2 and candidates[2].field == LocalStorage.apiKeyField then
    candidates[1], candidates[2] = candidates[2], candidates[1]
  end

  MM.printStatus("Lade Portfolio")
  local pf, err, info
  for _, c in ipairs(candidates) do
    apiKey = c.key
    pf, err, info = apiGet("portfolio")
    if pf ~= nil then
      LocalStorage.apiKeyField = c.field
      break
    end
    if not isUnauthorized(info) then return err end
  end
  if pf == nil then return LoginFailed end
  if type(pf.data) ~= "table" or pf.has_next_page == true then
    return "Unerwartete Portfolio-Antwort"
  end
  for _, pos in ipairs(pf.data) do
    if type(pos) ~= "table" or (pos.asset_id == nil and pos.currency_id == nil) then
      return "Unerwartetes Format der Portfolio-Positionen"
    end
  end
  portfolio = pf.data

  MM.printStatus("Lade Währungen")
  local currencies
  currencies, err = apiGet("currencies")
  if currencies == nil then return err end
  if type(currencies.data) ~= "table" or currencies.has_next_page == true then
    return "Unerwartete Antwort von currencies"
  end
  currencyById, currencyBySym = {}, {}
  for _, c in ipairs(currencies.data) do
    if type(c) == "table" and c.id ~= nil and c.symbol ~= nil then
      currencyById[c.id] = c
      currencyBySym[c.symbol] = c.id
    end
  end
  if next(currencyById) == nil then
    return "Bitpanda liefert eine leere Währungsliste"
  end

  -- Depots are kept in EUR (see ListAccounts). If Bitpanda valued the portfolio in
  -- another currency, fetch it again valued in EUR.
  local eurId = currencyBySym["EUR"]
  if eurId ~= nil and not portfolioValuedIn(portfolio, eurId) then
    MM.printStatus("Lade Portfolio in EUR")
    pf, err = apiGet("portfolio", {equivalent_currency_id = eurId})
    if pf == nil then return err end
    if type(pf.data) ~= "table" then return "Unerwartete Portfolio-Antwort" end
    portfolio = pf.data
  end

  -- A portfolio that suddenly has no position at all is far more likely an API glitch
  -- than a liquidated account. Refuse it twice before accepting it, because MoneyMoney
  -- would otherwise overwrite every holding and balance with zero.
  local positions = 0
  for _, pos in ipairs(portfolio) do
    if (moneyValue(pos.balance) or 0) > 0 then positions = positions + 1 end
  end
  local lastPositions = tonumber(LocalStorage.lastPositions) or 0
  if positions == 0 and lastPositions > 0 then
    local streak = (tonumber(LocalStorage.emptyStreak) or 0) + 1
    LocalStorage.emptyStreak = streak
    if streak <= 2 then
      return "Bitpanda liefert ein leeres Portfolio (zuletzt " .. lastPositions .. " Positionen). " ..
             "Aktualisierung abgebrochen, um die gespeicherten Bestände zu schützen; ist das Konto " ..
             "tatsächlich leer, wird dies bei der übernächsten Aktualisierung übernommen."
    end
  end
  LocalStorage.emptyStreak = 0
  LocalStorage.lastPositions = positions

  MM.printStatus("Lade Stammdaten")
  local ids = {}
  for _, pos in ipairs(portfolio) do
    if pos.asset_id ~= nil then table.insert(ids, pos.asset_id) end
  end
  err = loadAssets(ids)
  if err ~= nil then return err end

  operationsCache = nil
  return nil
end

function ListAccounts(knownAccounts)
  local accounts = {}

  -- One cash account per fiat wallet in the portfolio, EUR always.
  local seen = {}
  for _, pos in ipairs(portfolio) do
    local cid = pos.currency_id
    if pos.asset_id == nil and cid ~= nil and not seen[cid] then
      seen[cid] = true
      local sym = currencySymbol(cid)
      if sym == nil then
        MM.printStatus("Fiat-Wallet mit unbekannter Währungs-ID " .. tostring(cid) .. " übersprungen")
      else
        table.insert(accounts, {
          name          = "Bitpanda " .. sym,
          accountNumber = "bitpanda-fiat-" .. string.lower(sym),
          subAccount    = "fiat",
          currency      = sym,
          portfolio     = false,
          type          = AccountTypeGiro,
        })
      end
    end
  end
  local eurId = currencyBySym["EUR"]
  if eurId ~= nil and not seen[eurId] then
    table.insert(accounts, {
      name          = "Bitpanda EUR",
      accountNumber = "bitpanda-fiat-eur",
      subAccount    = "fiat",
      currency      = "EUR",
      portfolio     = false,
      type          = AccountTypeGiro,
    })
  end

  local depots = SPLIT_DEPOTS and GROUPS or {SINGLE_DEPOT}
  for _, g in ipairs(depots) do
    table.insert(accounts, {
      name          = g.name,
      accountNumber = "bitpanda-" .. g.key,
      subAccount    = g.key,
      currency      = "EUR",
      portfolio     = true,
      type          = AccountTypePortfolio,
    })
  end

  return accounts
end

-------------------------------------------------------------------------------
-- Depot positions
-------------------------------------------------------------------------------
-- Returns (security, nil) or (nil, errorText).
local function securityForPosition(pos, accountCurrency)
  local assetId  = pos.asset_id
  local asset    = assetById[assetId]
  local quantity = moneyValue(pos.balance) or 0
  local cb       = pos.currency_balance
  local amount   = moneyValue(cb)          -- nil if Bitpanda delivered no valuation
  local valueCur = accountCurrency
  if type(cb) == "table" and cb.currency_id ~= nil then
    valueCur = currencySymbol(cb.currency_id)
    if valueCur == nil then
      return nil, "Unbekannte Währungs-ID " .. tostring(cb.currency_id) .. " in der Bewertung von " .. assetName(assetId)
    end
  end

  local price = nil
  if amount ~= nil and amount > 0 and quantity > 0 then
    price = amount / quantity
  else
    -- No valuation in the portfolio (e.g. illiquid asset): try the ticker, otherwise
    -- report the position without a value rather than as worth zero.
    local p, sym = tickerPrice(assetId)
    if p ~= nil then
      price, valueCur, amount = p, sym, p * quantity
    else
      amount = nil
    end
  end

  local purchasePrice, purchaseCur = nil, accountCurrency
  local abp = pos.average_buy_price
  if abp ~= nil then
    purchasePrice = moneyValue(abp)
    if purchasePrice == 0 then purchasePrice = nil end
    if type(abp) == "table" and abp.currency_id ~= nil then
      purchaseCur = currencySymbol(abp.currency_id) or purchaseCur
    end
  end

  local sec = {
    name           = assetName(assetId),
    isin           = asset and asset.isin or nil,
    market         = MARKET,
    quantity       = quantity,
    price          = price,
    purchasePrice  = purchasePrice,
    tradeTimestamp = os.time(),
  }
  if valueCur == accountCurrency then
    sec.amount = amount
  else
    -- Valuation only available in another currency: hand it over as original amount,
    -- never as the account-currency amount.
    MM.printStatus("Position " .. sec.name .. " ist in " .. valueCur .. " bewertet, nicht in " .. accountCurrency)
    sec.currencyOfPrice = valueCur
    sec.originalAmount = amount
    sec.currencyOfOriginalAmount = valueCur
  end
  if purchasePrice ~= nil and purchaseCur ~= accountCurrency then
    sec.currencyOfPurchasePrice = purchaseCur
  end
  return sec, nil
end

-------------------------------------------------------------------------------
-- Fiat transactions from GET /operations
-------------------------------------------------------------------------------
local function loadOperations(since)
  local from = ""
  if since ~= nil and since > 0 then
    from = toIso8601(math.max(0, since - SINCE_OVERLAP))
  end
  if operationsCache ~= nil and operationsCache.from == from then
    return operationsCache.data, nil
  end
  local params = {}
  if from ~= "" then params["from"] = from end
  MM.printStatus("Lade Umsätze")
  local ops, err = apiGetAll("operations", params)
  if ops == nil then return nil, err end
  operationsCache = {from = from, data = ops}
  return ops, nil
end

-- Booking texts per transaction type (falls back to the operation type).
local BOOKING_TEXT = {
  deposit    = "Einzahlung",
  withdrawal = "Auszahlung",
  buy        = "Kauf",
  sell       = "Verkauf",
  fee        = "Gebühr",
  tax        = "Steuer",
  dividend   = "Dividende",
  reward     = "Reward",
  interest   = "Zinsen",
}
local ASSET_RELATED = {buy = true, sell = true, fee = true, tax = true, dividend = true, reward = true, interest = true}

local function bookingTextFor(opType, txType)
  local key = txType or opType or "unknown"
  if BOOKING_TEXT[key] ~= nil then return BOOKING_TEXT[key] end
  return (string.gsub(key, "_", " "))
end

-- Asset an operation refers to: an index wins over its constituents, otherwise the
-- first asset leg.
local function operationAssetId(op)
  local first = nil
  for _, tx in ipairs(op.transactions or {}) do
    if tx.index_asset_id ~= nil then return tx.index_asset_id end
    if tx.asset_id ~= nil and first == nil then first = tx.asset_id end
  end
  return first
end

-- The asset leg belonging to a trade: the leg of the operation's asset, else the first
-- asset leg that carries trade information.
local function tradeAssetLeg(op, assetId)
  local first = nil
  for _, tx in ipairs(op.transactions or {}) do
    if tx.asset_id ~= nil and tx.trade ~= nil then
      if tx.asset_id == assetId then return tx end
      if first == nil then first = tx end
    end
  end
  return first
end

-- Fiat legs of all operations for one cash account. A stock exchange order consists of
-- a *_reserve operation (wallet -> exchange wallet) and the executing operation with a
-- transfer leg back, the buy/sell leg and separate fee/tax legs; reserve and transfer
-- legs cancel out in the wallet, so only the remaining legs are booked. Cancelled
-- deposits never touched the wallet and show asset_balance_after = -1.
-- Returns (transactions, nil) or (nil, errorText).
local function transactionsForFiat(account, ops)
  local currencyId = currencyBySym[account.currency]
  if currencyId == nil then
    return nil, "Währung " .. tostring(account.currency) .. " ist bei Bitpanda unbekannt"
  end
  local sym = account.currency

  local ids = {}
  for _, op in ipairs(ops) do
    local id = operationAssetId(op)
    if id ~= nil then table.insert(ids, id) end
  end
  local err = loadAssets(ids)
  if err ~= nil then return nil, err end

  local result = {}
  for _, op in ipairs(ops) do
    local opType = tostring(op.operation_type or "")
    local opId   = tostring(op.operation_id or "?")
    if string.find(opType, "_reserve", 1, true) == nil then
      local assetId = operationAssetId(op)

      for _, tx in ipairs(op.transactions or {}) do
        local txType = tx.transaction_type
        local balanceAfter = moneyValue(tx.asset_balance_after)
        local isFiatLeg = tx.currency_id == currencyId and tx.asset_id == nil
        local isVoid = balanceAfter ~= nil and balanceAfter < 0

        if isFiatLeg and txType ~= "transfer" and not isVoid then
          local value = moneyValue(tx.asset_amount)
          if value == nil then
            return nil, "Betrag fehlt in Operation " .. opId
          end
          value = math.abs(value)
          local flow = string.upper(tostring(tx.flow or ""))
          if flow == "OUTGOING" then
            value = -value
          elseif flow ~= "INCOMING" then
            return nil, "Unbekannte Flussrichtung '" .. tostring(tx.flow) .. "' in Operation " .. opId
          end

          local text = bookingTextFor(opType, txType)
          local name = text
          if assetId ~= nil and ASSET_RELATED[txType] then
            name = text .. ": " .. assetName(assetId)
          elseif opType == "savings_plan" then
            name = "Bitpanda Sparplan"
          elseif opType == "deposit" or opType == "withdrawal" then
            name = "Bitpanda " .. text
          end

          local purposeLines = {}
          if tx.trade ~= nil then
            local leg = tradeAssetLeg(op, assetId)
            local legAmount = leg and moneyValue(leg.asset_amount) or nil
            local rate = tx.trade.rate
            if type(rate) == "table" then rate = rate.value end
            if legAmount ~= nil and rate ~= nil then
              table.insert(purposeLines, string.format("%s %s @ %s %s", tostring(legAmount), assetSymbol(assetId) or "", tostring(rate), sym))
            end
          end
          -- The transaction id keeps equal-looking bookings (same day, amount and text)
          -- distinguishable for MoneyMoney's duplicate detection.
          table.insert(purposeLines, "Bitpanda-Transaktion " .. tostring(tx.transaction_id or opId))

          -- Without a credit timestamp there is no stable booking date: report the
          -- transaction as pending so that MoneyMoney does not accumulate copies of it.
          local ts = parseIso8601(tx.credited_at)
          local booked = ts ~= nil
          if ts == nil then ts = os.time() end

          table.insert(result, {
            name        = name,
            amount      = value,
            currency    = sym,
            bookingDate = ts,
            valueDate   = ts,
            purpose     = table.concat(purposeLines, "\n"),
            bookingText = text,
            booked      = booked,
          })
        end
      end
    end
  end

  -- MoneyMoney expects the newest transaction first (stable sort by index).
  for i, t in ipairs(result) do t._i = i end
  table.sort(result, function(a, b)
    if a.bookingDate ~= b.bookingDate then return a.bookingDate > b.bookingDate end
    return a._i < b._i
  end)
  for _, t in ipairs(result) do t._i = nil end
  return result, nil
end

-------------------------------------------------------------------------------
function RefreshAccount(account, since)
  MM.printStatus("Aktualisiere " .. account.name)
  if portfolio == nil then
    return "Portfolio nicht geladen – Session wurde nicht initialisiert"
  end

  if account.portfolio then
    local securities = {}
    for _, pos in ipairs(portfolio) do
      if pos.asset_id ~= nil and (moneyValue(pos.balance) or 0) > 0 then
        if assetById[pos.asset_id] == nil then
          local err = loadAssets({pos.asset_id})
          if err ~= nil then return err end
        end
        if account.subAccount == SINGLE_DEPOT.key or classifyAsset(assetById[pos.asset_id]) == account.subAccount then
          local sec, err = securityForPosition(pos, account.currency)
          if sec == nil then return err end
          table.insert(securities, sec)
        end
      end
    end
    return {securities = securities}
  end

  -- Cash account: balance from the portfolio, transactions from the operations.
  local currencyId = currencyBySym[account.currency]
  local balance = 0
  for _, pos in ipairs(portfolio) do
    if pos.asset_id == nil and pos.currency_id == currencyId then
      balance = moneyValue(pos.balance) or 0
    end
  end

  local ops, err = loadOperations(since)
  if ops == nil then return err end

  local transactions, terr = transactionsForFiat(account, ops)
  if transactions == nil then return terr end

  return {
    balance      = balance,
    transactions = transactions,
  }
end

function EndSession()
  -- Nothing to do: API keys are stateless.
end
