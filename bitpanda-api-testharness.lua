-- Test-Harness für die Bitpanda-Extension: stubbt die MoneyMoney-Laufzeit (Connection, JSON,
-- MM, LocalStorage, Konstanten) und füttert die Extension mit gescripteten API-Antworten.
--
-- Aufruf im selben Verzeichnis wie die Extension (Lua 5.3, z. B. texlua aus TeX Live):
--   TZ=Europe/Berlin texlua bitpanda-api-testharness.lua [bitpanda-api.lua]
--
-- Jedes Szenario meldet, was die Extension an MoneyMoney zurückgeben würde. Erwartung für
-- eine robuste Version: T3–T11 liefern einen Fehlertext (oder LoginFailed), nie falsche Daten.

local EXT = arg and arg[1] or "bitpanda-api.lua"
local SCENARIO = {}
local REQUESTS = {}
local STATUS = {}

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
-- JSON(content):dictionary() – content is already a Lua table here
JSON = function(content) return { dictionary = function() return content end } end

local IDS = { eur = "eur-uuid", usd = "usd-uuid", chf = "chf-uuid",
              btc = "btc-uuid", eth = "eth-uuid", aapl = "aapl-uuid", bci = "bci-uuid" }

-- Optionally rename every key of a response to camelCase (as in the official docs)
local function camel(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do
    local nk = k
    if type(k) == "string" then nk = k:gsub("_(%l)", function(c) return c:upper() end) end
    out[nk] = camel(v)
  end
  return out
end

local function fakeApi(url)
  table.insert(REQUESTS, url)
  local path, query = url:match("^https://api%.public%.bitpanda%.com/v1/([^?]*)%??(.*)$")
  if SCENARIO.transportError then error("timeout") end
  if SCENARIO.flakyOnce and not SCENARIO._flaked then SCENARIO._flaked = true; return "" end
  local resp
  if path == "portfolio" then
    if SCENARIO.portfolioEmpty then return { data = {} } end
    local valCur = (SCENARIO.valuedInChf and not query:find("equivalent_currency_id")) and IDS.chf or IDS.eur
    local d = {
      { currency_id = IDS.eur, balance = { value = "1234.56", currency_id = IDS.eur } },
      { asset_id = IDS.btc, balance = { value = "0.5" }, currency_balance = { value = "30000", currency_id = valCur }, average_buy_price = { value = "40000", currency_id = valCur } },
      { asset_id = IDS.eth, balance = { value = "2" }, currency_balance = { value = "0", currency_id = valCur } },
      { asset_id = IDS.aapl, balance = { value = "3" }, currency_balance = { value = "600", currency_id = valCur } },
    }
    if SCENARIO.withUsd then table.insert(d, { currency_id = IDS.usd, balance = { value = "10", currency_id = IDS.usd } }) end
    if SCENARIO.unvalued then table.insert(d, { asset_id = "gold-uuid", balance = { value = "1.5" } }) end
    resp = { data = d }
  elseif path == "currencies" then
    if SCENARIO.currenciesEmpty then return { data = {} } end
    resp = { data = { { id = IDS.eur, symbol = "EUR", name = "Euro" }, { id = IDS.usd, symbol = "USD", name = "US-Dollar" }, { id = IDS.chf, symbol = "CHF", name = "Franken" } } }
  elseif path == "assets" then
    if SCENARIO.assetsFail then return { errors = { { status = 429, code = "rate_limited", title = "Too many requests" } } } end
    local out = {}
    local want = (query:match("id=([^&]*)") or ""):gsub("%%2[Cc]", ",")
    for id in want:gmatch("[^,]+") do
      if id == IDS.btc then table.insert(out, { id = id, name = "Bitcoin", symbol = "BTC", type = "cryptocoin", group = "coin" }) end
      if id == IDS.eth then table.insert(out, { id = id, name = "Ethereum", symbol = "ETH", type = "cryptocoin", group = "coin" }) end
      if id == IDS.aapl then table.insert(out, { id = id, name = "Apple", symbol = "AAPL", isin = "US0378331005", type = "equity_security", group = "equity_stock" }) end
      if id == IDS.bci then table.insert(out, { id = id, name = "Bitpanda Crypto Index 10", symbol = "BCI10", type = "index", group = "index" }) end
      if id == "gold-uuid" then table.insert(out, { id = id, name = "Gold", symbol = "XAU", type = "commodity", group = "metal" }) end
    end
    resp = { data = out, has_next_page = false }
  elseif path:match("^tickers/") then
    if path:find("gold") then return { error = { code = "not_found" } } end
    if SCENARIO.tickerGarbage then resp = { data = { price = "n/a", currency_id = IDS.eur } }
    else resp = { data = { price = "2500", currency_id = IDS.eur } } end
  elseif path == "operations" then
    local cursor = query:match("cursor=([^&]*)")
    local function op(id, opType, txs) return { operation_id = id, operation_type = opType, transactions = txs } end
    local function fiat(txType, flow, amount, credited, extra)
      local t = { transaction_type = txType, flow = flow, currency_id = IDS.eur, transaction_id = "tx-" .. tostring(amount) .. "-" .. tostring(credited),
                  asset_amount = (amount ~= "NOAMT") and { value = amount, currency_id = IDS.eur } or nil, credited_at = credited }
      for k, v in pairs(extra or {}) do t[k] = v end
      return t
    end
    if cursor == nil then
      resp = { data = {
        op("op1", "deposit", { fiat("deposit", "INCOMING", "100.00", "2026-07-01T12:00:00.000Z", { transaction_id = "tx-op1" }) }),
        op("op2", "withdrawal", { fiat("withdrawal", (not SCENARIO.flowNil) and "OUTGOING" or nil, "50.00", "2026-01-15T12:00:00.000Z") }),
        op("op3", "buy", {
          fiat("buy", "OUTGOING", "200.00", "2026-03-29T01:30:00.000Z", { trade = { rate = "40000" } }),
          { transaction_type = "buy", flow = "INCOMING", asset_id = IDS.btc,
            asset_amount = (not SCENARIO.assetLegNoAmount) and { value = "0.005", asset_id = IDS.btc } or nil,
            trade = { rate = "40000" } },
        }),
        op("op4", "deposit", { fiat("deposit", "INCOMING", "77.00", (not SCENARIO.pendingWithoutDate) and "2026-10-25T01:30:00.000Z" or nil) }),
        op("op7", "deposit", { fiat("deposit", "INCOMING", "100.00", "2026-07-01T15:30:00.000Z", { transaction_id = "tx-op7" }) }),
        op("op8", "deposit", { fiat("deposit", "INCOMING", SCENARIO.fiatLegNoAmount and "NOAMT" or "5.00", "2026-06-30T09:00:00.000Z", { transaction_id = "tx-op8" }) }),
        op("op6", "buy", {
          fiat("buy", "OUTGOING", "25.00", "2026-08-01T08:00:00.000Z", { trade = { rate = "1" } }),
          { transaction_type = "buy", flow = "INCOMING", asset_id = IDS.btc, index_asset_id = IDS.bci,
            asset_amount = { value = "0.0001", asset_id = IDS.btc }, trade = { rate = "1" } },
        }),
      }, has_next_page = true, next_cursor = "c2==" }
      if SCENARIO.noPaginationFields then resp.has_next_page = nil; resp.next_cursor = nil
        -- pad to a full page so the truncation is undetectable by count
        while #resp.data < 100 do table.insert(resp.data, op("pad" .. #resp.data, "deposit", { fiat("deposit", "INCOMING", "1.00", "2026-06-01T00:00:00.000Z") })) end
      end
    else
      if SCENARIO.cursorRestarts then
        -- emulate the real API: an unknown cursor yields page 1 again
        SCENARIO.cursorRestarts = false
        local again = fakeApi(url:gsub("cursor=[^&]*&?", ""))
        table.insert(REQUESTS, "(restart)")
        return again
      end
      resp = { data = { op("op5", "deposit", { fiat("deposit", "INCOMING", "999.00", "2026-07-01T12:00:00.000Z") }) },
               has_next_page = false, next_cursor = SCENARIO.staleCursorOnLastPage and "MjAyNi0wMS0yN1Qw" or nil }
    end
  else
    resp = { errors = { { status = 404, code = "not_found" } } }
  end
  if SCENARIO.camelCase then resp = camel(resp) end
  return resp
end

Connection = function()
  return { request = function(self, method, url, body, ctype, headers)
    assert(headers["x-api-key"] ~= nil, "no api key header")
    return fakeApi(url)
  end }
end

dofile(EXT)

-- ---------------------------------------------------------------- helpers
local function run(name, knobs, body)
  SCENARIO = knobs or {}
  REQUESTS = {}
  STATUS = {}
  local ok, err = pcall(body)
  if ok then print("[" .. name .. "] " .. (err or "ok")) else print("[" .. name .. "] LUA ERROR: " .. tostring(err)) end
end

local function session(user, pass)
  return InitializeSession("WebBanking", "Bitpanda (Public API)", user or "0123456789abcdef0123", nil, pass or "")
end

local function findAccount(accts, key)
  for _, a in ipairs(accts) do if a.subAccount == key then return a end end
end

local function describe(r)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  if r.securities then
    local n = {}
    for _, s in ipairs(r.securities) do table.insert(n, string.format("%s q=%s amt=%s price=%s", s.name, tostring(s.quantity), tostring(s.amount), tostring(s.price))) end
    return "securities: " .. table.concat(n, " | ")
  end
  local lines = {}
  for _, t in ipairs(r.transactions or {}) do
    table.insert(lines, string.format("  %-28s %9.2f  %s  booked=%s", t.name, t.amount, os.date("!%Y-%m-%dT%H:%M:%SZ", t.bookingDate), tostring(t.booked)))
  end
  return "balance=" .. tostring(r.balance) .. " tx=" .. #(r.transactions or {}) .. "\n" .. table.concat(lines, "\n")
end

print("=== extension under test: " .. EXT)

-- ---------------------------------------------------------------- tests
run("T1 happy path (EUR wallet)", {}, function()
  local s = session(); assert(s == nil, "session: " .. tostring(s))
  local eur = findAccount(ListAccounts({}), "fiat")
  return describe(RefreshAccount(eur, 1735689600))  -- since = 2026-01-01
end)

run("T2 timestamps vs expected UTC epochs (TZ=" .. tostring(os.getenv("TZ")) .. ")", {}, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  local expected = { ["Bitpanda Einzahlung"] = { [1782907200]=1, [1792891800]=1, [1782919800]=1, [1782810000]=1 }, ["Bitpanda Auszahlung"] = { [1768478400]=1 },
                     ["Kauf: Bitcoin"] = { [1774747800]=1 }, ["Kauf: Bitpanda Crypto Index 10"] = { [1785571200]=1 } }
  local bad = {}
  for _, t in ipairs(r.transactions) do
    if not (expected[t.name] and expected[t.name][t.bookingDate]) then table.insert(bad, t.name .. "=" .. t.bookingDate) end
  end
  return #bad == 0 and "all timestamps correct" or ("MISMATCH: " .. table.concat(bad, ", "))
end)

run("T3a pagination: whole API answers in camelCase (as documented)", { camelCase = true }, function()
  local s = session(); if s ~= nil then return "-> " .. tostring(s) end
  return describe(RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)) .. "\n  (expected: all tx incl. op5 from page 2, or an explicit error)"
end)

