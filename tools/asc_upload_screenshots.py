#!/usr/bin/env python3
"""Upload App Store screenshots to App Store Connect through its API.

Puts each folder of PNGs into the matching screenshot set of the app's editable App Store
version (the one in "Prepare for Submission"), for the primary locale, replacing what is there.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY (the .p8 contents), BUNDLE_ID.
Usage: asc_upload_screenshots.py DISPLAY_TYPE=FOLDER [DISPLAY_TYPE=FOLDER ...]
  e.g. APP_IPHONE_67=shots/iphone-6.9 APP_IPAD_PRO_3GEN_129=shots/ipad-13
"""
import base64
import hashlib
import json
import os
import pathlib
import re
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT with the crypto extra

API = "https://api.appstoreconnect.apple.com/v1"


def pem_from_secret(raw):
    """Rebuild a clean PEM whatever form the secret was pasted in."""
    raw = raw.replace("\r", "")
    body = re.sub(r"[^A-Za-z0-9+/=]", "", re.sub(r"-----(BEGIN|END)[A-Z ]*-----", "", raw))
    decoded = base64.b64decode(body + "=" * (-len(body) % 4))
    if b"PRIVATE KEY" in decoded:  # the whole .p8 file, base64-encoded once more
        text = decoded.decode("utf-8", "replace")
        body = re.sub(r"[^A-Za-z0-9+/=]", "", re.sub(r"-----(BEGIN|END)[A-Z ]*-----", "", text))
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n"


KEY = pem_from_secret(os.environ["ASC_KEY"])
KEY_ID = os.environ["ASC_KEY_ID"]
ISSUER = os.environ["ASC_ISSUER_ID"]
_token = {"value": None, "exp": 0}


def token():
    now = int(time.time())
    if now > _token["exp"] - 60:
        exp = now + 15 * 60
        _token["value"] = jwt.encode({"iss": ISSUER, "iat": now, "exp": exp, "aud": "appstoreconnect-v1"},
                                     KEY, algorithm="ES256", headers={"kid": KEY_ID, "typ": "JWT"})
        _token["exp"] = exp
    return _token["value"]


def call(method, path, body=None, ok=(200, 201, 204)):
    url = path if path.startswith("http") else API + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        sys.exit(f"{method} {path} failed: HTTP {e.code}\n{detail}")


def main():
    pairs = [a.split("=", 1) for a in sys.argv[1:]]
    bundle = os.environ["BUNDLE_ID"]

    apps = call("GET", f"/apps?filter[bundleId]={bundle}")["data"]
    if not apps:
        sys.exit(f"No app with bundle ID {bundle} in App Store Connect.")
    app = apps[0]
    print(f"App: {app['attributes']['name']} ({app['id']})")

    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED",
                "INVALID_BINARY", "WAITING_FOR_REVIEW"}
    versions = call("GET", f"/apps/{app['id']}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    version = next((v for v in versions if v["attributes"].get("appStoreState") in editable
                    or v["attributes"].get("appVersionState") in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED",
                                                                   "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}),
                   None)
    if version is None:
        states = [(v["attributes"]["versionString"], v["attributes"].get("appStoreState")) for v in versions]
        sys.exit(f"No editable App Store version found; versions: {states}")
    print(f"Version: {version['attributes']['versionString']} ({version['attributes'].get('appStoreState')})")

    locs = call("GET", f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations")["data"]
    primary = app["attributes"].get("primaryLocale", "en-US")
    loc = next((l for l in locs if l["attributes"]["locale"] == primary), locs[0] if locs else None)
    if loc is None:
        loc = call("POST", "/appStoreVersionLocalizations", {"data": {
            "type": "appStoreVersionLocalizations", "attributes": {"locale": primary},
            "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}}}})["data"]
    print(f"Locale: {loc['attributes']['locale']}")

    sets = call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
    failures = 0
    for display_type, folder in pairs:
        files = sorted(pathlib.Path(folder).glob("*.png"))
        if not files:
            sys.exit(f"No PNGs in {folder}")
        sset = next((s for s in sets if s["attributes"]["screenshotDisplayType"] == display_type), None)
        if sset is None:
            sset = call("POST", "/appScreenshotSets", {"data": {
                "type": "appScreenshotSets", "attributes": {"screenshotDisplayType": display_type},
                "relationships": {"appStoreVersionLocalization": {"data": {
                    "type": "appStoreVersionLocalizations", "id": loc["id"]}}}}})["data"]
        existing = call("GET", f"/appScreenshotSets/{sset['id']}/appScreenshots")["data"]
        for shot in existing:
            call("DELETE", f"/appScreenshots/{shot['id']}")
        print(f"\n{display_type}: replacing {len(existing)} with {len(files)} from {folder}")

        uploaded = []
        for f in files:
            data = f.read_bytes()
            shot = call("POST", "/appScreenshots", {"data": {
                "type": "appScreenshots", "attributes": {"fileName": f.name, "fileSize": len(data)},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": sset["id"]}}}}})["data"]
            for op in shot["attributes"]["uploadOperations"]:
                chunk = data[op["offset"]:op["offset"] + op["length"]]
                headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
                req = urllib.request.Request(op["url"], data=chunk, method=op["method"], headers=headers)
                with urllib.request.urlopen(req) as r:
                    r.read()
            call("PATCH", f"/appScreenshots/{shot['id']}", {"data": {
                "type": "appScreenshots", "id": shot["id"],
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
            uploaded.append((f.name, shot["id"]))
            print(f"  uploaded {f.name}")

        # Wait for Apple to process each image.
        for name, sid in uploaded:
            for _ in range(60):
                st = call("GET", f"/appScreenshots/{sid}")["data"]["attributes"].get("assetDeliveryState") or {}
                if st.get("state") in ("COMPLETE", "FAILED"):
                    break
                time.sleep(5)
            if st.get("state") == "COMPLETE":
                print(f"  processed {name}")
            else:
                failures += 1
                print(f"  ::error::{name}: {st.get('state')} {json.dumps(st.get('errors') or st.get('warnings'))}")
    if failures:
        sys.exit(f"{failures} screenshot(s) were not accepted.")
    print("\nAll screenshots uploaded and processed.")


if __name__ == "__main__":
    main()
