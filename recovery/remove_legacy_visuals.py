#!/usr/bin/env python3
import base64,json,os,re
from urllib.parse import urlencode
from urllib.request import Request,urlopen
SITE=os.environ["GK_SITE_URL"].rstrip("/")
AUTH="Basic "+base64.b64encode((os.environ["WP_USERNAME"]+":"+os.environ["WP_APPLICATION_PASSWORD"]).encode()).decode()
TOKEN=os.environ["GK_UNIFIED_API_TOKEN"]
def call(path,method="GET",body=None,bearer=False):
 h={"Authorization":("Bearer "+TOKEN if bearer else AUTH),"Accept":"application/json"}
 data=None
 if body is not None:
  data=json.dumps(body,ensure_ascii=False).encode();h["Content-Type"]="application/json; charset=utf-8"
 with urlopen(Request(SITE+path,data=data,headers=h,method=method),timeout=120) as r:
  b=r.read();return json.loads(b.decode("utf-8-sig")) if b else {}
def clean(slug,need,legacy):
 for kind in ("posts","pages"):
  rows=call(f"/wp-json/wp/v2/{kind}?"+urlencode({"slug":slug,"context":"edit","status":"any"}))
  if not rows:continue
  item=rows[0];html=item["content"].get("raw",item["content"].get("rendered",""))
  for token in legacy:
   pattern=r"<figure\b[^>]*>.*?"+re.escape(token)+r".*?</figure>"
   while re.search(pattern,html,flags=re.I|re.S):
    html=re.sub(pattern,"",html,count=1,flags=re.I|re.S)
  if need not in html:raise RuntimeError("Required replacement missing: "+slug)
  call(f"/wp-json/wp/v2/{kind}/{item['id']}","POST",{"content":html})
  verify=call(f"/wp-json/wp/v2/{kind}/{item['id']}?context=edit")["content"]["raw"]
  if any(x in verify for x in legacy):raise RuntimeError("Legacy visual remains: "+slug)
  print("CLEANED_VERIFIED",slug,item["id"]);return
 raise RuntimeError("Not found: "+slug)
clean("glasfaser","gk-ftth-cable-photorealistic.png",["gk-render-guard/assets/glasfaser.png"])
clean("was-macht-ein-telekom-techniker-eigentlich","gk-telecom-technician-photorealistic.png",["gk-og-techniker-20313.svg"])
call("/wp-json/gk-unified-api/v1/clear-cache","POST",{},True)
print("CACHE_CLEARED")