run("T3b pagination: full page without pagination fields", { noPaginationFields = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) == "table" then return "tx=" .. #r.transactions .. " delivered although history may be truncated" end
  return "-> " .. tostring(r)
end)

run("T4 flow value missing on withdrawal", { flowNil = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  for _, t in ipairs(r.transactions) do if t.name == "Bitpanda Auszahlung" then return "withdrawal booked as " .. t.amount end end
end)

run("T5 asset leg without asset_amount", { assetLegNoAmount = true }, function()
  session()
  return describe(RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0))
end)

dofile(EXT)  -- fresh module state (empty asset cache)
run("T6 /assets fails (429) during InitializeSession", { assetsFail = true }, function()
  local s = session()
  if s ~= nil then return "-> " .. tostring(s) end
  local accts = ListAccounts({})
  return "session ok; crypto: " .. describe(RefreshAccount(findAccount(accts, "crypto"), 0)) .. "\n  other: " .. describe(RefreshAccount(findAccount(accts, "other"), 0))
end)

run("T6b next session with working /assets", {}, function()
  local s = session()
  local accts = ListAccounts({})
  return "session=" .. tostring(s) .. "; crypto: " .. describe(RefreshAccount(findAccount(accts, "crypto"), 0))
end)

run("T7 ticker returns non-numeric price", { tickerGarbage = true }, function()
  session()
  return describe(RefreshAccount(findAccount(ListAccounts({}), "crypto"), 0))
end)

