#!/usr/bin/env python3
import base64, hashlib, json, os, sys, time
from datetime import datetime, timezone
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

SITE=os.environ["GK_SITE_URL"].rstrip("/")
USER=os.environ["WP_USERNAME"]
APP=os.environ["WP_APPLICATION_PASSWORD"]
TOKEN=os.environ["GK_UNIFIED_API_TOKEN"]
CUTOFF="2026-07-23T00:00:00"
AUTH="Basic "+base64.b64encode(f"{USER}:{APP}".encode()).decode()
HEAD={"Authorization":AUTH,"Accept":"application/json"}
REPORT={"cutoff":CUTOFF,"started":datetime.now(timezone.utc).isoformat(),"items":[],"summary":{}}
os.makedirs("recovery-output/backups",exist_ok=True)

def call(path, method="GET", body=None, bearer=False):
    headers={"Accept":"application/json","Authorization":("Bearer "+TOKEN if bearer else AUTH)}
    data=None
    if body is not None:
        data=json.dumps(body,ensure_ascii=False).encode("utf-8")
        headers["Content-Type"]="application/json; charset=utf-8"
    req=Request(SITE+path,data=data,headers=headers,method=method)
    for attempt in range(4):
        try:
            with urlopen(req,timeout=90) as r:
                raw=r.read()
                return json.loads(raw.decode("utf-8-sig")) if raw else {}
        except HTTPError as e:
            raw=e.read().decode("utf-8","replace")
            if e.code in (429,500,502,503,504) and attempt<3:
                time.sleep(2**attempt); continue
            raise RuntimeError(f"{method} {path}: HTTP {e.code}: {raw[:500]}")

def pages(kind):
    out=[]; page=1
    while True:
        q=urlencode({"context":"edit","status":"any","per_page":100,"page":page,"orderby":"id","order":"asc"})
        try: batch=call(f"/wp-json/wp/v2/{kind}?{q}")
        except RuntimeError as e:
            if "HTTP 400" in str(e) and page>1: break
            raise
        out.extend(batch)
        if len(batch)<100: break
        page+=1
    return out

def raw(field):
    if isinstance(field,dict): return field.get("raw",field.get("rendered",""))
    return field or ""

def sha(s): return hashlib.sha256(s.encode("utf-8")).hexdigest()

for kind in ("posts","pages"):
    for item in pages(kind):
        modified=(item.get("modified_gmt") or item.get("modified") or "")[:19]
        if not modified or modified < CUTOFF: continue
        iid=item["id"]
        current_content=raw(item.get("content"))
        backup_path=f"recovery-output/backups/{kind[:-1]}-{iid}-current.json"
        with open(backup_path,"w",encoding="utf-8") as f: json.dump(item,f,ensure_ascii=False,indent=2)
        revs=call(f"/wp-json/wp/v2/{kind}/{iid}/revisions?context=edit&per_page=100")
        candidates=[]
        for rev in revs:
            rm=(rev.get("modified_gmt") or rev.get("date_gmt") or rev.get("modified") or "")[:19]
            if rm and rm < CUTOFF: candidates.append((rm,rev))
        row={"type":kind[:-1],"id":iid,"slug":item.get("slug"),"current_modified":modified}
        if not candidates:
            row["status"]="NO_PRE_DAY_REVISION"; REPORT["items"].append(row); continue
        _,rev=max(candidates,key=lambda x:x[0])
        target_content=raw(rev.get("content"))
        if sha(current_content)==sha(target_content):
            row.update(status="ALREADY_RESTORED",revision_id=rev.get("id")); REPORT["items"].append(row); continue
        payload={"content":target_content}
        target_title=raw(rev.get("title"))
        target_excerpt=raw(rev.get("excerpt"))
        if target_title: payload["title"]=target_title
        if target_excerpt is not None: payload["excerpt"]=target_excerpt
        updated=call(f"/wp-json/wp/v2/{kind}/{iid}","POST",payload)
        verify=call(f"/wp-json/wp/v2/{kind}/{iid}?context=edit")
        verified=sha(raw(verify.get("content")))==sha(target_content)
        row.update(status=("RESTORED_VERIFIED" if verified else "VERIFY_FAILED"),revision_id=rev.get("id"),target_modified=max(candidates,key=lambda x:x[0])[0])
        REPORT["items"].append(row)
        if not verified: raise RuntimeError(f"Verification failed for {kind}/{iid}")

call("/wp-json/gk-unified-api/v1/clear-cache","POST",{},bearer=True)
from collections import Counter
REPORT["summary"]=dict(Counter(x["status"] for x in REPORT["items"]))
REPORT["finished"]=datetime.now(timezone.utc).isoformat()
with open("recovery-output/rollback-report.json","w",encoding="utf-8") as f: json.dump(REPORT,f,ensure_ascii=False,indent=2)
print(json.dumps(REPORT["summary"],ensure_ascii=False))
