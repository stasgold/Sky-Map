#!/usr/bin/env python3
"""Fill in the App Store listing through the App Store Connect API.

Applies appstore/listing.json to the app's editable App Store version: name, subtitle and
privacy policy URL (app info); description, keywords, promotional text and support and
marketing URLs (version localization); copyright; categories; content-rights declaration;
the age-rating questionnaire (all "none", rated 4+); App Review notes; and the build to submit
(the newest processed build of the version, or BUILD_NUMBER if set). Each part is applied
separately and reported, so one rejected field does not stop the rest.

App Store Connect has no API for the App Privacy questionnaire, so that stays a manual step,
as do the App Review contact details (name, phone, e-mail), which are yours to give.

Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY (.p8 contents), BUNDLE_ID, optional BUILD_NUMBER.
"""
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

import jwt  # PyJWT with the crypto extra

API = "https://api.appstoreconnect.apple.com/v1"


class ASCError(Exception):
    pass


def pem_from_secret(raw):
    raw = raw.replace("\r", "")
    body = re.sub(r"[^A-Za-z0-9+/=]", "", re.sub(r"-----(BEGIN|END)[A-Z ]*-----", "", raw))
    decoded = base64.b64decode(body + "=" * (-len(body) % 4))
    if b"PRIVATE KEY" in decoded:
        text = decoded.decode("utf-8", "replace")
        body = re.sub(r"[^A-Za-z0-9+/=]", "", re.sub(r"-----(BEGIN|END)[A-Z ]*-----", "", text))
    lines = [body[i:i + 64] for i in range(0, len(body), 64)]
    return "-----BEGIN PRIVATE KEY-----\n" + "\n".join(lines) + "\n-----END PRIVATE KEY-----\n"


KEY = pem_from_secret(os.environ["ASC_KEY"])
_tok = {"v": None, "exp": 0}