run("T8 empty /currencies (portfolio has EUR + USD)", { currenciesEmpty = true, withUsd = true }, function()
  local s = session()
  if s ~= nil then return "-> " .. tostring(s) end
  local out = {}
  for _, a in ipairs(ListAccounts({})) do if a.subAccount == "fiat" then table.insert(out, a.name .. "/" .. a.currency) end end
  return "session ok; fiat accounts: " .. table.concat(out, ", ")
end)

run("T9 operation without credited_at", { pendingWithoutDate = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  for _, t in ipairs(r.transactions) do if t.amount == 77 then return string.format("undated tx: bookingDate=%d (now=%d) booked=%s", t.bookingDate, os.time(), tostring(t.booked)) end end
  return "undated tx not delivered"
end)

run("T10 portfolio empty after non-empty (API glitch), three sessions", { portfolioEmpty = true }, function()
  local out = {}
  for i = 1, 3 do
    local s = session()
    if s ~= nil then table.insert(out, i .. ": -> " .. tostring(s):sub(1, 60) .. "…")
    else
      local accts = ListAccounts({})
      table.insert(out, i .. ": accepted; crypto " .. describe(RefreshAccount(findAccount(accts, "crypto"), 0)) .. "; EUR balance=" .. tostring(RefreshAccount(findAccount(accts, "fiat"), 0).balance))
    end
  end
  return table.concat(out, "\n  ")
end)

run("T11 transport error on every request", { transportError = true }, function()
  return "session -> " .. tostring(session()) .. " (" .. #REQUESTS .. " attempts)"
end)

run("T12 one flaky (empty) response, then fine", { flakyOnce = true }, function()
  local s = session()
  return "session=" .. tostring(s) .. ", requests=" .. #REQUESTS .. ", status: " .. table.concat(STATUS, " / ")
end)

run("T13 key in password field, e-mail in user name: no rejected request in either session", {}, function()
  LocalStorage = {}
  local key = "0123456789abcdef0123"
  local realKey = { [key] = true }
  Connection = function() return { request = function(self, m, url, b, c, headers)
    if not realKey[headers["x-api-key"]] then table.insert(REQUESTS, "401 " .. url); return { errors = { { status = 401, code = "unauthorized", title = "Unauthorized" } } } end
    return fakeApi(url)
  end } end
  dofile(EXT)
  local s1 = session("michael@example.org", key); local n1 = #REQUESTS
  REQUESTS = {}
  local s2 = session("michael@example.org", key); local n2 = #REQUESTS
  local first401 = 0
  for _, r in ipairs(REQUESTS) do if r:find("^401") then first401 = first401 + 1 end end
  return string.format("session1=%s (%d requests), session2=%s (%d requests, %d rejected) apiKeyField=%s", tostring(s1), n1, tostring(s2), n2, first401, tostring(LocalStorage.apiKeyField))
end)

run("T14 wrong key everywhere", {}, function()
  Connection = function() return { request = function(self, m, url, b, c, headers)
    return { errors = { { status = 401, code = "unauthorized", title = "Unauthorized" } } }
  end } end
  dofile(EXT)
  return "session -> " .. tostring(session("wrongkeywrongkeywrongkey", "alsowrongalsowrongalso"))
end)

run("T15 401 in non-JSON:API shape", {}, function()
  Connection = function() return { request = function(self, m, url, b, c, headers)
    return { message = "Unauthorized" }
  end } end
  dofile(EXT)
  return "session -> " .. tostring(session())
end)

run("T16 rate limit message mentioning 'api key' must not become LoginFailed", {}, function()
  Connection = function() return { request = function(self, m, url, b, c, headers)
    return { errors = { { status = 429, code = "rate_limited", title = "Rate limit exceeded for this API key" } } }
  end } end
  dofile(EXT)
  return "session -> " .. tostring(session())
end)

-- restore the normal fake connection for the remaining tests
Connection = function() return { request = function(self, m, url, b, c, headers) return fakeApi(url) end } end
dofile(EXT)

run("T17 portfolio valued in CHF (account base currency ≠ EUR)", { valuedInChf = true }, function()
  local s = session()
  if s ~= nil then return "-> " .. tostring(s) end
  local urls = {}
  for _, u in ipairs(REQUESTS) do if u:find("portfolio") then table.insert(urls, u) end end
  return describe(RefreshAccount(findAccount(ListAccounts({}), "crypto"), 0)) .. "\n  portfolio requests: " .. table.concat(urls, " ; ")
end)

run("T18 request count for one full refresh (fresh state)", {}, function()
  session()
  for _, a in ipairs(ListAccounts({})) do RefreshAccount(a, 1735689600) end
  return #REQUESTS .. " requests:\n  " .. table.concat(REQUESTS, "\n  ")
end)

run("T19 malformed operation (transactions is a number): MoneyMoney shows the Lua error itself", {}, function()
  Connection = function() return { request = function(self, m, url, b, c, headers)
    local r = fakeApi(url)
    if url:find("operations") then r.data[1].transactions = 5 end
    return r
  end } end
  dofile(EXT)
  session()
  return "refresh -> " .. tostring(RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0))
end)

