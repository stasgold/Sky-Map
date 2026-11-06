#!/usr/bin/env python3
"""Read-only pre-submission check of the App Store version in App Store Connect.

Reads back what Apple holds for the editable version and prints PASS / WARN / FAIL per item.
Changes nothing. Environment: ASC_KEY_ID, ASC_ISSUER_ID, ASC_KEY, BUNDLE_ID.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import asc_metadata as asc  # noqa: E402  (reuses its authenticated API helper)

call, ASCError = asc.call, asc.ASCError
results = []


def report(level, item, detail=""):
    results.append(level)
    print(f"{level:4}  {item}" + (f" — {detail}" if detail else ""))


def main():
    L = json.load(open("appstore/listing.json", encoding="utf-8"))
    app = call("GET", f"/apps?filter[bundleId]={os.environ['BUNDLE_ID']}")["data"][0]
    app_id = app["id"]
    report("PASS", "App record", f"{app['attributes']['name']} ({app_id}), bundle {app['attributes']['bundleId']}")
    cr = app["attributes"].get("contentRightsDeclaration")
    report("PASS" if cr else "FAIL", "Content rights declaration", str(cr))

    versions = call("GET", f"/apps/{app_id}/appStoreVersions?filter[platform]=IOS&limit=20")["data"]
    editable = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY",
                "WAITING_FOR_REVIEW", "IN_REVIEW"}
    v = next((x for x in versions if x["attributes"].get("appStoreState") in editable), versions[0])
    va = v["attributes"]
    report("PASS", "Version", f"{va['versionString']} — {va.get('appStoreState')}")
    report("PASS" if va.get("copyright") else "FAIL", "Copyright", str(va.get("copyright")))

    # Listing text (version localization).
    locs = call("GET", f"/appStoreVersions/{v['id']}/appStoreVersionLocalizations")["data"]
    loc = next((l for l in locs if l["attributes"]["locale"] == L["locale"]), None)
    if not loc:
        report("FAIL", f"Version localization {L['locale']}", "missing")
    else:
        a = loc["attributes"]
        for key, limit in (("description", 4000), ("keywords", 100), ("promotionalText", 170)):
            val = a.get(key) or ""
            ok = bool(val) and len(val) <= limit
            report("PASS" if ok else "FAIL", key, f"{len(val)}/{limit} chars")
        for key in ("supportUrl", "marketingUrl"):
            report("PASS" if a.get(key) else ("FAIL" if key == "supportUrl" else "WARN"), key, str(a.get(key)))
        # Screenshots.
        sets = call("GET", f"/appStoreVersionLocalizations/{loc['id']}/appScreenshotSets")["data"]
        need = {"APP_IPHONE_67": "iPhone 6.9\"", "APP_IPAD_PRO_3GEN_129": "iPad 13\""}
        for s in sets:
            t = s["attributes"]["screenshotDisplayType"]
            shots = call("GET", f"/appScreenshotSets/{s['id']}/appScreenshots")["data"]
            states = [(x["attributes"].get("assetDeliveryState") or {}).get("state") for x in shots]
            done = sum(st == "COMPLETE" for st in states)
            ok = done == len(shots) and len(shots) > 0
            report("PASS" if ok else "FAIL", f"Screenshots {need.get(t, t)}", f"{done}/{len(shots)} processed")
            need.pop(t, None)
        for t, label in need.items():
            report("FAIL", f"Screenshots {label}", "none (required)")

    # App info: name, subtitle, privacy policy, categories, age rating.
    infos = call("GET", f"/apps/{app_id}/appInfos")["data"]
    info = next((i for i in infos if i["attributes"].get("appStoreState") in editable
                 or i["attributes"].get("state") in {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED"}), infos[0])
    ilocs = call("GET", f"/appInfos/{info['id']}/appInfoLocalizations")["data"]
    il = next((l for l in ilocs if l["attributes"]["locale"] == L["locale"]), None)
    if il:
        a = il["attributes"]
        report("PASS" if a.get("name") == L["name"] else "FAIL", "Name", str(a.get("name")))
        report("PASS" if a.get("subtitle") else "WARN", "Subtitle", str(a.get("subtitle")))
        report("PASS" if a.get("privacyPolicyUrl") else "FAIL", "Privacy policy URL", str(a.get("privacyPolicyUrl")))
    else:
        report("FAIL", "App info localization", "missing")
    for rel in ("primaryCategory", "secondaryCategory"):
        try:
            c = call("GET", f"/appInfos/{info['id']}/{rel}").get("data")
            report("PASS" if c else ("FAIL" if rel == "primaryCategory" else "WARN"), rel, c["id"] if c else "not set")
        except ASCError as e:
            report("WARN", rel, str(e)[:120])
    decl = call("GET", f"/appInfos/{info['id']}/ageRatingDeclaration")["data"]["attributes"]
    unanswered = [k for k, val in decl.items() if val is None and k not in {
        "kidsAgeBand", "ageRatingOverride", "ageRatingOverrideV2", "koreaAgeRatingOverride",
        "developerAgeRatingInfoUrl", "gracRatingClassificationNumber", "seventeenPlus", "socialMediaAgeRestricted"}]
    report("PASS" if not unanswered else "FAIL", "Age rating questionnaire",
           "all answered" if not unanswered else "unanswered: " + ", ".join(unanswered))
    rating = info["attributes"].get("appStoreAgeRating")
    if rating:
        report("PASS", "Resulting age rating", rating)

    # Build.
    try:
        b = call("GET", f"/appStoreVersions/{v['id']}/build").get("data")
    except ASCError:
        b = None
    if not b:
        report("FAIL", "Build attached", "none")
    else:
        ba = b["attributes"]
        report("PASS" if ba.get("processingState") == "VALID" else "FAIL", "Build attached",
               f"{ba.get('version')} — {ba.get('processingState')}, expired={ba.get('expired')}")
        enc = ba.get("usesNonExemptEncryption")
        report("PASS" if enc is False else "WARN", "Export compliance", f"usesNonExemptEncryption={enc}")
        if ba.get("version") and int(ba["version"]) < 12:
            report("FAIL", "Build number", "builds below 12 contain the info-card crash")

    # Review details.
    try:
        rd = call("GET", f"/appStoreVersions/{v['id']}/appStoreReviewDetail").get("data")
    except ASCError:
        rd = None
    if not rd:
        report("FAIL", "App Review information", "missing")
    else:
        a = rd["attributes"]
        report("PASS" if a.get("notes") else "WARN", "Review notes", f"{len(a.get('notes') or '')} chars")
        report("PASS" if a.get("demoAccountRequired") is False else "WARN", "Sign-in required", str(a.get("demoAccountRequired")))
        missing = [k for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail") if not a.get(k)]
        report("PASS" if not missing else "FAIL", "Review contact details",
               "complete" if not missing else "missing: " + ", ".join(missing))

    # Price and availability.
    try:
        sched = call("GET", f"/apps/{app_id}/appPriceSchedule?include=manualPrices,baseTerritory")
        prices = [i for i in sched.get("included", []) if i["type"] == "appPrices"]
        report("PASS" if prices else "FAIL", "Price schedule", f"{len(prices)} manual price(s) set")
    except ASCError as e:
        report("FAIL", "Price schedule", str(e)[:150])
    try:
        avail = call("GET", f"/apps/{app_id}/appAvailabilityV2")["data"]
        n, on, url = 0, 0, f"/v2/appAvailabilities/{avail['id']}/territoryAvailabilities?limit=200"
        while url:
            page = call("GET", url)
            for ta in page["data"]:
                n += 1
                on += bool(ta["attributes"].get("available"))
            nxt = page.get("links", {}).get("next")
            url = ("/v2" + nxt.split("/v2", 1)[1]) if nxt else None
        report("PASS" if on else "FAIL", "Availability", f"{on} of {n} territories")
    except ASCError as e:
        report("FAIL", "Availability", str(e)[:150])

    report("INFO", "App Privacy questionnaire", "no API — confirm in App Store Connect that it is published")
    fails = results.count("FAIL")
    print(f"\n{results.count('PASS')} pass, {results.count('WARN')} warn, {fails} fail")
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
