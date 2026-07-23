#!/usr/bin/env python3
import base64, json, mimetypes, os, re, time
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import HTTPError

SITE=os.environ["GK_SITE_URL"].rstrip("/")
AUTH="Basic "+base64.b64encode((os.environ["WP_USERNAME"]+":"+os.environ["WP_APPLICATION_PASSWORD"]).encode()).decode()
TOKEN=os.environ["GK_UNIFIED_API_TOKEN"]

def call(path,method="GET",body=None,headers=None,raw=False):
    h={"Authorization":AUTH,"Accept":"application/json"}
    if headers: h.update(headers)
    data=None
    if body is not None:
        if isinstance(body,(bytes,bytearray)): data=body
        else:
            data=json.dumps(body,ensure_ascii=False).encode()
            h["Content-Type"]="application/json; charset=utf-8"
    req=Request(SITE+path,data=data,headers=h,method=method)
    for n in range(4):
        try:
            with urlopen(req,timeout=120) as r:
                b=r.read()
                return b if raw else (json.loads(b.decode("utf-8-sig")) if b else {})
        except HTTPError as e:
            detail=e.read().decode("utf-8","replace")
            if e.code in (429,500,502,503,504) and n<3: time.sleep(2**n); continue
            raise RuntimeError(f"{method} {path}: HTTP {e.code}: {detail[:500]}")

def media(slug,path,alt,caption):
    found=call("/wp-json/wp/v2/media?"+urlencode({"slug":slug,"context":"edit","per_page":10}))
    if found: return found[0]
    data=open(path,"rb").read()
    item=call("/wp-json/wp/v2/media","POST",data,{
      "Content-Type":"image/png",
      "Content-Disposition":f'attachment; filename="{slug}.png"'
    })
    return call(f"/wp-json/wp/v2/media/{item['id']}","POST",{"alt_text":alt,"caption":caption,"title":caption})

def find(slug):
    for kind in ("posts","pages"):
        rows=call(f"/wp-json/wp/v2/{kind}?"+urlencode({"slug":slug,"context":"edit","status":"any"}))
        if rows:return kind,rows[0]
    raise RuntimeError("Not found: "+slug)

def content(item):
    v=item.get("content",{})
    return v.get("raw",v.get("rendered","")) if isinstance(v,dict) else v

def update_first_figure(slug,figure,featured=None,prepend=False,marker=None):
    kind,item=find(slug); html=content(item)
    if marker and marker in html: new=html
    elif prepend: new=figure+"\n"+html
    else:
        new,n=re.subn(r"<figure\\b[^>]*>.*?</figure>",figure,html,count=1,flags=re.I|re.S)
        if n!=1: new=figure+"\n"+html
    payload={"content":new}
    if featured: payload["featured_media"]=featured
    call(f"/wp-json/wp/v2/{kind}/{item['id']}","POST",payload)
    check=call(f"/wp-json/wp/v2/{kind}/{item['id']}?context=edit")
    if figure not in content(check): raise RuntimeError("Verification failed: "+slug)
    print("UPDATED_VERIFIED",kind,item["id"],slug)

fiber=media(
 "gk-ftth-cable-photorealistic",
 "assets/gk-ftth-cable-photorealistic.png",
 "Fotorealistischer Aufbau eines FTTH-Glasfaserkabels mit schwarzem Mantel, gelbem Aramidgarn, weißem Pufferröhrchen und dünner Glasfaser.",
 "FTTH-Glasfaserkabel: Mantel, Aramid-Zugentlastung, Pufferröhrchen und die eigentliche dünne Glasfaser."
)
technician=media(
 "gk-telecom-technician-photorealistic",
 "assets/gk-telecom-technician-photorealistic.png",
 "Telekommunikationstechniker bei der Leitungsprüfung an einem geöffneten Kupfer-Hausanschluss im Keller.",
 "Ein Telekommunikationstechniker prüft die Leitung am Hausanschluss mit einem Messgerät."
)

fiber_fig=f'''<figure class="gk-topic-photo gk-photo-verified"><img src="{fiber["source_url"]}" alt="Fotorealistischer Aufbau eines FTTH-Glasfaserkabels mit schwarzem Mantel, gelbem Aramidgarn, weißem Pufferröhrchen und dünner Glasfaser." width="1536" height="1024" loading="eager"><figcaption>Ein echtes Glasfaserkabel besitzt keinen metallischen Innenleiter und keine Koax-Schirmung: Unter dem Mantel liegen Aramid-Zugentlastung, Pufferröhrchen und die sehr dünne Glasfaser.</figcaption></figure>'''
tech_fig=f'''<figure class="gk-article-visual gk-photo-verified"><img src="{technician["source_url"]}" alt="Telekommunikationstechniker bei der Leitungsprüfung an einem geöffneten Kupfer-Hausanschluss im Keller." width="1536" height="1024" loading="eager"><figcaption>Praxis statt Symbolkasten: Leitungsprüfung am Kupfer-Hausanschluss mit Messgerät.</figcaption></figure>'''
apl_real='''<section class="gk-real-component-gallery" data-gk-marker="real-apl-reference"><h2>So sieht ein echter DSL-APL aus</h2><p>Ein APL ist kein einheitlich geformter Kasten. Bauform, Farbe und Alter unterscheiden sich. Typisch ist die Montage im Keller oder Hausanschlussraum; häufig führt ein schwarzes Erdkabel hinein. Das Gehäuse darf nur von berechtigtem Fachpersonal geöffnet werden.</p><div class="gk-real-photo-grid"><figure><img src="https://glasfaser-kompass.de/wp-content/uploads/2026/06/apl_001.jpg" alt="Echter DSL-APL mit schwarzem ankommendem Erdkabel an einer Kellerwand." loading="eager"><figcaption>Typischer DSL-APL mit ankommendem schwarzem Erdkabel.</figcaption></figure><figure><img src="https://glasfaser-kompass.de/wp-content/uploads/2026/06/apl_003.jpg" alt="Geöffneter echter DSL-APL als Referenz für die Bauform; Öffnung nur durch Fachpersonal." loading="lazy"><figcaption>Geöffnete Referenzansicht zur Bauformerkennung – nicht selbst öffnen.</figcaption></figure></div></section>'''

update_first_figure("glasfaser",fiber_fig,fiber["id"])
update_first_figure("was-macht-ein-telekom-techniker-eigentlich",tech_fig,technician["id"])
update_first_figure("apl-tae-signalweg",apl_real,23281,prepend=True,marker='data-gk-marker="real-apl-reference"')

req=Request(SITE+"/wp-json/gk-unified-api/v1/clear-cache",data=b"{}",headers={"Authorization":"Bearer "+TOKEN,"Content-Type":"application/json"},method="POST")
with urlopen(req,timeout=90) as r:
    result=json.loads(r.read().decode("utf-8-sig"))
    if not result.get("cache_cleared"): raise RuntimeError("Cache clear not confirmed")
print("CACHE_CLEARED")
