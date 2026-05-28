from __future__ import annotations

import datetime as dt
import os
import re
import sys
from pathlib import Path

import requests


BASE_URL = "https://api.heavenection.com"
LOGIN_URL = f"{BASE_URL}/developer/login/"
RELEASES_URL = f"{BASE_URL}/developer/releases/"
APK_PATH = Path("staff_app/build/app/outputs/flutter-apk/app-release.apk")


def _extract_csrf(html: str) -> str:
    match = re.search(r'name="csrfmiddlewaretoken"\s+value="([^"]+)"', html)
    if not match:
        raise RuntimeError("Could not extract CSRF token from page.")
    return match.group(1)


def _ensure_release_build_exists() -> None:
    if not APK_PATH.exists():
        raise RuntimeError(f"APK not found at: {APK_PATH}")


def main() -> int:
    identifier = os.getenv("LIVE_DEV_IDENTIFIER", "").strip()
    password = os.getenv("LIVE_DEV_PASSWORD", "").strip()
    if not identifier or not password:
        raise RuntimeError("LIVE_DEV_IDENTIFIER and LIVE_DEV_PASSWORD must be set.")

    _ensure_release_build_exists()

    session = requests.Session()
    session.headers.update(
        {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) HeavenectionReleaseBot/1.0",
        }
    )

    login_page = session.get(LOGIN_URL, timeout=45)
    login_page.raise_for_status()
    csrf_login = _extract_csrf(login_page.text)

    login_response = session.post(
        LOGIN_URL,
        data={
            "csrfmiddlewaretoken": csrf_login,
            "identifier": identifier,
            "password": password,
        },
        headers={"Referer": LOGIN_URL},
        allow_redirects=True,
        timeout=60,
    )
    if login_response.status_code >= 400:
        alert_messages = re.findall(
            r'<div class="alert[^"]*">(.*?)</div>',
            login_response.text,
            flags=re.IGNORECASE | re.DOTALL,
        )
        alert_messages = [
            re.sub(r"<[^>]+>", "", msg).strip() for msg in alert_messages if msg.strip()
        ]
        snippet = re.sub(r"\s+", " ", login_response.text)[:300]
        raise RuntimeError(
            f"Release Center login failed with status {login_response.status_code}. "
            f"Alerts: {alert_messages or 'none'}. Response snippet: {snippet}"
        )

    releases_page = session.get(RELEASES_URL, timeout=45)
    releases_page.raise_for_status()
    if "Publish Mobile Update" not in releases_page.text:
        raise RuntimeError("Login failed or developer release page is not accessible.")
    csrf_release = _extract_csrf(releases_page.text)

    published_at = dt.datetime.now().strftime("%Y-%m-%dT%H:%M")
    with APK_PATH.open("rb") as apk_file:
        publish_response = session.post(
            RELEASES_URL,
            data={
                "csrfmiddlewaretoken": csrf_release,
                "release_action": "upload_release",
                "version_name": "1.0.15",
                "version_code": "18",
                "minimum_supported_version_code": "0",
                "release_notes": (
                    "Updater reliability improvements: fixed download tracking, "
                    "failure handling, and install prompt flow."
                ),
                "is_active": "on",
                "published_at": published_at,
            },
            files={
                "apk_file": (
                    "heavenection-v1.0.15+18.apk",
                    apk_file,
                    "application/vnd.android.package-archive",
                )
            },
            headers={"Referer": RELEASES_URL},
            allow_redirects=True,
            timeout=240,
        )
    publish_response.raise_for_status()

    verify_page = session.get(RELEASES_URL, timeout=45)
    verify_page.raise_for_status()
    body = verify_page.text
    if "Release number 18" not in body:
        raise RuntimeError(
            "Release upload request completed, but version code 18 is not visible in live release history."
        )
    row_match = re.search(
        r"Release number\s+18.*?<td>\s*<span class=\"hc-status[^>]*\">(.*?)</span>",
        body,
        flags=re.IGNORECASE | re.DOTALL,
    )
    if row_match:
        row_status = re.sub(r"\s+", " ", row_match.group(1)).strip().lower()
        if row_status != "active":
            raise RuntimeError(
                f"Version 18 exists, but row status is '{row_status}' instead of Active."
            )

    print("SUCCESS: Live Release Center now lists version 1.0.15 (18).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"ERROR: {exc}")
        raise SystemExit(1)