def token():
    now = int(time.time())
    if now > _tok["exp"] - 60:
        _tok["exp"] = now + 900
        _tok["v"] = jwt.encode({"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": _tok["exp"],
                                "aud": "appstoreconnect-v1"}, KEY, algorithm="ES256",
                               headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"})
    return _tok["v"]


def call(method, path, body=None):
    req = urllib.request.Request(API + path, data=json.dumps(body).encode() if body is not None else None,
                                 method=method, headers={"Authorization": f"Bearer {token()}",
                                                         "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            text = r.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        raise ASCError(f"{method} {path} -> HTTP {e.code}: {e.read().decode()[:1500]}")


results = []


def step(name, fn):
    try:
        detail = fn()
        results.append((True, name, detail or ""))
        print(f"OK    {name} {detail or ''}")
    except Exception as e:  # report and carry on with the next part
        results.append((False, name, str(e)))
        print(f"FAIL  {name}\n      {e}")


def main():
    L = json.load(open("appstore/listing.json", encoding="utf-8"))
    bundle = os.environ["BUNDLE_ID"]
    app = call("GET", f"/apps?filter[bundleId]={bundle}")["data"][0]
    app_id = app["id"]
    print(f"App {app['attributes']['name']} ({app_id})")

    versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=50")["data"]
    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}
    version = next(v for v in versions if v["attributes"].get("appStoreState") in editable
                   or v["attributes"].get("appVersionState") in editable)
    vid = version["id"]
    print(f"Version {version['attributes']['versionString']} ({version['attributes'].get('appStoreState')})")

    infos = call("GET", f"/apps/{app_id}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("appStoreState") in editable
                 or i["attributes"].get("state") in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"}), infos[0])
    info_id = info["id"]

    def app_info_localization():
        locs = call("GET", f"/appInfos/{info_id}/appInfoLocalizations")["data"]
        loc = next((l for l in locs if l["attributes"]["locale"] == L["locale"]), None)
        attrs = {"name": L["name"], "subtitle": L["subtitle"], "privacyPolicyUrl": L["privacyPolicyUrl"]}
        if loc:
            call("PATCH", f"/appInfoLocalizations/{loc['id']}", {"data": {
                "type": "appInfoLocalizations", "id": loc["id"], "attributes": attrs}})
        else:
            call("POST", "/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations", "attributes": {"locale": L["locale"], **attrs},
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info_id}}}}})
        return "(name, subtitle, privacy policy URL)"

    def version_localization():
        locs = call("GET", f"/appStoreVersions/{vid}/appStoreVersionLocalizations")["data"]
        loc = next((l for l in locs if l["attributes"]["locale"] == L["locale"]), None)
        attrs = {k: L[k] for k in ("description", "keywords", "promotionalText", "supportUrl", "marketingUrl")}
        if loc:
            call("PATCH", f"/appStoreVersionLocalizations/{loc['id']}", {"data": {
                "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": attrs}})
        else:
            call("POST", "/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations", "attributes": {"locale": L["locale"], **attrs},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        return "(description, keywords, promotional text, support & marketing URLs)"

    def copyright_():
        call("PATCH", f"/appStoreVersions/{vid}", {"data": {
            "type": "appStoreVersions", "id": vid, "attributes": {"copyright": L["copyright"]}}})

    def categories():
        call("PATCH", f"/appInfos/{info_id}", {"data": {"type": "appInfos", "id": info_id, "relationships": {
            "primaryCategory": {"data": {"type": "appCategories", "id": L["primaryCategory"]}},
            "secondaryCategory": {"data": {"type": "appCategories", "id": L["secondaryCategory"]}}}}})
        return f"({L['primaryCategory']}, {L['secondaryCategory']})"

    def content_rights():
        call("PATCH", f"/apps/{app_id}", {"data": {"type": "apps", "id": app_id, "attributes": {
            "contentRightsDeclaration": L["contentRightsDeclaration"]}}})

    def age_rating():
        decl = call("GET", f"/appInfos/{info_id}/ageRatingDeclaration")["data"]
        # Answer "none"/"no" to every content question. Enum questions take NONE; yes/no
        # questions take false. Overrides and the kids band are left unset.
        enums = {"alcoholTobaccoOrDrugUseOrReferences", "contests", "gamblingSimulated", "gunsOrOtherWeapons",
                 "horrorOrFearThemes", "matureOrSuggestiveThemes", "medicalOrTreatmentInformation",
                 "profanityOrCrudeHumor", "sexualContentGraphicAndNudity", "sexualContentOrNudity",
                 "violenceCartoonOrFantasy", "violenceRealistic", "violenceRealisticProlongedGraphicOrSadistic"}
        skip = {"kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride",
                "developerAgeRatingInfoUrl", "seventeenPlus"}
        attrs = {}
        for k, v in decl["attributes"].items():
            if k in skip:
                continue
            if k in enums or isinstance(v, str):
                attrs[k] = "NONE"
            elif isinstance(v, bool) or v is None:
                attrs[k] = False
        call("PATCH", f"/ageRatingDeclarations/{decl['id']}", {"data": {
            "type": "ageRatingDeclarations", "id": decl["id"], "attributes": attrs}})
        return f"({len(attrs)} questions answered none/no)"

    def review_notes():
        try:
            detail = call("GET", f"/appStoreVersions/{vid}/appStoreReviewDetail").get("data")
        except ASCError:
            detail = None
        attrs = {"notes": L["reviewNotes"], "demoAccountRequired": False}
        if detail:
            call("PATCH", f"/appStoreReviewDetails/{detail['id']}", {"data": {
                "type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}})
        else:
            call("POST", "/appStoreReviewDetails", {"data": {"type": "appStoreReviewDetails", "attributes": attrs,
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": vid}}}}})
        return "(notes; no sign-in required — add your contact details in App Store Connect)"

    def build():
        want = os.environ.get("BUILD_NUMBER")
        builds = call("GET", f"/builds?filter[app]={app_id}&filter[preReleaseVersion.version]="
                             f"{version['attributes']['versionString']}&filter[processingState]=VALID"
                             f"&sort=-uploadedDate&limit=20")["data"]
        if not builds:  # the version string may differ (e.g. 1.0 vs 1.0.0); fall back to all builds
            builds = call("GET", f"/builds?filter[app]={app_id}&filter[processingState]=VALID"
                                 f"&sort=-uploadedDate&limit=20")["data"]
        if want:
            builds = [b for b in builds if b["attributes"]["version"] == want]
        if not builds:
            raise ASCError("no processed (VALID) build found yet; try again once processing finishes")
        b = builds[0]
        call("PATCH", f"/appStoreVersions/{vid}/relationships/build", {"data": {"type": "builds", "id": b["id"]}})
        return f"(build {b['attributes']['version']})"

    step("App name, subtitle, privacy policy URL", app_info_localization)
    step("Description, keywords, promotional text, URLs", version_localization)
    step("Copyright", copyright_)
    step("Categories", categories)
    step("Content rights", content_rights)
    step("Age rating", age_rating)
    step("App Review notes", review_notes)
    step("Build for this version", build)

    failed = [r for r in results if not r[0]]
    print(f"\n{len(results) - len(failed)} of {len(results)} parts applied.")
    print("Still manual in App Store Connect: App Privacy (answer 'Data Not Collected') and the "
          "App Review contact name, phone and e-mail.")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
