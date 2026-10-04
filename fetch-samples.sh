#!/usr/bin/env bash
# Collects additional sample responses from the Bitpanda Public API for the replay test:
#   1) the COMPLETE operations history (all pages)
#   2) a probe of the `from` filter (does it filter on credited_at?)
#   3) error responses (wrong key, unknown ticker) incl. HTTP status codes
#   4) small checks: default page size of /assets, /portfolio with equivalent_currency_id
# Usage:  BP_KEY=your-api-key ./fetch-samples-v2.sh
# Output: bp_samples/*  (your own balances are inside – do not share unredacted)
set -euo pipefail
: "${BP_KEY:?set BP_KEY to your Bitpanda API key}"
B="https://api.public.bitpanda.com/v1"
OUT="bp_samples"; mkdir -p "$OUT"
EUR="b88b8466-efe3-11eb-b56f-0691764446a7"
get()  { curl -sS -H "x-api-key: $BP_KEY" -H "Accept: application/json" "$@"; }
# like get, but also records the HTTP status code in a side file (always sends the key)
getS() { local name="$1"; shift; curl -sS -o "$OUT/$name.json" -w '%{http_code}' -H "x-api-key: $BP_KEY" -H "Accept: application/json" "$@" > "$OUT/$name.http"; echo "   $name: HTTP $(cat "$OUT/$name.http")"; }

echo "0) portfolio + currencies snapshot (same moment as the operations below) ..."
get "$B/portfolio"  > "$OUT/portfolio.json"
get "$B/currencies" > "$OUT/currencies.json"
python3 -c "import json;d=json.load(open('$OUT/portfolio.json'));print('   portfolio positions:', len(d['data']))"

echo "1) operations, all pages ..."
cursor=""; page=0; : > "$OUT/operations_all.ndjson"
rm -f "$OUT"/operations_page_*.json
while :; do
  page=$((page+1))
  url="$B/operations?page_size=100${cursor:+&cursor=$cursor}"
  get "$url" > "$OUT/operations_page_$page.json"
  python3 - "$OUT/operations_page_$page.json" >> "$OUT/operations_all.ndjson" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
if "data" not in d:
    sys.stderr.write("   unexpected response: %s\n" % json.dumps(d)[:200]); sys.exit(1)
for op in d["data"]: print(json.dumps(op))
EOF
  cursor=$(python3 -c "import json;d=json.load(open('$OUT/operations_page_$page.json'));print(d.get('next_cursor','') if d.get('has_next_page') else '')")
  [ -z "$cursor" ] && break
  [ $page -ge 200 ] && break
done
echo "   pages: $page, operations: $(wc -l < "$OUT/operations_all.ndjson")"

echo "2) from-filter probe ..."
# boundary = credited_at of the 40th-newest operation; expected = ops with any leg credited_at >= boundary
FROM=$(python3 - "$OUT/operations_all.ndjson" <<'EOF'
import json, sys
ops = [json.loads(l) for l in open(sys.argv[1])]
if len(ops) < 45: sys.exit(0)
print(ops[39]["transactions"][0]["credited_at"])
EOF
)
if [ -n "$FROM" ]; then
  getS "operations_from_probe" "$B/operations?page_size=100&from=$FROM"
  python3 - "$OUT/operations_all.ndjson" "$OUT/operations_from_probe.json" "$FROM" <<'EOF'
import json, sys
ops = [json.loads(l) for l in open(sys.argv[1])]
probe = json.load(open(sys.argv[2])).get("data", [])
FROM = sys.argv[3]
def newest(op): return max(t["credited_at"] for t in op["transactions"])
def oldest(op): return min(t["credited_at"] for t in op["transactions"])
expected = {op["operation_id"] for op in ops if newest(op) >= FROM}
got = {op["operation_id"] for op in probe}
older = [op["operation_id"] for op in probe if newest(op) < FROM]
print("   from=%s  returned=%d  expected(by credited_at)=%d  missing=%d  older-than-from=%d  has_next_page=%s"
      % (FROM, len(got), len(expected), len(expected - got), len(older), json.load(open(sys.argv[2])).get("has_next_page")))
print("   => 'from' filters on credited_at: %s" % ("yes" if (expected == got) else "NO / unclear – see numbers"))
EOF
  # second probe: from = a very old date must return the full history (paged)
  getS "operations_from_old" "$B/operations?page_size=100&from=2020-01-01T00:00:00.000Z"
  python3 -c "import json;d=json.load(open('$OUT/operations_from_old.json'));print('   from=2020-01-01: returned', len(d.get('data',[])), 'has_next_page =', d.get('has_next_page'))"
else
  echo "   fewer than 45 operations – probe skipped"
fi

echo "3) error samples ..."
curl -sS -o "$OUT/error_401.json" -w '%{http_code}' -H "x-api-key: invalid-key-for-testing" -H "Accept: application/json" "$B/portfolio" > "$OUT/error_401.http"
echo "   wrong key: HTTP $(cat "$OUT/error_401.http") body: $(head -c 300 "$OUT/error_401.json")"
curl -sS -o "$OUT/error_nokey.json" -w '%{http_code}' -H "Accept: application/json" "$B/portfolio" > "$OUT/error_nokey.http"
echo "   no key:    HTTP $(cat "$OUT/error_nokey.http") body: $(head -c 300 "$OUT/error_nokey.json")"
getS "error_ticker_404" "$B/tickers/00000000-0000-0000-0000-000000000000"
echo "   body: $(head -c 300 "$OUT/error_ticker_404.json")"
getS "error_bad_cursor" "$B/operations?page_size=100&cursor=nonsense"
echo "   body: $(head -c 300 "$OUT/error_bad_cursor.json")"

echo "4) small checks ..."
getS "assets_default_page" "$B/assets"
python3 -c "import json;d=json.load(open('$OUT/assets_default_page.json'));print('   /assets without page_size returns', len(d.get('data',[])), 'entries, has_next_page =', d.get('has_next_page'))"
getS "portfolio_eur" "$B/portfolio?equivalent_currency_id=$EUR"
python3 -c "import json;d=json.load(open('$OUT/portfolio_eur.json'));print('   /portfolio?equivalent_currency_id=EUR:', 'ok,', len(d['data']), 'positions' if 'data' in d else d)"
getS "operations_page_size_500" "$B/operations?page_size=500"
python3 -c "import json;d=json.load(open('$OUT/operations_page_size_500.json'));print('   /operations?page_size=500 returns', len(d.get('data',[])), 'entries (max page size clamp?)' if 'data' in d else d)"

echo "done -> $OUT/"
