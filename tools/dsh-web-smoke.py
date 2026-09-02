#!/usr/bin/env python3
"""Preset-independent Playwright smoke check for an already-running DSH Web GUI."""

from __future__ import annotations

import argparse
import json
import os
import sys
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Open an existing DSH Web GUI with an isolated Playwright context, "
            "capture a screenshot, and report Console/network failures."
        )
    )
    parser.add_argument(
        "--url",
        default=os.environ.get("DSH_WEB_URL", "http://127.0.0.1:3080"),
        help="Existing DSH Web URL (default: DSH_WEB_URL or http://127.0.0.1:3080).",
    )
    parser.add_argument(
        "--channel",
        default="msedge",
        help="Installed Chromium channel to launch (default: msedge).",
    )
    parser.add_argument(
        "--output-dir",
        default=".dsh-windows-ops/browser-verification",
        help="Directory for screenshot and JSON summary.",
    )
    parser.add_argument("--timeout-ms", type=int, default=30_000)
    parser.add_argument("--settle-ms", type=int, default=3_000)
    parser.add_argument(
        "--expect-text",
        action="append",
        default=[],
        help="Text that must appear in the rendered body; repeat as needed.",
    )
    parser.add_argument("--headed", action="store_true")
    parser.add_argument("--fail-on-console-error", action="store_true")
    parser.add_argument("--fail-on-request-failure", action="store_true")
    parser.add_argument("--fail-on-http-error", action="store_true")
    return parser.parse_args()


def package_version() -> str:
    try:
        return version("playwright")
    except PackageNotFoundError:
        return "missing"


def main() -> int:
    args = parse_args()
    if args.timeout_ms <= 0 or args.settle_ms < 0:
        print("timeout values must be positive", file=sys.stderr)
        return 2

    try:
        from playwright.sync_api import Error as PlaywrightError
        from playwright.sync_api import sync_playwright
    except ImportError:
        print(
            "Python Playwright is missing. Install the reviewed pin with "
            "`python -m pip install --user playwright==1.62.0`.",
            file=sys.stderr,
        )
        return 2

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    screenshot_path = output_dir / "dsh-web-smoke.png"
    summary_path = output_dir / "dsh-web-smoke.json"

    console_errors: list[str] = []
    request_failures: list[str] = []
    http_failures: list[str] = []
    summary: dict[str, Any] = {
        "requestedUrl": args.url,
        "browserChannel": args.channel,
        "playwrightVersion": package_version(),
        "headed": args.headed,
        "consoleErrors": console_errors,
        "requestFailures": request_failures,
        "httpFailures": http_failures,
        "expectText": args.expect_text,
    }

    exit_code = 0
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(
                channel=args.channel,
                headless=not args.headed,
            )
            context = browser.new_context(viewport={"width": 1440, "height": 900})
            page = context.new_page()
            page.on(
                "console",
                lambda message: console_errors.append(message.text)
                if message.type == "error"
                else None,
            )
            page.on(
                "requestfailed",
                lambda request: request_failures.append(
                    f"{request.method} {request.url}: {request.failure}"
                ),
            )
            page.on(
                "response",
                lambda response: http_failures.append(
                    f"{response.status} {response.url}"
                )
                if response.status >= 400
                else None,
            )

            response = page.goto(
                args.url,
                wait_until="domcontentloaded",
                timeout=args.timeout_ms,
            )
            page.wait_for_timeout(args.settle_ms)
            body_text = page.locator("body").inner_text(timeout=args.timeout_ms)
            missing_text = [text for text in args.expect_text if text not in body_text]
            page.screenshot(path=str(screenshot_path), full_page=True)

            summary.update(
                {
                    "finalUrl": page.url,
                    "documentStatus": response.status if response else None,
                    "title": page.title(),
                    "bodyCharacters": len(body_text),
                    "missingExpectedText": missing_text,
                    "screenshot": str(screenshot_path),
                }
            )

            if response is None or not response.ok:
                exit_code = 1
            if not body_text.strip() or missing_text:
                exit_code = 1
            if args.fail_on_console_error and console_errors:
                exit_code = 1
            if args.fail_on_request_failure and request_failures:
                exit_code = 1
            if args.fail_on_http_error and http_failures:
                exit_code = 1

            context.close()
            browser.close()
    except PlaywrightError as error:
        summary["error"] = str(error)
        exit_code = 1
    except Exception as error:  # Keep the report actionable for automation callers.
        summary["error"] = f"{type(error).__name__}: {error}"
        exit_code = 1

    summary["ok"] = exit_code == 0
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))
    print(f"summary={summary_path}")
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