Connection = function() return { request = function(self, m, url, b, c, headers) return fakeApi(url) end } end
dofile(EXT)
run("T20 last page says has_next_page=false but still carries a next_cursor (real API behaviour)", { staleCursorOnLastPage = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  local n = 0
  for _, u in ipairs(REQUESTS) do if u:find("operations") then n = n + 1 end end
  return "tx=" .. #r.transactions .. ", operations requests=" .. n .. " (expected 2, no loop)"
end)

run("T21 cursor rejected: API restarts at page 1 (real API behaviour)", { cursorRestarts = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  local names = {}
  for _, t in ipairs(r.transactions) do names[#names + 1] = t.name .. "/" .. t.amount end
  table.sort(names)
  local dup = 0
  for i = 2, #names do if names[i] == names[i - 1] then dup = dup + 1 end end
  return "tx=" .. #r.transactions .. ", duplicates=" .. dup
end)

Connection = function() return { request = function(self, m, url, b, c, headers) return fakeApi(url) end } end
dofile(EXT)
run("T22 two deposits, same day, same amount, same name: purposes must differ", {}, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  local seen, same = {}, 0
  for _, t in ipairs(r.transactions) do
    local k = os.date("!%Y-%m-%d", t.bookingDate) .. "|" .. t.name .. "|" .. t.amount .. "|" .. t.purpose
    if seen[k] then same = same + 1 end
    seen[k] = true
  end
  return "tx=" .. #r.transactions .. ", indistinguishable pairs=" .. same .. " (expected 0)"
end)

run("T23 fiat leg without asset_amount", { fiatLegNoAmount = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  for _, t in ipairs(r.transactions) do if t.amount == 0 then return "booked a 0.00 transaction (wrong)" end end
  return "no zero transaction, tx=" .. #r.transactions
end)

run("T24 403 missing scope must not become LoginFailed", {}, function()
  Connection = function() return { request = function(self, m, url, b, c, headers)
    return { errors = { { status = 403, code = "forbidden", title = "API key lacks scope: Balances" } } }
  end } end
  dofile(EXT)
  return "session -> " .. tostring(session())
end)

Connection = function() return { request = function(self, m, url, b, c, headers) return fakeApi(url) end } end
dofile(EXT)
run("T25 transactions sorted newest first", {}, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  for i = 2, #r.transactions do
    if r.transactions[i].bookingDate > r.transactions[i - 1].bookingDate then return "NOT sorted at index " .. i end
  end
  return "sorted, first=" .. os.date("!%Y-%m-%d", r.transactions[1].bookingDate) .. " last=" .. os.date("!%Y-%m-%d", r.transactions[#r.transactions].bookingDate)
end)

run("T26 position without valuation and ticker 404: amount nil, not 0", { unvalued = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "metal"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  for _, sec in ipairs(r.securities) do
    if sec.name == "Gold" then return string.format("Gold: quantity=%s amount=%s price=%s securityNumber=%s", tostring(sec.quantity), tostring(sec.amount), tostring(sec.price), tostring(sec.securityNumber)) end
  end
  return "Gold not found in Metalle depot"
end)

run("T27 account created by v2.01/v2.02 (accountNumber = currency uuid) still refreshes", {}, function()
  session()
  local legacy = { name = "Bitpanda EUR", accountNumber = "eur-uuid", subAccount = "fiat", currency = "EUR", portfolio = false }
  local r = RefreshAccount(legacy, 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  return "balance=" .. tostring(r.balance) .. " tx=" .. #r.transactions
end)

run("T28 ListAccounts shape", {}, function()
  session()
  local out = {}
  for _, a in ipairs(ListAccounts({})) do table.insert(out, a.accountNumber .. "/" .. tostring(a.type)) end
  return table.concat(out, ", ")
end)

run("T29 key in user name, dummy password: one rejected request in session 1, none in session 2", {}, function()
  LocalStorage = {}
  local key = "0123456789abcdef0123"
  Connection = function() return { request = function(self, m, url, b, c, headers)
    if headers["x-api-key"] ~= key then table.insert(REQUESTS, "401 " .. url); return { errors = { { status = 401, code = "unauthorized", title = "Credentials / Access token wrong" } } } end
    return fakeApi(url)
  end } end
  dofile(EXT)
  local s1 = InitializeSession("WebBanking", "Bitpanda (Public API)", key, nil, "dummy"); local n1 = 0
  for _, r in ipairs(REQUESTS) do if r:find("^401") then n1 = n1 + 1 end end
  REQUESTS = {}
  local s2 = InitializeSession("WebBanking", "Bitpanda (Public API)", key, nil, "dummy"); local n2 = 0
  for _, r in ipairs(REQUESTS) do if r:find("^401") then n2 = n2 + 1 end end
  return string.format("session1=%s (%d rejected), session2=%s (%d rejected), apiKeyField=%s", tostring(s1), n1, tostring(s2), n2, tostring(LocalStorage.apiKeyField))
end)
