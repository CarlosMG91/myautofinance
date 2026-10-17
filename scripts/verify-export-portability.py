"""T08: lector independiente de ZIP/CSV/SQLite; solo fixtures sintéticas.

No importa Flutter ni código de producto. Requiere Python 3.12+, sin paquetes.
Uso: python scripts/verify-export-portability.py --root .tools/226-public
     --evidence .tools/226-evidence --output .tools/226-evidence/independent.json
Cada plataforma contiene all/january/empty/base-copy/partial/zero/history/
variant-copy.zip, guardados por el recorrido nativo. Las capturas esperadas
proceden del driver (windows.json/android.json). Nunca se abre la base activa.
"""

import argparse
import csv
import hashlib
import io
import json
import pathlib
import re
import sqlite3
import subprocess
import tempfile
import zipfile
from decimal import Decimal


def require(condition, message):
    if not condition:
        raise ValueError(message)


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"Clave JSON duplicada: {key}")
        result[key] = value
    return result


def digest(data):
    return hashlib.sha256(data).hexdigest()


def cents(text):
    require(re.fullmatch(r"-?(0|[1-9][0-9]*)\.[0-9]{2}", text), "EUR no canónico")
    require(text != "-0.00", "Cero negativo")
    value = int(Decimal(text) * 100)
    require(-(2**63) <= value < 2**63, "EUR fuera de int64")
    return value


def read_zip(path):
    with zipfile.ZipFile(path) as archive:
        require(archive.testzip() is None, "CRC inválido")
        names = archive.namelist()
        require(len(names) == len(set(names)), "Entrada ZIP duplicada")
        require(all(re.fullmatch(r"[A-Za-z_]+\.(csv|json|md|sqlite)", n)
                    for n in names), "Inventario inseguro")
        files = {n: archive.read(n) for n in names}
    manifest = json.loads(files["manifest.json"], object_pairs_hook=unique_object)
    require(set(manifest) == {
        "kind", "formatVersion", "exportId", "createdAtUtc", "datasetId",
        "revision", "applicationId", "schemaVersion", "currency", "filter",
        "dictionary", "files", "databaseTables",
    }, "Campos de manifiesto inesperados")
    require(manifest["formatVersion"] == 1 and manifest["currency"] == "EUR",
            "Versión/moneda no admitidas")
    require(manifest["kind"] in ("autofinance.dataExport", "autofinance.portableBackup"),
            "Kind no admitido")
    declared = [f["path"] for f in manifest["files"]]
    require(len(declared) == len(set(declared)), "files duplicados")
    require(set(files) == set(declared) | {"manifest.json"}, "Inventario distinto")
    for entry in manifest["files"]:
        data = files[entry["path"]]
        require(str(len(data)) == entry["sizeBytes"], "Tamaño distinto")
        require(digest(data) == entry["sha256"], "SHA-256 distinto")
    return manifest, files


