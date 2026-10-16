#!/usr/bin/env bash
# Prüft, wie die Bitpanda Public API einen Cursor behandelt, der aus einem Zeitstempel OHNE
# Millisekunden entsteht (base64 endet dann auf "="). Hintergrund: Seite 8 bei Stefan wurde mit
# Cursor 2025-12-02T16:39:48Z angefordert und die API lieferte Seite 1 zurück.
#
# Aufruf:  BP_KEY=dein-api-key ./cursor-test.sh
# Ausgabe: pro Variante Anzahl, ältester Zeitstempel der ersten Operation, self_cursor, next_cursor.
#          "akzeptiert" = die erste Operation liegt VOR dem Testzeitstempel; "Seite 1" = Neustart.
set -euo pipefail
: "${BP_KEY:?BP_KEY auf den Bitpanda-API-Key setzen}"
B="https://api.public.bitpanda.com/v1"
TMP=$(mktemp -d)
get() { curl -sS -H "x-api-key: $BP_KEY" -H "Accept: application/json" "$@"; }
summarize() {
  python3 -c '
import json, sys, base64
d = json.load(sys.stdin)
if "data" not in d:
    print("   FEHLER:", json.dumps(d)[:200]); sys.exit(0)
ops = d["data"]
def dec(c):
    if not c: return "-"
    try: return base64.b64decode(c + "=" * (-len(c) % 4)).decode()
    except Exception: return repr(c)
first = min(t["credited_at"] for t in ops[0]["transactions"]) if ops else "-"
ts = sys.argv[1]
verdict = "" if not ts else ("  => akzeptiert" if first < ts else "  => Seite 1 (Neustart)")
print("   n=%d  erste Operation=%s  self_cursor=%s  next_cursor=%s%s" % (len(ops), first, dec(d.get("self_cursor")), dec(d.get("next_cursor")), verdict))
' "${1:-}"
}

echo "0) Seite 1 als Referenz"
get "$B/operations?page_size=5" > "$TMP/p1.json"; summarize < "$TMP/p1.json"

# Testzeitstempel: credited_at der 3. Operation von Seite 1, ohne Millisekunden
TS=$(python3 -c 'import json;d=json.load(open("'"$TMP"'/p1.json"));ops=d["data"];t=min(x["credited_at"] for x in ops[2]["transactions"]);print(t[:19]+"Z")')
PAD=$(printf %s "$TS" | base64)
NOPAD=${PAD%%=*}
ENC=${PAD//=/%3D}
echo "   Testzeitstempel: $TS"
echo "   Cursor gepolstert: $PAD   ohne Padding: $NOPAD   prozentkodiert: $ENC"
echo
echo "1) Cursor mit '=' roh (so sendet curl / fetch-samples.sh)"
get "$B/operations?page_size=5&cursor=$PAD" | summarize "$TS"
echo "2) Cursor mit '=' als %3D (so sendet MoneyMoney nach MM.urlencode)"
get "$B/operations?page_size=5&cursor=$ENC" | summarize "$TS"
echo "3) Cursor ohne '=' (Padding entfernt)"
get "$B/operations?page_size=5&cursor=$NOPAD" | summarize "$TS"
echo "4) Kontrolle: next_cursor von Seite 1 unverändert"
NC=$(python3 -c 'import json;print(json.load(open("'"$TMP"'/p1.json")).get("next_cursor",""))')
get "$B/operations?page_size=5&cursor=$NC" | summarize
echo "5) Kontrolle: derselbe Zeitstempel über den to-Parameter statt Cursor"
get "$B/operations?page_size=5&to=$TS" | summarize "$TS"
rm -rf "$TMP"
echo "fertig – bitte die komplette Ausgabe zurückgeben"
