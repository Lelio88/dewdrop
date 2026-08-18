"""One command to ship a release, with the checks in front of the build.

Shipping DewDrop is seven steps — bump, commit, build with the right
--dart-define, confirm the bundle is the one you think, upload, verify, push.
Done by hand, the step that gets skipped is never the same one, and two of them
fail silently: a build without --dart-define points at the LOCAL Supabase and
compiles perfectly, and a stale AAB uploads perfectly.

So the order is deliberate. Everything that can say "no" runs BEFORE the four
minutes of Gradle: a dirty tree, a failing analyze, a failing test. Everything
that can only be checked afterwards — does this bundle really target the cloud —
runs before the upload, not after.

Nothing here is clever; it just refuses to skip.

Run:
  python tools/release/ship.py --notes-file notes.txt          # alpha
  python tools/release/ship.py --notes-file notes.txt --push   # …and push main
  python tools/release/ship.py --dry-run                       # rehearse
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass


def root() -> Path:
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / ".git").exists():
            return parent
    sys.exit("Dépôt git introuvable.")


def run(cmd: list[str], cwd: Path, capture: bool = False) -> subprocess.CompletedProcess:
    return subprocess.run(
        cmd, cwd=cwd, text=True, shell=False,
        capture_output=capture, encoding="utf-8", errors="replace",
    )


def step(n: int, total: int, label: str) -> None:
    print(f"\n  [{n}/{total}] {label}")


def fail(msg: str) -> None:
    print(f"\n  ✗ {msg}\n")
    raise SystemExit(1)


def read_version(repo: Path) -> str:
    for line in (repo / "pubspec.yaml").read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            return line.split(":", 1)[1].strip()
    fail("Version absente de pubspec.yaml.")
    return ""


def supabase_defines(repo: Path) -> list[str]:
    """The --dart-define pair, from the vault outside the repo.

    Their absence is the silent failure this whole script exists to prevent:
    without them the app builds fine and talks to a Supabase that only exists on
    this machine.
    """
    vault = repo.parent / ".dewdrop-secrets" / "supabase-cloud.env"
    if not vault.exists():
        fail(f"Coffre introuvable : {vault}")
    values: dict[str, str] = {}
    for line in vault.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        values[k.strip()] = v.strip()
    missing = {"SUPABASE_URL", "SUPABASE_ANON_KEY"} - values.keys()
    if missing:
        fail(f"Clés manquantes dans le coffre : {', '.join(sorted(missing))}")
    return [
        f"--dart-define=SUPABASE_URL={values['SUPABASE_URL']}",
        f"--dart-define=SUPABASE_ANON_KEY={values['SUPABASE_ANON_KEY']}",
    ]


def bundle_targets_cloud(repo: Path, url: str) -> bool:
    """Look inside the built bundle for the cloud host.

    Dart stores string literals in Latin-1, UTF-8 or UTF-16 depending on their
    contents, so a single-encoding search reports false absences. The host is
    plain ASCII, but the rule is worth respecting where it costs nothing.
    """
    import zipfile

    aab = repo / "build/app/outputs/bundle/release/app-release.aab"
    host = url.replace("https://", "").rstrip("/")
    with zipfile.ZipFile(aab) as z:
        names = [n for n in z.namelist() if n.endswith("libapp.so")]
        if not names:
            return False
        blob = z.read(names[0])
    for enc in ("latin-1", "utf-8", "utf-16-le"):
        try:
            if blob.count(host.encode(enc)) > 0:
                return True
        except UnicodeEncodeError:
            continue
    return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--track", default="alpha")
    ap.add_argument("--notes-file")
    ap.add_argument("--push", action="store_true", help="pousser main après publication")
    ap.add_argument("--dry-run", action="store_true", help="tout sauf la publication")
    ap.add_argument("--skip-tests", action="store_true", help="à n'utiliser qu'en connaissance de cause")
    args = ap.parse_args()

    repo = root()
    version = read_version(repo)
    total = 7
    print(f"\n  DewDrop {version} → track « {args.track} »")

    step(1, total, "Arbre git propre ?")
    dirty = run(["git", "status", "--porcelain"], repo, capture=True).stdout.strip()
    if dirty:
        fail(
            "Modifications non commitées — la version publiée doit correspondre à "
            f"un commit :\n{dirty}"
        )
    print("      OK")

    step(2, total, "flutter analyze")
    if run(["flutter", "analyze"], repo).returncode != 0:
        fail("Analyse en échec.")
    print("      OK")

    step(3, total, "flutter test")
    if args.skip_tests:
        print("      IGNORÉ (--skip-tests)")
    elif run(["flutter", "test"], repo).returncode != 0:
        fail("Tests en échec.")
    else:
        print("      OK")

    step(4, total, "Build de l'AAB signé")
    defines = supabase_defines(repo)
    if run(["flutter", "build", "appbundle", "--release", *defines], repo).returncode != 0:
        fail("Build en échec.")
    print("      OK")

    step(5, total, "Le bundle vise-t-il bien Supabase cloud ?")
    url = next(d for d in defines if d.startswith("--dart-define=SUPABASE_URL=")).split("=", 2)[2]
    if not bundle_targets_cloud(repo, url):
        fail(
            "L'hôte Supabase cloud est ABSENT du binaire : l'app pointerait vers "
            "la stack locale et ne joindrait rien chez un testeur."
        )
    print("      OK")

    step(6, total, "Publication Play")
    publish = [sys.executable, "tools/release/publish_play.py", "--track", args.track]
    if args.notes_file:
        publish += ["--notes-file", args.notes_file]
    if args.dry_run:
        publish += ["--dry-run"]
    if run(publish, repo).returncode != 0:
        fail("Publication en échec.")

    step(7, total, "Vérification de la production Supabase")
    if run([sys.executable, "tools/release/verify_prod.py"], repo).returncode != 0:
        print("      ⚠ La production ne correspond pas au dépôt (voir ci-dessus).")
        print("      L'app est publiée ; il reste un `supabase db push` / `config push`.")
    else:
        print("      OK")

    if args.push and not args.dry_run:
        print("\n  Push de main…")
        if run(["git", "push", "origin", "main"], repo).returncode != 0:
            fail("git push en échec.")

    print(f"\n  ✓ {version} expédié.\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
