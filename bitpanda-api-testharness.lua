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

local function indexOps()
  return {
    { operation_id = "0c3572f1-op", operation_type = "index_buy", transactions = {
      { transaction_id = "0c3572f1", currency_id = IDS.eur, asset_amount = { value = "45.99", currency_id = IDS.eur }, flow = "OUTGOING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "eda60f33", rate = "17.58083576" } },
      { transaction_id = "be0bd0ab", currency_id = IDS.eur, asset_amount = { value = "50.13", currency_id = IDS.eur }, flow = "OUTGOING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "c20d0555", rate = "409.74180000" } },
      { transaction_id = "8a3ce66c", currency_id = IDS.eur, asset_amount = { value = "53.03", currency_id = IDS.eur }, flow = "OUTGOING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "4057474c", rate = "122.19921103" } },
      { transaction_id = "b196c0af", currency_id = IDS.eur, asset_amount = { value = "247.34", currency_id = IDS.eur }, flow = "OUTGOING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "b20eb71a", rate = "1102.93270425" } },
      { transaction_id = "e4bfe618", currency_id = IDS.eur, asset_amount = { value = "167.45", currency_id = IDS.eur }, flow = "OUTGOING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "7d5cf1c0", rate = "28962.22500000" } },
      { transaction_id = "34669f1d", asset_id = "b86c81e5", asset_amount = { value = "2.61591659", asset_id = "b86c81e5" }, flow = "INCOMING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "1", asset_id = "b86c81e5" }, index_asset_id = "bci5-uuid", trade = { trade_id = "eda60f33", rate = "17.58083576" } },
      { transaction_id = "4b74e712", asset_id = "b86c1b2a", asset_amount = { value = "0.12234534", asset_id = "b86c1b2a" }, flow = "INCOMING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "1", asset_id = "b86c1b2a" }, index_asset_id = "bci5-uuid", trade = { trade_id = "c20d0555", rate = "409.74180000" } },
      { transaction_id = "cba4e48f", asset_id = "b86c0bbf", asset_amount = { value = "0.43396352", asset_id = "b86c0bbf" }, flow = "INCOMING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "1", asset_id = "b86c0bbf" }, index_asset_id = "bci5-uuid", trade = { trade_id = "4057474c", rate = "122.19921103" } },
      { transaction_id = "17d3b4ad", asset_id = "b86c113a", asset_amount = { value = "0.22425665", asset_id = "b86c113a" }, flow = "INCOMING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "1", asset_id = "b86c113a" }, index_asset_id = "bci5-uuid", trade = { trade_id = "b20eb71a", rate = "1102.93270425" } },
      { transaction_id = "84cf657e", asset_id = "b86c034b", asset_amount = { value = "0.00578166", asset_id = "b86c034b" }, flow = "INCOMING", credited_at = "2021-01-20T22:04:51Z", asset_balance_after = { value = "1", asset_id = "b86c034b" }, index_asset_id = "bci5-uuid", trade = { trade_id = "7d5cf1c0", rate = "28962.22500000" } }
    } },
    { operation_id = "89792c58-op", operation_type = "index_sell", transactions = {
      { transaction_id = "89792c58", asset_id = "b86c1b2a", asset_amount = { value = "0.01491773", asset_id = "b86c1b2a" }, flow = "OUTGOING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "1", asset_id = "b86c1b2a" }, index_asset_id = "bci5-uuid", trade = { trade_id = "b7f67134", rate = "351.25965000" } },
      { transaction_id = "75976946", asset_id = "b86c0bbf", asset_amount = { value = "0.05300388", asset_id = "b86c0bbf" }, flow = "OUTGOING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "1", asset_id = "b86c0bbf" }, index_asset_id = "bci5-uuid", trade = { trade_id = "f68f187f", rate = "113.95391800" } },
      { transaction_id = "8cbb6b1f", asset_id = "b86c81e5", asset_amount = { value = "0.31878502", asset_id = "b86c81e5" }, flow = "OUTGOING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "1", asset_id = "b86c81e5" }, index_asset_id = "bci5-uuid", trade = { trade_id = "47c72abf", rate = "19.91938007" } },
      { transaction_id = "a9ec0006", asset_id = "b86c034b", asset_amount = { value = "0.00070562", asset_id = "b86c034b" }, flow = "OUTGOING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "1", asset_id = "b86c034b" }, index_asset_id = "bci5-uuid", trade = { trade_id = "ff02489c", rate = "26231.95575000" } },
      { transaction_id = "a0c26a21", asset_id = "b86c113a", asset_amount = { value = "0.02739092", asset_id = "b86c113a" }, flow = "OUTGOING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "1", asset_id = "b86c113a" }, index_asset_id = "bci5-uuid", trade = { trade_id = "60ee8a4c", rate = "1014.93460140" } },
      { transaction_id = "3754dbd6", currency_id = IDS.eur, asset_amount = { value = "5.24", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "b7f67134", rate = "351.25965000" } },
      { transaction_id = "251aefaa", currency_id = IDS.eur, asset_amount = { value = "6.04", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "f68f187f", rate = "113.95391800" } },
      { transaction_id = "fe1f6a8c", currency_id = IDS.eur, asset_amount = { value = "6.35", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "47c72abf", rate = "19.91938007" } },
      { transaction_id = "300786db", currency_id = IDS.eur, asset_amount = { value = "18.51", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "ff02489c", rate = "26231.95575000" } },
      { transaction_id = "4bdd489c", currency_id = IDS.eur, asset_amount = { value = "27.8", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-23T13:36:31Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", trade = { trade_id = "60ee8a4c", rate = "1014.93460140" } }
    } },
    { operation_id = "9e384a48-op", operation_type = "index_rebalancing", transactions = {
      { transaction_id = "9e384a48", asset_id = "b86c1b2a", asset_amount = { value = "0.10742761", asset_id = "b86c1b2a" }, flow = "OUTGOING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "1", asset_id = "b86c1b2a" }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "5a2ff8d4", rate = "325.48425000" } },
      { transaction_id = "3a148ce7", asset_id = "b86c0bbf", asset_amount = { value = "0.04288901", asset_id = "b86c0bbf" }, flow = "OUTGOING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "1", asset_id = "b86c0bbf" }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "10531b0b", rate = "104.69221786" } },
      { transaction_id = "01bd95cb", asset_id = "b86c113a", asset_amount = { value = "0.04734887", asset_id = "b86c113a" }, flow = "OUTGOING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "1", asset_id = "b86c113a" }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "46b30820", rate = "1070.22056468" } },
      { transaction_id = "6b353250", asset_id = "b86c81e5", asset_amount = { value = "0.24152084", asset_id = "b86c81e5" }, flow = "OUTGOING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "1", asset_id = "b86c81e5" }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "92bb8b50", rate = "18.39796946" } },
      { transaction_id = "fa2ef8c2", currency_id = IDS.eur, asset_amount = { value = "34.28", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "5a2ff8d4", rate = "325.48425000" } },
      { transaction_id = "fb24f380", currency_id = IDS.eur, asset_amount = { value = "4.4", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "10531b0b", rate = "104.69221786" } },
      { transaction_id = "b39cd7fd", currency_id = IDS.eur, asset_amount = { value = "49.68", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "46b30820", rate = "1070.22056468" } },
      { transaction_id = "4f0588ea", currency_id = IDS.eur, asset_amount = { value = "4.35", currency_id = IDS.eur }, flow = "INCOMING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", transaction_type = "sell", trade = { trade_id = "92bb8b50", rate = "18.39796946" } },
      { transaction_id = "0a75043e", currency_id = IDS.eur, asset_amount = { value = "61.93", currency_id = IDS.eur }, flow = "OUTGOING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", transaction_type = "buy", trade = { trade_id = "b88e13bb", rate = "13.19463109" } },
      { transaction_id = "ef5c781d", currency_id = IDS.eur, asset_amount = { value = "30.78", currency_id = IDS.eur }, flow = "OUTGOING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "100", currency_id = IDS.eur }, index_asset_id = "bci5-uuid", transaction_type = "buy", trade = { trade_id = "07fa4863", rate = "26860.98500000" } },
      { transaction_id = "4c775802", asset_id = "b86ccc0b", asset_amount = { value = "4.60024927", asset_id = "b86ccc0b" }, flow = "INCOMING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "1", asset_id = "b86ccc0b" }, index_asset_id = "bci5-uuid", transaction_type = "buy", trade = { trade_id = "b88e13bb", rate = "13.19463109" } },
      { transaction_id = "81551cb4", asset_id = "b86c034b", asset_amount = { value = "0.00112309", asset_id = "b86c034b" }, flow = "INCOMING", credited_at = "2021-01-31T17:55:40Z", asset_balance_after = { value = "1", asset_id = "b86c034b" }, index_asset_id = "bci5-uuid", transaction_type = "buy", trade = { trade_id = "07fa4863", rate = "26860.98500000" } }
    } }
  }
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
    if SCENARIO.withBci5 then table.insert(d, { asset_id = "bci5-uuid", balance = { value = "0.026354981" },
      invested_amount = { value = "609.66", currency_id = IDS.eur }, average_buy_price = { value = "23133.20683802", currency_id = IDS.eur },
      currency_balance = { value = "774.71", currency_id = IDS.eur } }) end
    if SCENARIO.withIndex then table.insert(d, { asset_id = IDS.bci, balance = { value = "0.026354981" },
      invested_amount = { value = "609.66", currency_id = IDS.eur }, average_buy_price = { value = "23133.20683802", currency_id = IDS.eur },
      currency_balance = { value = "774.71", currency_id = IDS.eur }, total_return = { value = "165.05", currency_id = IDS.eur } }) end
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
      if id == "bci5-uuid" then table.insert(out, { id = id, name = "Bitpanda Crypto Index 5", symbol = "BCI5", type = "index", group = "index" }) end
      for _, c in ipairs({ {"b86c81e5","DOGE"}, {"b86c1b2a","LINK"}, {"b86c0bbf","LTC"}, {"b86c113a","ETH"}, {"b86c034b","BTC"}, {"b86ccc0b","XRP"} }) do
        if id == c[1] then table.insert(out, { id = id, name = c[2] .. " (Bestandteil)", symbol = c[2], type = "cryptocoin", group = "coin" }) end
      end
    end
    resp = { data = out, has_next_page = false }
  elseif path:match("^tickers/") then
    if path:find("gold") then return { error = { code = "not_found" } } end
    if SCENARIO.tickerGarbage then resp = { data = { price = "n/a", currency_id = IDS.eur } }
    else resp = { data = { price = "2500", currency_id = IDS.eur } } end
  elseif path == "operations" then
    local cursor = query:match("cursor=([^&]*)")
    if SCENARIO.paddedCursor and cursor ~= nil then
      if cursor:find("=", 1, true) or cursor:find("%3D", 1, true) or cursor:find("%3d", 1, true) then
        cursor = nil                    -- real API: padded cursor is not understood -> page 1 again
        table.insert(REQUESTS, "(padded cursor rejected -> page 1)")
      elseif cursor == "MjAyNi0wNS0yNVQxNDozNTozOVo" then
        cursor = "c2=="                 -- unpadded form accepted -> page 2
      end
    end
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
      }, has_next_page = true, next_cursor = SCENARIO.paddedCursor and "MjAyNi0wNS0yNVQxNDozNTozOVo=" or "c2==" }
      if SCENARIO.noPaginationFields then resp.has_next_page = nil; resp.next_cursor = nil
        -- pad to a full page so the truncation is undetectable by count
        while #resp.data < 100 do table.insert(resp.data, op("pad" .. #resp.data, "deposit", { fiat("deposit", "INCOMING", "1.00", "2026-06-01T00:00:00.000Z") })) end
      end
    else
      if SCENARIO.stuckCursor then
        -- emulate >100 operations with the same credited_at: the API hands back the same cursor
        return { data = { op("op9", "deposit", { fiat("deposit", "INCOMING", "1.00", "2026-05-01T00:00:00.000Z") }) },
                 has_next_page = true, next_cursor = "c2==" }
      end
      if SCENARIO.cursorRestarts then
        -- emulate the real API: an unknown cursor yields page 1 again
        SCENARIO.cursorRestarts = false
        local again = fakeApi(url:gsub("cursor=[^&]*&?", ""))
        table.insert(REQUESTS, "(restart)")
        return again
      end
      local page2 = { op("op5", "deposit", { fiat("deposit", "INCOMING", "999.00", "2026-07-01T12:00:00.000Z") }) }
      if SCENARIO.withBci5 then for _, o in ipairs(indexOps()) do table.insert(page2, o) end end
      if SCENARIO.duplicateIds then
        -- legacy-style data: distinct operations sharing operation_id values of page 1
        table.insert(page2, op("op1", "deposit", { fiat("deposit", "INCOMING", "11.00", "2026-04-01T00:00:00.000Z", { transaction_id = "tx-dup-a" }) }))
        table.insert(page2, op("op2", "deposit", { fiat("deposit", "INCOMING", "12.00", "2026-04-01T00:00:00.000Z", { transaction_id = "tx-dup-b" }) }))
      end
      resp = { data = page2,
               has_next_page = false, next_cursor = SCENARIO.staleCursorOnLastPage and "MjAyNi0wMS0yN1Qw" or nil }
    end
  else
    resp = { errors = { { status = 404, code = "not_found" } } }
  end
  if path == "operations" and SCENARIO.honourFrom then
    local from = query:match("from=([^&]*)")
    if from then
      from = from:gsub("%%3A", ":"):gsub("%%3a", ":")
      local kept = {}
      for _, o in ipairs(resp.data) do
        local newest = ""
        for _, t in ipairs(o.transactions) do if (t.credited_at or "") > newest then newest = t.credited_at end end
        if newest >= from then table.insert(kept, o) end
      end
      resp.data = kept
    end
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

Connection = function() return { request = function(self, m, url, b, c, headers) return fakeApi(url) end } end
dofile(EXT)
run("T30 distinct operations sharing operation_id values (legacy data) must all be delivered", { duplicateIds = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  local found = 0
  for _, t in ipairs(r.transactions) do if t.amount == 11 or t.amount == 12 then found = found + 1 end end
  return "tx=" .. #r.transactions .. ", legacy duplicates-by-id delivered=" .. found .. " (expected 2)"
end)

run("T31 API stuck: page 2 returns its own cursor again", { stuckCursor = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  local n = 0
  for _, u in ipairs(REQUESTS) do if u:find("operations") then n = n + 1 end end
  return (type(r) == "table" and ("tx=" .. #r.transactions) or ("-> " .. tostring(r))) .. " | operations requests=" .. n .. " | status: " .. table.concat(STATUS, " / ")
end)

run("T32 index position (BCI5 sample): nominal presentation", { withIndex = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "index"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  for _, sec in ipairs(r.securities) do
    return string.format("%s: quantity=%s %s amount=%s price=%.2f%% purchasePrice=%s", sec.name, tostring(sec.quantity), tostring(sec.currencyOfQuantity), tostring(sec.amount), sec.price, tostring(sec.purchasePrice))
  end
  return "no index position"
end)

run("T33 API emits a padded cursor (timestamp without milliseconds) and rejects it when sent back padded", { paddedCursor = true }, function()
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  local sent = {}
  for _, u in ipairs(REQUESTS) do local c = u:match("cursor=([^&]*)"); if c then sent[#sent + 1] = c end end
  if type(r) ~= "table" then return "-> " .. tostring(r) .. " | cursors sent: " .. table.concat(sent, ", ") end
  return "tx=" .. #r.transactions .. " (expected 8 incl. page 2) | cursors sent: " .. table.concat(sent, ", ")
end)

Connection = function() return { request = function(self, m, url, b, c, headers) return fakeApi(url) end } end
dofile(EXT)
run("T34 first refresh loads the full history (no from), second refresh follows since", {}, function()
  LocalStorage = {}
  session()
  local eur = findAccount(ListAccounts({}), "fiat")
  local r1 = RefreshAccount(eur, 1735689600)
  local urls1 = {}
  for _, u in ipairs(REQUESTS) do if u:find("operations") then urls1[#urls1 + 1] = u:gsub(".*operations%??", "") end end
  REQUESTS = {}
  dofile(EXT)  -- new session, same LocalStorage
  session()
  local r2 = RefreshAccount(eur, 1735689600)
  local urls2 = {}
  for _, u in ipairs(REQUESTS) do if u:find("operations") then urls2[#urls2 + 1] = u:gsub(".*operations%??", "") end end
  return string.format("run1: tx=%s, operations queries: %s | run2: tx=%s, queries: %s | marker=%s",
    type(r1) == "table" and #r1.transactions or tostring(r1), table.concat(urls1, " ; "),
    type(r2) == "table" and #r2.transactions or tostring(r2), table.concat(urls2, " ; "), tostring(LocalStorage.fullHistoryDone_EUR))
end)

run("T35 first refresh fails (API error): marker must NOT be set", { assetsFail = false }, function()
  LocalStorage = {}
  local orig = Connection
  Connection = function() return { request = function(self, m, url, b, c, headers)
    if url:find("operations") then return { errors = { { status = 500, code = "internal", title = "boom" } } } end
    return fakeApi(url)
  end } end
  dofile(EXT)
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 1735689600)
  Connection = orig
  return "refresh -> " .. tostring(r):sub(1, 60) .. " | marker=" .. tostring(LocalStorage.fullHistoryDone_EUR)
end)

Connection = function() return { request = function(self, m, url, b, c, headers) return fakeApi(url) end } end
dofile(EXT)
run("T36 BCI5 with Stefan's real index operations: nominal = net paid (buy 563.94 - sell 63.94 = 500.00)", { withBci5 = true }, function()
  LocalStorage = {}
  session()
  local accts = ListAccounts({})
  local r = RefreshAccount(findAccount(accts, "index"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  local out = {}
  for _, sec in ipairs(r.securities) do
    out[#out + 1] = string.format("%s: nominal=%.2f %s amount=%.2f price=%.2f%% purchasePrice=%s", sec.name, sec.quantity, tostring(sec.currencyOfQuantity), sec.amount, sec.price, tostring(sec.purchasePrice))
  end
  local n = 0
  for _, u in ipairs(REQUESTS) do if u:find("operations") then n = n + 1 end end
  return table.concat(out, " | ") .. string.format(" | operations requests=%d | LocalStorage: indexNet=%s until=%s cur=%s",
    n, tostring(LocalStorage["indexNet_bci5-uuid"]), tostring(LocalStorage.indexNetUntil), tostring(LocalStorage.indexNetCurrency))
end)

run("T37 next session: only operations after the stored timestamp are requested, net unchanged", { withBci5 = true, honourFrom = true }, function()
  -- LocalStorage carries over from T36; the script itself starts afresh like in MoneyMoney
  dofile(EXT)
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "index"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  local q = {}
  for _, u in ipairs(REQUESTS) do if u:find("operations") then q[#q + 1] = (u:gsub(".*operations%??", "")) end end
  return string.format("nominal=%.2f price=%.2f%% | operations queries: %s | indexNet=%s", r.securities[1].quantity, r.securities[1].price, table.concat(q, " ; "), tostring(LocalStorage["indexNet_bci5-uuid"]))
end)

run("T38 fiat account: index legs booked with index names, constituent in purpose, rebalancing nets to zero", { withBci5 = true }, function()
  LocalStorage = {}
  session()
  local r = RefreshAccount(findAccount(ListAccounts({}), "fiat"), 0)
  if type(r) ~= "table" then return "-> " .. tostring(r) end
  local byName, sums, sample = {}, {}, nil
  for _, t in ipairs(r.transactions) do
    if t.name:find("Index") then
      byName[t.name] = (byName[t.name] or 0) + 1
      sums[t.name] = (sums[t.name] or 0) + t.amount
      if t.name:find("Index%-Kauf") and sample == nil then sample = t.purpose:gsub("\n", " / ") .. " [" .. t.bookingText .. "]" end
    end
  end
  local parts = {}
  for k, v in pairs(byName) do parts[#parts + 1] = string.format("%s x%d sum=%.2f", k, v, sums[k]) end
  table.sort(parts)
  return table.concat(parts, " | ") .. "\n   sample: " .. tostring(sample)
end)
