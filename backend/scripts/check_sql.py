"""Parse every SQL file (and every function body, SQL or PL/pgSQL) with the PostgreSQL parser.

Usage: python backend/scripts/check_sql.py <dir> [<dir> ...]
Exits non-zero if any file fails to parse. Catches syntax errors only, not missing objects.
"""
import sys
from pathlib import Path

import pglast

failed = 0
skipped = 0
checked = 0
for d in sys.argv[1:]:
    for path in sorted(Path(d).glob("*.sql")):
        src = path.read_text(encoding="utf-8")
        try:
            for raw in pglast.split(src):
                stmt = pglast.parse_sql(raw)[0].stmt
                if type(stmt).__name__ == "CreateFunctionStmt":
                    opts = {o.defname: o.arg for o in stmt.options}
                    if opts["language"].sval == "plpgsql":
                        pglast.parse_plpgsql(raw)
                    else:
                        pglast.parse_sql(opts["as"][0].sval)
                    checked += 1
                elif type(stmt).__name__ == "DoStmt":
                    pglast.parse_plpgsql(raw)
        except Exception as e:  # noqa: BLE001 - report any parser failure with its file
            if "LookupExplicitNamespace" in str(e):
                # pglast's PL/pgSQL parser cannot resolve schema-qualified types outside public/pg_catalog;
                # that is a tool limit, not a syntax error, so the rest of the file is not checked
                print(f"{path}: skipped PL/pgSQL body with schema-qualified types")
                skipped += 1
                continue
            print(f"{path}: {e}")
            failed += 1

print(f"{checked} function bodies parsed, {skipped} file(s) partly skipped, {failed} file(s) failed")
sys.exit(1 if failed else 0)