def check_csv(manifest, files, outcome, dictionary):
    require(manifest["kind"] == "autofinance.dataExport", "No es CSV")
    require(files["diccionario.json"] == dictionary, "Diccionario distinto")
    month = outcome["month"]
    require(manifest["filter"] == {
        "mode": "months" if month else "all",
        "fromMonth": month + "-01" if month else None,
        "throughMonth": month + "-01" if month else None,
    }, "Filtro distinto del formulario")
    counts = {f["path"]: f["rowCount"] for f in manifest["files"]}
    result = {}
    for definition in json.loads(dictionary)["files"]:
        name = definition["path"]
        data = files[name]
        require(not data.startswith(b"\xef\xbb\xbf") and data.endswith(b"\r\n"),
                "BOM/terminador CSV incorrecto")
        reader = csv.DictReader(io.StringIO(data.decode("utf-8"), newline=""),
                                delimiter=";", strict=True)
        rows = list(reader)
        require(reader.fieldnames == [c["name"] for c in definition["columns"]],
                "Cabeceras distintas")
        require(str(len(rows)) == counts[name], "rowCount CSV distinto")
        source = outcome["capture"][definition["sourceTable"]]
        if month and name in ("movimientos.csv", "presupuestos.csv", "fotos.csv"):
            column = "value_date" if name == "movimientos.csv" else "month"
            source = [r for r in source if r[column].startswith(month)]
        if name == "valores_fotos.csv":
            selected = {r["id"] for r in outcome["capture"]["wealth_snapshots"]
                        if not month or r["month"].startswith(month)}
            source = [r for r in source if r["snapshot_id"] in selected]
        require({r["id"] for r in rows} == {r["id"] for r in source},
                f"IDs/filtro distintos en {name}")
        originals = {r["id"]: r for r in source}
        for row in rows:
            for column in definition["columns"]:
                origin = column["source"]
                if origin in originals[row["id"]]:
                    actual = row[column["name"]]
                    expected = originals[row["id"]][origin]
                    if column["type"] in ("eur", "eurNonNegative"):
                        require(cents(actual) == int(expected), "Céntimos distintos")
                    else:
                        require(actual == ("" if expected is None else str(expected)),
                                f"Texto/valor distinto en {name}.{column['name']}")
        result[name] = rows
    accounts = {r["id"] for r in result["cuentas.csv"]}
    categories = {r["id"] for r in result["categorias.csv"]}
    photos = {r["id"] for r in result["fotos.csv"]}
    for row in result["movimientos.csv"]:
        require(row["cuenta_id"] in accounts, "Cuenta sin referencia")
        require(not row["categoria_id"] or row["categoria_id"] in categories,
                "Categoría sin referencia")
    for row in result["presupuestos.csv"]:
        require(row["categoria_id"] in categories, "Presupuesto sin categoría")
    for row in result["valores_fotos.csv"]:
        require(row["cuenta_id"] in accounts and row["foto_id"] in photos,
                "Valor sin referencia")
    stage = outcome["stage"]
    if stage in ("all", "january"):
        movements, budgets = result["movimientos.csv"], result["presupuestos.csv"]
        require(len(movements) == (10 if stage == "all" else 6), "Reales EP-001")
        require(len(budgets) == (48 if stage == "all" else 4), "Presupuestos EP-001")
        require(sum(cents(r["importe_eur"]) for r in movements)
                == (232965 if stage == "all" else 122975), "Real firmado EP-001")
        require(sum(cents(r["importe_eur"]) for r in budgets)
                == (1320000 if stage == "all" else 110000), "Presupuesto firmado EP-001")
        cafes = [r for r in movements if r["concepto"] == "Café"]
        require(len(cafes) == 2 and len({r["id"] for r in cafes}) == 2,
                "Café deduplicado")
        require([r["mes"] for r in result["fotos.csv"]] == ["2026-01-01"],
                "Foto febrero fabricada")
        require(result['fotos.csv'][0]['estado'] == 'complete' and
                result['fotos.csv'][0]['cuentas_esperadas'] == '4' and
                result['fotos.csv'][0]['valores_registrados'] == '4',
                'Foto enero no completa')
    if stage == "empty":
        require(all(not result[n] for n in ("movimientos.csv", "presupuestos.csv",
                    "fotos.csv", "valores_fotos.csv")), "Rango vacío con datos")
        require(all(result[n] for n in ("cuentas.csv", "categorias.csv",
                    "liquidez_cuentas.csv")), "Contexto ausente en rango vacío")
    if stage in ("partial", "zero"):
        photo = result["fotos.csv"]
        require(len(photo) == 1 and photo[0]["estado"] ==
                ("incomplete" if stage == "partial" else "complete"), "Estado de foto")
        require(photo[0]["cuentas_pendientes"] == ("2" if stage == "partial" else "0"),
                "Pendientes de foto")
        if stage == "zero":
            require(any(r["importe_eur"] == "0.00" for r in result["valores_fotos.csv"]),
                    "Cero explícito perdido")
    if stage == "history":
        require(len(result['fotos.csv']) == 2 and
                all(p['estado'] == 'complete' for p in result['fotos.csv']),
                'Fotos de la variante histórica no completas')
        edge = [r for r in result["movimientos.csv"]
                if r["concepto"] == 'Árbol; "Café"\nsegunda línea 🧪']
        require(len(edge) == 1 and edge[0]["importe_eur"] == "92233720368547758.07",
                "Unicode/escape/int64 perdido")
        require(edge[0]["discrecionalidad"] == ' Discrecional; "sí"\r\n漢字 ',
                "Discrecionalidad alterada")
    # Interpretación independiente de fotos completas: ausencia/parcial nunca
    # se sustituye por cero ni por los valores del mes anterior.
    catalog = {r['id']: r for r in result['cuentas.csv']}
    for photo in result['fotos.csv']:
        if photo['estado'] != 'complete':
            continue
        values = [r for r in result['valores_fotos.csv'] if r['foto_id'] == photo['id']]
        net = sum(cents(r['importe_eur']) * (-1 if catalog[r['cuenta_id']]['tipo'] == 'debt' else 1)
                  for r in values)
        liquid = 0
        for value in values:
            periods = [p for p in result['liquidez_cuentas.csv']
                       if p['cuenta_id'] == value['cuenta_id'] and p['desde_mes'] <= photo['mes']
                       and (not p['hasta_mes'] or photo['mes'] < p['hasta_mes'])]
            if periods and periods[0]['liquidez'] == 'liquid':
                liquid += cents(value['importe_eur'])
        expected = (900000, 1400000) if photo['mes'] == '2026-01-01' else (
            1670000 if stage == 'history' else 620000, 1190000)
        require((liquid, net) == expected, 'Lectura patrimonial/liquidez histórica distinta')
    return {n: len(rows) for n, rows in result.items()}


