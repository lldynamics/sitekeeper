#!/usr/bin/env python3
import argparse
import html
import json
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_DIR = REPO_ROOT / "Sources" / "Resources" / "Legal" / "PrivacyPolicy"
DOCS_DIR = REPO_ROOT / "docs" / "legal"


def render_template(text: str, app_name: str, support_email: str) -> str:
    return (
        text.replace("{APP_NAME}", app_name)
        .replace("{SUPPORT_EMAIL}", support_email)
        .strip()
    )


def markdown_document(title: str, last_updated_label: str, last_updated: str, body: str) -> str:
    return f"# {title}\n\n{last_updated_label}: {last_updated}\n\n{body}\n"


def html_document(lang: str, title: str, last_updated_label: str, last_updated: str, body: str) -> str:
    chunks = []
    list_items = []

    def flush_list() -> None:
        nonlocal list_items
        if list_items:
            chunks.append("<ul>" + "".join(f"<li>{item}</li>" for item in list_items) + "</ul>")
            list_items = []

    for block in body.split("\n\n"):
        lines = [line.strip() for line in block.splitlines() if line.strip()]
        if not lines:
            continue
        if all(line.startswith("- ") for line in lines):
            list_items.extend(html.escape(line[2:]) for line in lines)
            flush_list()
            continue
        flush_list()
        if len(lines) == 1 and not lines[0].endswith(("。", ".", ":", "：")):
            chunks.append(f"<h2>{html.escape(lines[0])}</h2>")
        else:
            chunks.append(f"<p>{html.escape(' '.join(lines))}</p>")

    flush_list()
    return f"""<!doctype html>
<html lang="{html.escape(lang)}">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{html.escape(title)}</title>
  <style>
    body {{ font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.65; max-width: 820px; margin: 0 auto; padding: 40px 20px; color: #1f2933; }}
    h1 {{ font-size: 2rem; margin-bottom: 0.25rem; }}
    h2 {{ font-size: 1.15rem; margin-top: 1.75rem; }}
    .updated {{ color: #697386; margin-bottom: 2rem; }}
  </style>
</head>
<body>
  <h1>{html.escape(title)}</h1>
  <p class="updated">{html.escape(last_updated_label)}: {html.escape(last_updated)}</p>
  {"".join(chunks)}
</body>
</html>
"""


def write_or_check(path: Path, content: str, check: bool, stale_paths: list[Path]) -> None:
    if check:
        if not path.exists() or path.read_text(encoding="utf-8") != content:
            stale_paths.append(path)
        return

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description="Export Sitekeeper privacy policy from versioned app resources.")
    parser.add_argument("--app-name-zh-Hans", default="工地掌柜")
    parser.add_argument("--app-name-en", default="Sitekeeper")
    parser.add_argument("--support-email", default="support@chengjinfang.com")
    parser.add_argument("--website-root", type=Path, help="Optional apps-site repo root to receive HTML copies.")
    parser.add_argument("--check", action="store_true", help="Check generated files without writing them.")
    args = parser.parse_args()

    manifest = json.loads((SOURCE_DIR / "privacy-policy.json").read_text(encoding="utf-8"))
    stale_paths: list[Path] = []
    if not args.check:
        DOCS_DIR.mkdir(parents=True, exist_ok=True)

    titles = {
        "zh-Hans": "隐私政策",
        "en": "Privacy Policy",
    }
    last_updated_labels = {
        "zh-Hans": "最后更新",
        "en": "Last updated",
    }

    for locale, entry in manifest["locales"].items():
        source = SOURCE_DIR / f"{entry['resource']}.{entry['fileExtension']}"
        app_name = args.app_name_zh_Hans if locale == "zh-Hans" else args.app_name_en
        body = render_template(source.read_text(encoding="utf-8"), app_name, args.support_email)
        title = titles.get(locale, "Privacy Policy")
        last_updated_label = last_updated_labels.get(locale, "Last updated")
        markdown = markdown_document(title, last_updated_label, entry["lastUpdatedDisplay"], body)
        write_or_check(DOCS_DIR / f"privacy-policy.{locale}.md", markdown, args.check, stale_paths)

        if args.website_root:
            target = (
                args.website_root / "sitekeeper" / "privacy" / "index.html"
                if locale == "zh-Hans"
                else args.website_root / "sitekeeper" / "privacy" / "en" / "index.html"
            )
            write_or_check(
                target,
                html_document(locale, title, last_updated_label, entry["lastUpdatedDisplay"], body),
                args.check,
                stale_paths,
            )

    if stale_paths:
        print("Privacy policy generated files are stale:", file=sys.stderr)
        for path in stale_paths:
            print(f"  {path.relative_to(REPO_ROOT)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
