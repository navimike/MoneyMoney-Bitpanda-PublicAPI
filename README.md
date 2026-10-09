# Bitpanda-Extension für MoneyMoney (Public API)

Inoffizielle MoneyMoney-Extension für Bitpanda auf Basis der neuen
[Bitpanda Public API](https://docs.public.bitpanda.com) (`api.public.bitpanda.com/v1`).
Nachfolger der Legacy-API-Extension von
[GimliGloinsSon](https://github.com/GimliGloinsSon/MoneyMoney-bitpanda-Extension).
Status: unsigniert, aktuelle Version 2.04 (siehe `version` im Skriptkopf).

## Installation

1. `bitpanda-api.lua` in den Extensions-Ordner kopieren (MoneyMoney → Hilfe → *Datenbank im Finder anzeigen* → `Extensions`), danach MoneyMoney neu starten. Für unsignierte Extensions muss in den Einstellungen die Signaturprüfung ausgeschaltet sein.
2. Bei Bitpanda einen API-Key erzeugen (Kontoeinstellungen → API) mit den Scopes **Balances** und **Transaction**; laut Bitpanda-Doku deckt **Trade (Read)** Assets, Währungen und Kurse ab.
3. In MoneyMoney Konto hinzufügen → Service *Bitpanda (Public API)* → den API-Key ins **Passwortfeld** eintragen (Benutzername beliebig).

## Konten

Pro Fiat-Wallet ein Konto (z. B. *Bitpanda EUR*) mit Umsätzen, dazu Depots. Standard ist ein Depot je Asset-Gruppe (Krypto, Aktien, ETFs, ETCs, Metalle, Indizes, Cash Plus, Sonstige); mit `SPLIT_DEPOTS = false` oben im Skript gibt es stattdessen ein einziges Depot. Alle Depots werden beim Einrichten angelegt, weil MoneyMoney die Kontenliste später nicht erneut abfragt – leere Depots lassen sich in MoneyMoney ausblenden. Depots werden in EUR bewertet.

## Verhalten

- Jeder API-Fehler, jedes fehlende Feld und jeder unbekannte Wert bricht die Aktualisierung mit einer Fehlermeldung ab; es werden nie Teildaten geliefert. Vorübergehende Fehler (429, 5xx, Netzwerk) werden bis zu dreimal wiederholt.
- Börsenorders bestehen bei Bitpanda aus einer Reserve-Operation und der ausführenden Operation; Reserve- und Transfer-Legs heben sich im Wallet auf und werden nicht gebucht, Kauf/Verkauf, Gebühr und Steuer schon. Stornierte Einzahlungen (`asset_balance_after = -1`) werden ausgelassen. Damit entspricht die Summe der Umsätze der Saldoänderung des Wallets.
- Jeder Umsatz trägt die Bitpanda-Transaktions-ID im Verwendungszweck, damit MoneyMoney gleich aussehende Buchungen (gleicher Tag, Betrag und Text) nicht als Duplikate verwirft.
- Umsätze werden ab `since` minus 7 Tage abgefragt; Duplikate verwirft MoneyMoney.
- Ein plötzlich leeres Portfolio wird zweimal abgewiesen, bevor es übernommen wird (Schutz vor API-Aussetzern).

## Tests

- `bitpanda-api-testharness.lua`: stubbt die MoneyMoney-Laufzeit und prüft ~30 Szenarien (Pagination, Fehlerformate, Vorzeichen, fehlende Felder, Duplikate). Aufruf: `TZ=Europe/Berlin lua5.3 bitpanda-api-testharness.lua` (auch `texlua` aus TeX Live funktioniert).
- `bitpanda-api-replay.lua`: fährt die Extension gegen gespeicherte echte API-Antworten und gleicht Umsatzsumme und Saldo mit `asset_balance_after` ab. Die Antworten holt `fetch-samples.sh` (eigener API-Key nötig); sie enthalten Kontostände und gehören nicht ins Repository.

## Fehlersuche

Bei langen Historien steht jede geladene Seite der Umsätze im MoneyMoney-Protokoll (Fenster → Protokoll): `operations: Seite n, m Einträge, Cursor <Zeitstempel>`. Bei einer Fehlermeldung bitte diese Zeilen zusammen mit der Meldung melden.

## Änderungen

- 2.04 – Paginierung: Zyklenerkennung über die Cursor statt über Operations-IDs (behebt den Abbruch „Paginierung beginnt von vorn“ bei langen Historien), jede Seite wird protokolliert.
- 2.03 – Review-Fassung: Transaktions-ID im Verwendungszweck, strikte Feldsemantik für Depotpositionen, deutsche Meldungen, `SPLIT_DEPOTS`.

## Lizenz

MIT, siehe Kopf von `bitpanda-api.lua`.