def check_sqlite(manifest, files, outcome, destination, guide):
    require(set(files) == {"manifest.json", "LEEME.md", "autofinance.sqlite"},
            "Inventario de copia completa")
    require(manifest["kind"] == "autofinance.portableBackup" and
            manifest["filter"] is None and manifest["dictionary"] is None, "Copia parcial")
    destination.mkdir()  # Siempre nueva; nunca se sobreescribe una extracción.
    for name, data in files.items():
        (destination / name).write_bytes(data)
    path = destination / "autofinance.sqlite"
    before = digest(path.read_bytes())
    db = sqlite3.connect(path.resolve().as_uri() + "?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    try:
        require(db.execute("PRAGMA integrity_check").fetchone()[0] == "ok", "Integridad SQLite")
        require(not db.execute("PRAGMA foreign_key_check").fetchall(), "Claves SQLite")
        for pragma, field in (("application_id", "applicationId"), ("user_version", "schemaVersion")):
            require(db.execute("PRAGMA " + pragma).fetchone()[0] == manifest[field], field)
        state = db.execute("SELECT dataset_id,revision FROM database_state").fetchone()
        require(state[0] == manifest["datasetId"] and str(state[1]) == manifest["revision"],
                "Identidad/revisión SQLite")
        tables = {r[0] for r in db.execute(
            "SELECT name FROM sqlite_schema WHERE type='table' AND name NOT LIKE 'sqlite_%'")}
        require(tables == set(outcome["capture"]), "Tablas SQLite distintas")
        counts = {r["name"]: r["rowCount"] for r in manifest["databaseTables"]}
        for name in sorted(tables):
            rows = [{k: str(v) if isinstance(v, int) else v for k, v in dict(r).items()}
                    for r in db.execute(f'SELECT * FROM "{name}" ORDER BY 1')]
            require(rows == outcome["capture"][name], f"Captura distinta: {name}")
            require(str(len(rows)) == counts[name], f"Conteo distinto: {name}")
        # Ejecutar cada sentencia SQL publicada de T07, sin copiar su lógica.
        sql_results = []
        integer_overflows = 0
        for block in re.findall(r"```sql\r?\n(.*?)```", guide, re.S):
            statement = ""
            for line in block.splitlines(keepends=True):
                statement += line
                if sqlite3.complete_statement(statement):
                    try:
                        values = db.execute(statement).fetchall()
                    except sqlite3.OperationalError as error:
                        # T07 advierte que sum(INTEGER) no supera int64. La
                        # variante extrema se lee/suma con enteros Python.
                        require(outcome['stage'] == 'variant-copy' and
                                str(error) == 'integer overflow', str(error))
                        integer_overflows += 1
                        values = []
                    sql_results.append([list(r) for r in values])
                    statement = ""
            require(not statement.strip(), "SQL incompleto en T07")
        jan = db.execute("""SELECT
            sum(CASE WHEN a.kind<>'debt' AND p.liquidity='liquid' THEN v.amount_cents ELSE 0 END),
            sum(CASE WHEN a.kind='debt' THEN -v.amount_cents ELSE v.amount_cents END)
            FROM wealth_snapshots s JOIN wealth_values v ON v.snapshot_id=s.id
            JOIN accounts a ON a.id=v.account_id LEFT JOIN account_liquidity_periods p
            ON p.account_id=a.id AND p.from_month<=s.month AND
            (p.until_month IS NULL OR s.month<p.until_month) WHERE s.month='2026-01-01'""").fetchone()
        require(tuple(jan) == (900000, 1400000), "Patrimonio enero EP-001")
        if outcome['stage'] == 'base-copy':
            require(db.execute("SELECT count(*) FROM wealth_snapshots WHERE month='2026-02-01'").fetchone()[0] == 0,
                    'La copia base fabrica febrero')
            require(sum(int(r['amount_cents']) for r in outcome['capture']['movements']) == 232965,
                    'Real anual SQLite EP-001')
            require(sum(int(r['amount_cents']) for r in outcome['capture']['budgets']) == 1320000,
                    'Presupuesto anual SQLite EP-001')
        else:
            feb = db.execute("""SELECT
                sum(CASE WHEN a.kind<>'debt' AND p.liquidity='liquid' THEN v.amount_cents ELSE 0 END),
                sum(CASE WHEN a.kind='debt' THEN -v.amount_cents ELSE v.amount_cents END)
                FROM wealth_snapshots s JOIN wealth_values v ON v.snapshot_id=s.id
                JOIN accounts a ON a.id=v.account_id LEFT JOIN account_liquidity_periods p
                ON p.account_id=a.id AND p.from_month<=s.month AND
                (p.until_month IS NULL OR s.month<p.until_month) WHERE s.month='2026-02-01'""").fetchone()
            require(tuple(feb) == (1670000, 1190000), 'Liquidez febrero SQLite')
        return {"tables": len(tables), "guideStatements": len(sql_results),
                "guideIntegerOverflows": integer_overflows,
                "exactMovementTotalCents": str(sum(int(r['amount_cents']) for r in outcome['capture']['movements'])),
                "januaryLiquidCents": jan[0], "januaryNetCents": jan[1]}
    finally:
        db.close()
        require(digest(path.read_bytes()) == before, "Lectura modificó SQLite")
        require(set(p.name for p in destination.iterdir()) == set(files), "Sidecar inesperado")


def check_negative(path, guide_script=None, sqlite_cli=None):
    """Lectura externa: un CRC válido tampoco basta si el manifiesto miente."""
    manifest, files = read_zip(path)
    with tempfile.TemporaryDirectory(prefix="export-negative-") as temp:
        root = pathlib.Path(temp)
        corrupt = root / "corrupt.zip"
        corrupt.write_bytes(path.read_bytes()[:-30])
        false_manifest = root / "false-manifest.zip"
        manifest["files"][0]["sha256"] = "0" * 64
        with zipfile.ZipFile(false_manifest, "w") as archive:
            for name, data in files.items():
                archive.writestr(name, json.dumps(manifest).encode() if name == "manifest.json" else data)
        for candidate in (corrupt, false_manifest):
            try:
                read_zip(candidate)
            except (ValueError, zipfile.BadZipFile, KeyError):
                continue
            raise ValueError("Falso éxito con ZIP/manifiesto dañado")
        checked = ["truncatedZipRejected", "mismatchingManifestRejected"]
        if sqlite_cli:
            manifest, files = read_zip(path)
            candidates = [corrupt, false_manifest]
            for field, value in [('revision', '999999'), ('formatVersion', 2)]:
                altered = dict(manifest, **{field: value})
                candidate = root / f'{field}.zip'
                with zipfile.ZipFile(candidate, 'w') as archive:
                    for name, data in files.items():
                        archive.writestr(name, json.dumps(altered).encode() if name == 'manifest.json' else data)
                candidates.append(candidate)
            previous = root / 'previous'
            previous.mkdir()
            sentinel = previous / 'keep.txt'
            sentinel.write_text('Copia sintética anterior; conservar', encoding='utf-8')
            candidates.append(path)
            original = digest(path.read_bytes())
            for index, candidate in enumerate(candidates):
                destination = previous if candidate == path else root / f'new-{index}'
                process = subprocess.run([
                    'powershell.exe', '-NoProfile', '-File', str(guide_script),
                    '-Zip', str(candidate.resolve()), '-Destination', str(destination.resolve()),
                    '-Sqlite', str(sqlite_cli.resolve()),
                ], capture_output=True, timeout=60)
                require(process.returncode != 0, 'T07 informa éxito ante entrada no válida/destino existente')
            require(digest(path.read_bytes()) == original and
                    sentinel.read_text(encoding='utf-8') == 'Copia sintética anterior; conservar',
                    'T07 negativo alteró original/destino anterior')
            checked += ['guideTruncatedZipRejected', 'guideHashMismatchRejected',
                        'guideRevisionMismatchRejected', 'guideUnsupportedVersionRejected',
                        'guideExistingDestinationProtected']
    return checked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=pathlib.Path, required=True)
    parser.add_argument("--evidence", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--platform", choices=("windows", "android"), nargs="+",
                        default=["windows", "android"])
    parser.add_argument("--sqlite-cli", type=pathlib.Path,
                        help="Ejecuta también los negativos reales del script PowerShell T07")
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parents[1]
    dictionary = (repo / "docs/ep-027/diccionario-v1.json").read_bytes()
    guide = (repo / "docs/ep-027/recuperacion-sqlite.md").read_text(encoding="utf-8")
    result = {"syntheticDataOnly": True, "pythonSqliteVersion": sqlite3.sqlite_version,
              "platforms": {}}
    # Mantener extracciones para inspección; nunca reutilizar un destino previo.
    recovered = pathlib.Path(tempfile.mkdtemp(prefix="Consulta nueva con tildes á-"))
    for platform in args.platform:
        report = json.loads((args.evidence / f"{platform}.json").read_text(encoding="utf-8"))
        require(report["syntheticDataOnly"] and report["privateCopiesUnchanged"], "Fixture no acreditada")
        stages = {}
        for outcome in report["outcomes"]:
            if outcome["stage"] == "cancel":
                require(outcome["result"] == "ExportSaveCancelled", "Cancelación falló")
                continue
            stage = outcome["stage"]
            path = args.root / platform / f"{stage}.zip"
            manifest, files = read_zip(path)
            require(manifest["datasetId"] == outcome["datasetId"] and
                    manifest["revision"] == outcome["revision"], "Captura/UI no coincide")
            checked = (check_sqlite(manifest, files, outcome, recovered / f"{platform}-{stage}", guide)
                       if outcome["complete"] else check_csv(manifest, files, outcome, dictionary))
            stages[stage] = {"bytes": path.stat().st_size, "sha256": digest(path.read_bytes()),
                             "datasetId": manifest['datasetId'],
                             "revision": manifest["revision"],
                             "manifestSha256": digest(files['manifest.json']),
                             "sqliteSha256": digest(files['autofinance.sqlite']) if outcome['complete'] else None,
                             "checks": checked}
        require(set(stages) == {"all", "january", "empty", "base-copy", "partial", "zero", "history", "variant-copy"},
                "Faltan ámbitos/variantes nativos")
        result["platforms"][platform] = stages
        result.setdefault("negativeChecks", {})[platform] = check_negative(
            args.root / platform / "base-copy.zip",
            repo / 'scripts/check-export-recovery-guide.ps1', args.sqlite_cli)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"OK: {len(args.platform) * 8} ZIP nativos; CSV exactos, "
          f"{len(args.platform) * 2} SQLite completas y consultas T07. Extracciones: {recovered}")


if __name__ == "__main__":
    main()
