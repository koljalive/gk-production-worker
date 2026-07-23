#!/usr/bin/env python3
import base64,json,os,re
from urllib.request import Request,urlopen
SITE=os.environ["GK_SITE_URL"].rstrip("/")
AUTH="Basic "+base64.b64encode((os.environ["WP_USERNAME"]+":"+os.environ["WP_APPLICATION_PASSWORD"]).encode()).decode()
def get(path):
 with urlopen(Request(SITE+path,headers={"Authorization":AUTH,"Accept":"application/json"}),timeout=90) as r:
  return json.loads(r.read().decode("utf-8-sig"))
report={"plugins":[],"social_routes":[],"meta_secret_presence":{}}
try:
 plugins=get("/wp-json/wp/v2/plugins?status=active&per_page=100")
 for p in plugins:
  report["plugins"].append({"plugin":p.get("plugin"),"name":p.get("name"),"status":p.get("status"),"version":p.get("version")})
except Exception as e:
 report["plugin_error"]=str(e)
root=get("/wp-json/")
keywords=re.compile(r"(social|facebook|instagram|meta|publicize|jetpack|blog2social|revive|buffer|postiz|fs-poster)",re.I)
for route,info in root.get("routes",{}).items():
 if keywords.search(route) or keywords.search(json.dumps(info,ensure_ascii=False)):
  report["social_routes"].append(route)
for name in ("META_ACCESS_TOKEN","FACEBOOK_PAGE_ID","FB_PAGE_ID","INSTAGRAM_BUSINESS_ACCOUNT_ID","IG_BUSINESS_ACCOUNT_ID","META_APP_ID","META_APP_SECRET"):
 report["meta_secret_presence"][name]=bool(os.environ.get(name))
print(json.dumps(report,ensure_ascii=False,indent=2))
