"""Check what the LIVE Supabase project actually serves — not what the repo says.

This exists because of a two-month silent outage. The French email templates
were correct in git, `supabase config push` had been run, the command reported
success, and users still received English bodies: the CLI of the day pushed the
subjects and dropped the contents. Every check we had looked at the repo, so
every check passed.

The lesson generalises: after a deploy, verify the SERVER. A tool's exit code
says the command ran, not that the thing you wanted is true.

What it checks
  - each auth email template GoTrue can send is overridden, in French, with the
    substitution its flow needs ({{ .Token }} for reauthentication, the
    confirmation link everywhere else);
  - the SMTP sender is the Brevo-authenticated domain (otherwise Gmail shows
    "via smtp-brevo.com");
  - the RPCs and tables the app depends on exist, with the guard rails intact.

Credentials: SUPABASE_ACCESS_TOKEN, read from the environment or from
../.dewdrop-secrets/supabase-cli.env. The token is account-wide — it is never
printed, and neither is anything derived from it.

Run:
  python tools/release/verify_prod.py            # after a config/db push
  python tools/release/verify_prod.py --json     # machine-readable
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

API = "https://api.supabase.com/v1"

# Every template GoTrue can send. Keep in step with config.toml and with
# test/supabase/email_templates_test.dart — a flow missing from any of the three
# is a flow that silently falls back to English.
TEMPLATES = {
    "confirmation": "{{ .ConfirmationURL }}",
    "recovery": "{{ .ConfirmationURL }}",
    "email_change": "{{ .ConfirmationURL }}",
    "magic_link": "{{ .ConfirmationURL }}",
    "reauthentication": "{{ .Token }}",
    "invite": "{{ .ConfirmationURL }}",
}

# Database objects the app cannot work without, with the property that matters.
# `search_profiles` is checked for its guard rails, not merely its existence:
# the thresholds ARE the feature (see docs/architecture.md, "Découvrabilité").
DB_CHECKS = [
    (
        "fonction search_profiles",
        "select count(*) from pg_proc where proname = 'search_profiles'",
        lambda rows: rows[0]["count"] == 1,
    ),
    (
        "search_profiles : seuil de similarité + plafond",
        "select prosrc from pg_proc where proname = 'search_profiles'",
        lambda rows: "0.45" in rows[0]["prosrc"] and "limit 3" in rows[0]["prosrc"],
    ),
    (
        "extension pg_trgm",
        "select count(*) from pg_extension where extname = 'pg_trgm'",
        lambda rows: rows[0]["count"] == 1,
    ),
    (
        "vue public_profiles (annuaire restreint)",
        "select count(*) from information_schema.views "
        "where table_name = 'public_profiles'",
        lambda rows: rows[0]["count"] == 1,
    ),
]


def repo_root() -> Path:
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / ".git").exists():
            return parent
    return here.parent.parent


def project_ref(root: Path) -> str:
    ref_file = root / "supabase" / ".temp" / "project-ref"
    if ref_file.exists():
        ref = ref_file.read_text(encoding="utf-8").strip()
        if ref:
            return ref
    sys.exit(
        "Projet Supabase introuvable : lance `supabase link` une fois, ou "
        "renseigne supabase/.temp/project-ref."
    )


def access_token(root: Path) -> str:
    token = os.environ.get("SUPABASE_ACCESS_TOKEN")
    if token:
        return token
    vault = root.parent / ".dewdrop-secrets" / "supabase-cli.env"
    if vault.exists():
        for line in vault.read_text(encoding="utf-8").splitlines():
            if line.startswith("SUPABASE_ACCESS_TOKEN="):
                return line.split("=", 1)[1].strip()
    sys.exit(
        "SUPABASE_ACCESS_TOKEN absent (environnement et "
        "../.dewdrop-secrets/supabase-cli.env). Voir docs/architecture.md."
    )


def api(path: str, token: str, payload: dict | None = None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(
        f"{API}{path}",
        data=data,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            # The management API answers 403 to urllib's default User-Agent.
            # Not a permission problem — it took a curl-vs-urllib comparison to
            # tell the two apart, so leave this header alone.
            "User-Agent": "dewdrop-verify-prod/1.0",
        },
        method="POST" if data else "GET",
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        # Never echo the body verbatim: it can contain request context.
        sys.exit(f"API Supabase {path} : HTTP {e.code}")
    except urllib.error.URLError as e:
        sys.exit(f"API Supabase injoignable : {e.reason}")


def check_emails(cfg: dict) -> list[tuple[bool, str]]:
    out = []
    for flow, needle in TEMPLATES.items():
        subject = cfg.get(f"mailer_subjects_{flow}") or ""
        body = cfg.get(f"mailer_templates_{flow}_content") or ""
        if not body:
            out.append((False, f"{flow} : aucun corps (gabarit anglais par défaut)"))
            continue
        problems = []
        if 'lang="fr"' not in body:
            problems.append("corps pas en français")
        if "DewDrop" not in body:
            problems.append("corps non brandé")
        if needle not in body:
            problems.append(f"{needle} manquant")
        if "DewDrop" not in subject:
            problems.append("sujet non brandé")
        out.append(
            (not problems, f"{flow} : {', '.join(problems) if problems else 'OK'}")
        )

    sender = cfg.get("smtp_admin_email") or ""
    ok = sender.endswith("heianenterprise.com")
    out.append(
        (
            ok,
            f"expéditeur SMTP : {'OK' if ok else 'hors domaine authentifié → Gmail affichera « via smtp-brevo.com »'}",
        )
    )
    return out


def check_db(ref: str, token: str) -> list[tuple[bool, str]]:
    out = []
    for label, sql, verdict in DB_CHECKS:
        try:
            rows = api(f"/projects/{ref}/database/query", token, {"query": sql})
            out.append((bool(verdict(rows)), f"{label} : {'OK' if verdict(rows) else 'ABSENT/ALTÉRÉ'}"))
        except SystemExit:
            raise
        except Exception:
            out.append((False, f"{label} : vérification impossible"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true", help="sortie machine")
    ap.add_argument("--emails-only", action="store_true")
    args = ap.parse_args()

    root = repo_root()
    ref = project_ref(root)
    token = access_token(root)

    results: list[tuple[bool, str]] = []
    cfg = api(f"/projects/{ref}/config/auth", token)
    results += check_emails(cfg)
    if not args.emails_only:
        results += check_db(ref, token)

    failed = [msg for ok, msg in results if not ok]

    if args.json:
        print(json.dumps({"ok": not failed, "checks": [
            {"ok": ok, "detail": msg} for ok, msg in results
        ]}, ensure_ascii=False, indent=2))
    else:
        print(f"\n  Projet {ref} — ce que le serveur sert vraiment\n")
        for ok, msg in results:
            print(f"    {'✓' if ok else '✗'}  {msg}")
        print()
        if failed:
            print(f"  [ÉCHEC] {len(failed)} vérification(s) en défaut.")
            print("  Les gabarits exigent `supabase config push` avec un CLI >= 2.114 ;")
            print("  les objets SQL exigent `supabase db push`.\n")
        else:
            print("  [OK] La production correspond au dépôt.\n")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
