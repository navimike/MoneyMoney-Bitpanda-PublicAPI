-- Replay-Test: fährt die Extension gegen echte, gespeicherte API-Antworten aus "API Abrufe/".
-- Aufruf im Extension-Ordner (Lua 5.3, z. B. texlua):
--   TZ=Europe/Berlin texlua bitpanda-api-replay.lua [bitpanda-api.lua] [API Abrufe]
--
-- Nutzt bp_samples/operations_page_N.json (fetch-samples-v2.sh) für die volle Historie, sonst bp_operations.json.
-- Gibt keine Beträge aus, nur Strukturen, Zähler und Konsistenzprüfungen:
--   * Konten, Depotpositionen (Name, Klassifizierung, Preis = Wert/Menge?)
--   * Fiat-Umsätze: Anzahl je Typ, Datumsbereich, unbekannte Namen, booked-Flag
--   * Abgleich: Summe der gebuchten Umsätze == Kontobewegung laut asset_balance_after
--   * Fehlerpfad: echter Ticker-Fehler {"error":{"code":"not_found"}}

local EXT = arg and arg[1] or "bitpanda-api.lua"
local DIR = arg and arg[2] or "API Abrufe"

-- ---------------------------------------------------------------- minimal JSON decoder
local function jsonDecode(s)
  local pos = 1
  local function skip() pos = string.find(s, "%S", pos) or (#s + 1) end
  local parseValue
  local function parseString()
    local out, i = {}, pos + 1
    while true do
      local c = string.sub(s, i, i)
      if c == "" then error("unterminated string") end
      if c == '"' then pos = i + 1; return table.concat(out) end
      if c == "\\" then
        local e = string.sub(s, i + 1, i + 1)
        local map = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }
        if e == "u" then
          local cp = tonumber(string.sub(s, i + 2, i + 5), 16)
          table.insert(out, utf8.char(cp)); i = i + 6
        else
          table.insert(out, map[e] or e); i = i + 2
        end
      else
        table.insert(out, c); i = i + 1
      end
    end
  end
  function parseValue()
    skip()
    local c = string.sub(s, pos, pos)
    if c == "{" then
      local obj = {}; pos = pos + 1; skip()
      if string.sub(s, pos, pos) == "}" then pos = pos + 1; return obj end
      while true do
        skip(); local k = parseString(); skip()
        assert(string.sub(s, pos, pos) == ":", "expected ':' at " .. pos); pos = pos + 1
        obj[k] = parseValue(); skip()
        local d = string.sub(s, pos, pos); pos = pos + 1
        if d == "}" then return obj end
        assert(d == ",", "expected ',' at " .. pos)
      end
    elseif c == "[" then
      local arr = {}; pos = pos + 1; skip()
      if string.sub(s, pos, pos) == "]" then pos = pos + 1; return arr end
      while true do
        table.insert(arr, parseValue()); skip()
        local d = string.sub(s, pos, pos); pos = pos + 1
        if d == "]" then return arr end
        assert(d == ",", "expected ',' at " .. pos)
      end
    elseif c == '"' then
      return parseString()
    elseif string.sub(s, pos, pos + 3) == "true" then pos = pos + 4; return true
    elseif string.sub(s, pos, pos + 4) == "false" then pos = pos + 5; return false
    elseif string.sub(s, pos, pos + 3) == "null" then pos = pos + 4; return nil
    else
      local numStr = string.match(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      assert(numStr and numStr ~= "", "unexpected token at " .. pos .. ": " .. string.sub(s, pos, pos + 10))
      pos = pos + #numStr
      return tonumber(numStr)
    end
  end
  local v = parseValue()
  return v
end

local function readFile(p)
  local f = assert(io.open(p, "rb"), "cannot open " .. p)
  local c = f:read("a"); f:close(); return c
end
local function loadJson(p) return jsonDecode(readFile(p)) end

-- ---------------------------------------------------------------- real responses
-- Portfolio: prefer the snapshot taken together with the full operations history
-- (fetch-samples-v2.sh writes bp_samples/portfolio.json in the same run).
local portfolioFile = DIR .. "/bp_portfolio.json"
do
  local f = io.open(DIR .. "/bp_samples/operations_page_1.json", "rb")
  local g = io.open(DIR .. "/bp_samples/portfolio.json", "rb")
  if f and g then portfolioFile = DIR .. "/bp_samples/portfolio.json" end
  if f then f:close() end
  if g then g:close() end
end
local RAW = {
  portfolio  = readFile(portfolioFile),
  currencies = readFile(DIR .. "/bp_currencies.json"),
  operations = readFile(DIR .. "/bp_operations.json"),
  tickerErr  = readFile(DIR .. "/bp_ticker.json"),
}
local tickerFiles = {}
local p = io.popen('ls "' .. DIR .. '/bp_samples" 2>/dev/null')
if p then
  for f in p:lines() do
    local id = string.match(f, "^ticker_(.-)%.json$")
    if id then tickerFiles[id] = readFile(DIR .. "/bp_samples/" .. f) end
  end
  p:close()
end

-- assets: serve from assets_all.ndjson, decoding only lines that mention a requested id
local function assetsFor(ids)
  local want = {}
  for id in string.gmatch(ids, "[^,]+") do want[id] = true end
  local out = {}
  for line in io.lines(DIR .. "/bp_samples/assets_all.ndjson") do
    local id = string.match(line, '"id"%s*:%s*"([^"]+)"')
    if id and want[id] then table.insert(out, jsonDecode(line)) end
  end
  return { data = out, has_next_page = false }
end

local REQUESTS = {}
local STATUS = {}
local function fakeApi(url)
  table.insert(REQUESTS, url)
  local path, query = url:match("^https://api%.public%.bitpanda%.com/v1/([^?]*)%??(.*)$")
  if path == "portfolio" then return RAW.portfolio
  elseif path == "currencies" then return RAW.currencies
  elseif path == "operations" then
    -- full history from fetch-samples-v2.sh (operations_page_N.json) if present, served in
    -- request order; otherwise the single captured page followed by an empty last page.
    OPS_REQ = (OPS_REQ or 0) + 1
    local f = io.open(DIR .. "/bp_samples/operations_page_" .. OPS_REQ .. ".json", "rb")
    if f then local c = f:read("a"); f:close(); return c end
    if OPS_REQ > 1 then return '{"data":[],"has_next_page":false}' end
    return RAW.operations
  elseif path == "assets" then
    local ids = (query:match("id=([^&]*)") or ""):gsub("%%2[Cc]", ",")
    return assetsFor(ids)   -- table: JSON stub passes it through
  elseif path:match("^tickers/") then
    local id = path:match("^tickers/(.+)$")
    return tickerFiles[id] or RAW.tickerErr
  end
  return '{"error":{"code":"not_found"}}'
end

-- ---------------------------------------------------------------- MoneyMoney stubs
WebBanking = function(t) end
LoginFailed = "LoginFailed"
ProtocolWebBanking = "WebBanking"
AccountTypeSavings = "Savings"
AccountTypeGiro = "Giro"
AccountTypePortfolio = "Portfolio"
LocalStorage = {}
MM = {
  urlencode = function(s) return (tostring(s):gsub("[^%w%-_%.~]", function(c) return string.format("%%%02X", c:byte()) end)) end,
  printStatus = function(...) table.insert(STATUS, table.concat({...}, " ")) end,
  sleep = function() end,
}
JSON = function(content)
  return { dictionary = function()
    if type(content) == "table" then return content end
    return jsonDecode(content)
  end }
end
Connection = function()
  return { request = function(self, method, url, body, ctype, headers)
    assert(headers["x-api-key"] ~= nil, "no api key header")
    return fakeApi(url)
  end }
end

dofile(EXT)

-- ---------------------------------------------------------------- replay
print("=== replay of " .. EXT .. " against " .. DIR)
local s = InitializeSession("WebBanking", "Bitpanda (Public API)", "replay-key-0123456789", nil, "")
print("InitializeSession -> " .. tostring(s))
if s ~= nil then os.exit(1) end

local accounts = ListAccounts({})
print("ListAccounts: " .. #accounts .. " accounts")
for _, a in ipairs(accounts) do
  print(string.format("  %-24s %-8s %-5s portfolio=%s", a.name, a.subAccount, a.currency, tostring(a.portfolio)))
end

local since = os.time() - 400 * 86400
local ok = true
local function check(cond, msg)
  print((cond and "  PASS  " or "  FAIL  ") .. msg)
  if not cond then ok = false end
end

-- depots
local pf = loadJson(portfolioFile).data
print("portfolio snapshot: " .. portfolioFile)
local expectedPositions = 0
for _, pos in ipairs(pf) do if pos.asset_id and tonumber(pos.balance.value) > 0 then expectedPositions = expectedPositions + 1 end end
local totalPositions = 0
for _, a in ipairs(accounts) do
  if a.portfolio then
    local r = RefreshAccount(a, since)
    if type(r) ~= "table" then
      print("  " .. a.name .. " -> " .. tostring(r)); ok = false
    else
      totalPositions = totalPositions + #r.securities
      if #r.securities > 0 then
        print("  " .. a.name .. ": " .. #r.securities .. " position(s)")
        for _, sec in ipairs(r.securities) do
          local priceOk = sec.price ~= nil and sec.quantity > 0 and math.abs(sec.price * sec.quantity - sec.amount) < 0.01
          print(string.format("     %-55s isin=%s wkn/symbol=%s price=value/qty:%s purchasePrice:%s foreignCur:%s",
            sec.name, tostring(sec.isin), tostring(sec.securityNumber), tostring(priceOk),
            sec.purchasePrice ~= nil and "yes" or "no", tostring(sec.currencyOfPrice)))
          if not priceOk then ok = false end
        end
      end
    end
  end
end
check(totalPositions == expectedPositions, "all " .. expectedPositions .. " portfolio positions with balance > 0 are routed into exactly one depot (" .. totalPositions .. ")")

-- fiat (reconciliation source: full history if captured, else the single page)
local currencyIdOf = {}
for _, c in ipairs(loadJson(DIR .. "/bp_currencies.json").data) do currencyIdOf[c.symbol] = c.id end
local ops = {}
local pageNo = 1
while true do
  local f = io.open(DIR .. "/bp_samples/operations_page_" .. pageNo .. ".json", "rb")
  if not f then break end
  local c = f:read("a"); f:close()
  for _, op in ipairs(jsonDecode(c).data) do table.insert(ops, op) end
  pageNo = pageNo + 1
end
if #ops == 0 then ops = loadJson(DIR .. "/bp_operations.json").data end
print("operations available for reconciliation: " .. #ops .. " (" .. (pageNo - 1) .. " captured page(s))")
for _, a in ipairs(accounts) do
  if not a.portfolio then
    local r = RefreshAccount(a, since)
    if type(r) ~= "table" then
      print("  " .. a.name .. " -> " .. tostring(r)); ok = false
    else
      print("  " .. a.name .. ": " .. #r.transactions .. " transactions")
      local byText, unknown, pending, minD, maxD, sum = {}, 0, 0, nil, nil, 0
      for _, t in ipairs(r.transactions) do
        byText[t.bookingText] = (byText[t.bookingText] or 0) + 1
        if string.find(t.name, "Unknown", 1, true) or string.find(t.name, "Unbekannt", 1, true) then unknown = unknown + 1 end
        if not t.booked then pending = pending + 1 end
        if minD == nil or t.bookingDate < minD then minD = t.bookingDate end
        if maxD == nil or t.bookingDate > maxD then maxD = t.bookingDate end
        sum = sum + t.amount
      end
      local parts = {}
      for k, v in pairs(byText) do table.insert(parts, k .. "=" .. v) end
      table.sort(parts)
      print("     by bookingText: " .. table.concat(parts, ", "))
      print("     date range: " .. os.date("!%Y-%m-%d", minD or 0) .. " .. " .. os.date("!%Y-%m-%d", maxD or 0))
      check(unknown == 0, "no transaction with an unresolved asset name")
      local keys, clashes = {}, 0
      for _, t in ipairs(r.transactions) do
        local k = os.date("!%Y-%m-%d", t.bookingDate) .. "|" .. t.name .. "|" .. string.format("%.8f", t.amount) .. "|" .. t.purpose
        if keys[k] then clashes = clashes + 1 end
        keys[k] = true
      end
      check(clashes == 0, "every transaction is distinguishable by day/name/amount/purpose (" .. clashes .. " clashes)")
      check(pending == 0, "all transactions have a credit timestamp (booked=true)")

      -- Reconciliation against asset_balance_after of the main wallet (the wallet that
      -- carries deposits). Reserve/transfer legs cancel out, so the sum of what the
      -- extension books must equal the wallet movement over the captured window.
      local mainWallet
      for _, op in ipairs(ops) do
        if op.operation_type == "deposit" then mainWallet = op.transactions[1].wallet_id; break end
      end
      local legs = {}
      for _, op in ipairs(ops) do
        for _, tx in ipairs(op.transactions) do
          if tx.wallet_id == mainWallet and tx.currency_id == currencyIdOf[a.currency] and tonumber(tx.asset_balance_after.value) >= 0 then
            local amt = tonumber(tx.asset_amount.value)
            if tx.flow == "OUTGOING" then amt = -amt end
            table.insert(legs, {t = tx.credited_at, o = tonumber(tx.order_id) or 0, amt = amt, after = tonumber(tx.asset_balance_after.value)})
          end
        end
      end
      table.sort(legs, function(x, y) if x.t == y.t then return x.o < y.o end return x.t < y.t end)
      check(#legs > 0, "main wallet legs found for reconciliation (" .. #legs .. ")")
      if #legs > 0 then
        local delta = legs[#legs].after - (legs[1].after - legs[1].amt)
        check(math.abs(sum - delta) < 0.005, string.format("sum of booked transactions equals wallet movement over the window (%d legs, diff %.4f)", #legs, sum - delta))
        check(math.abs(legs[#legs].after - r.balance) < 0.005, "reported balance equals latest asset_balance_after of the main wallet")
        local breaks = 0
        for i = 2, #legs do if math.abs(legs[i - 1].after + legs[i].amt - legs[i].after) > 0.005 then breaks = breaks + 1 end end
        check(breaks == 0, "asset_balance_after chain of the main wallet is consistent (" .. breaks .. " breaks)")
      end
    end
  end
end

print("requests: " .. #REQUESTS)
for _, u in ipairs(REQUESTS) do print("  " .. (u:gsub("id=[^&]*", "id=<ids>"))) end
print("status messages:")
for _, m in ipairs(STATUS) do print("  " .. m) end
print(ok and "=== REPLAY OK" or "=== REPLAY FAILED")
