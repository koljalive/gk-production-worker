using GkProductionWorker;
using System.Net;
using System.Reflection;
using System.Text;
using System.Text.Json;

var failures = 0;
void Test(string name, Action action) { try { action(); Console.WriteLine("PASS " + name); } catch (Exception e) { failures++; Console.WriteLine("FAIL " + name + ": " + e.Message); } }
void Assert(bool value, string message) { if (!value) throw new Exception(message); }

var cfg = new WorkerConfig { RequireTwoOfficialSources = true, CheckImagesAndAiObjects = true };
Test("unchanged content passes", () => Assert(QualityGate.Check(new(1,"abc content long enough","abc content long enough",[],[],true,true,false),cfg).Passed,"should pass"));
Test("content loss blocks", () => Assert(!QualityGate.Check(new(1,new string('a',300),"short",[],["https://telekom.de/a","https://bundesnetzagentur.de/b"],true,true,false),cfg).Passed,"should block"));
Test("two source rule", () => Assert(!QualityGate.Check(new(1,"old long enough","new long enough",[],["https://telekom.de/a","https://www.telekom.de/b"],true,true,true),cfg).Passed,"same host should not count twice"));
Test("media rule", () => Assert(!QualityGate.Check(new(1,"old long enough","new long enough",[],["https://telekom.de/a","https://bundesnetzagentur.de/b"],false,true,true),cfg).Passed,"media should block"));

Test("editorial cleanup does not require factual sources", () =>
{
    var proposal = new CorrectionProposal(1, "<p>Techniker prüfen den Hausanschluss.</p>", "<p>Techniker prüfen den Hausanschluss sorgfältig.</p>", [], [], true, true, false);
    Assert(QualityGate.Check(proposal, cfg).Passed, "editorial cleanup was blocked by source gate");
});
Test("deterministic KI-frei gates block duplicate and filler", () =>
{
    var proposal = new CorrectionProposal(1, "old content long enough", "<h2>Glasfaser prüfen</h2><h2>Glasfaser prüfen</h2><p>In conclusion: ultimativ 100% garantiert.</p>", [], ["https://telekom.de/a", "https://bundesnetzagentur.de/b"], true, true, false);
    var result = QualityGate.Check(proposal, cfg);
    Assert(!result.Passed && result.Findings.Any(x => x.Code == "DUPLICATE_CONTENT") && result.Findings.Any(x => x.Code == "LANGUAGE_MIX"), "KI-frei findings missing");
});
Test("affiliate gates require https rel and disclosure", () =>
{
    var proposal = new CorrectionProposal(1, "old content long enough", "<p><a href='http://shop.test/router?ref=abc' rel='nofollow'>Router kaufen</a></p>", [], ["https://telekom.de/a", "https://bundesnetzagentur.de/b"], true, true, false);
    var result = QualityGate.Check(proposal, cfg);
    Assert(!result.Passed && result.Findings.Any(x => x.Code == "AFFILIATE_HTTPS") && result.Findings.Any(x => x.Code == "AFFILIATE_REL") && result.Findings.Any(x => x.Code == "AFFILIATE_DISCLOSURE"), "affiliate findings missing");
});
Test("valid affiliate disclosure passes deterministic gate", () =>
{
    var proposal = new CorrectionProposal(1, "old content long enough", "<p>Anzeige: Bei qualifizierten Käufen erhalten wir eine Provision.</p><p><a href='https://shop.test/router?ref=abc' rel='sponsored nofollow'>passender Router</a></p>", [], ["https://telekom.de/a", "https://bundesnetzagentur.de/b"], true, true, false);
    Assert(QualityGate.Check(proposal, cfg).Passed, "valid affiliate markup was blocked");
});
Test("contradictory proposal finding blocks publication", () =>
{
    var proposal = new CorrectionProposal(1, "<p>Originaler Text zum Anschluss.</p>", "<p>Geänderter Text zum Anschluss.</p>", [new("CONTRADICTORY_PROPOSAL", "blocker", "Die KI-Antwort ist widersprüchlich: corrected_html wurde trotz requires_change=false geändert.")], [], true, true, false);
    var result = QualityGate.Check(proposal, cfg);
    Assert(!result.Passed && result.Findings.Any(x => x.Code == "CONTRADICTORY_PROPOSAL" && x.Severity == "blocker"), "contradiction was not blocking");
});
Test("mislabeled factual edits still require sources", () =>
{
    var proposal = new CorrectionProposal(1, "<p>Der Tarif kostet 40 Euro.</p>", "<p>Der Tarif kostet 30 Euro.</p>", [], ["https://telekom.de/a"], true, true, true);
    var result = QualityGate.Check(proposal, cfg);
    Assert(!result.Passed && result.Findings.Any(x => x.Code == "INSUFFICIENT_SOURCES"), "factual edit bypassed source gate");
});
Test("deterministic duplicate cleanup can bypass factual sources", () =>
{
    var original = "<p>Der Techniker misst den Pegel am ONT.</p><p>Der Techniker misst den Pegel am ONT.</p>";
    var corrected = "<p>Der Techniker misst den Pegel am ONT.</p>";
    var proposal = new CorrectionProposal(1, original, corrected, [], [], true, true, false);
    Assert(QualityGate.Check(proposal, cfg).Passed, "duplicate cleanup was blocked by factual sources");
});
Test("duplicate links inside changed section are deterministic cleanup", () =>
{
    var original = "<section><p>Weiterführende Artikel für die Praxis.</p><a href='/a'>Router für Glasfaser richtig auswählen</a><a href='/b'>Router für Glasfaser richtig auswählen</a><a href='/c'>ONT im Haus richtig einordnen</a></section>";
    var corrected = "<section><p>Weiterführende Artikel für die Praxis.</p><a href='/a'>Router für Glasfaser richtig auswählen</a><a href='/c'>ONT im Haus richtig einordnen</a></section>";
    var method = typeof(OpenAiCorrectionEngine).GetMethod("IsDeterministicCleanup", BindingFlags.NonPublic | BindingFlags.Static);
    Assert(method is not null && (bool)method.Invoke(null, [original, corrected])!, "duplicate link cleanup was treated as factual because its section changed");
});
Test("cleanup cannot remove unique blocks", () =>
{
    var original = "<p>Der Techniker misst den Pegel am ONT.</p><p>Der Techniker misst den Pegel am ONT.</p><p>Der Router bleibt für die Messung angeschlossen.</p>";
    var corrected = "<p>Der Techniker misst den Pegel am ONT.</p>";
    var method = typeof(OpenAiCorrectionEngine).GetMethod("IsDeterministicCleanup", BindingFlags.NonPublic | BindingFlags.Static);
    Assert(method is not null && !(bool)method.Invoke(null, [original, corrected])!, "removal of a unique block was accepted as duplicate cleanup");
});
Test("embedded HTML image is extracted once", () =>
{
    using var doc = JsonDocument.Parse("""{"content":"<img src=\"https:\/\/example.test\/bild.webp\" alt=\"ONT\">","duplicate":"https://example.test/bild.webp"}""");
    var method = typeof(OpenAiCorrectionEngine).GetMethod("ExtractImageUrls", BindingFlags.NonPublic | BindingFlags.Static);
    var urls = ((IEnumerable<string>)method!.Invoke(null, [doc.RootElement])!).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
    Assert(urls.Count == 1 && urls[0] == "https://example.test/bild.webp", "embedded image URL was not extracted and deduplicated");
});
Test("HTML media evidence is not auto-checked", () =>
{
    using var doc = JsonDocument.Parse("""{"content":"<figure class=\"wp-image-55\"><picture><img src=\"https://example.test/bild.webp\" alt=\"ONT im Keller\"></picture><figcaption>Montage</figcaption></figure>"}""");
    var method = typeof(OpenAiCorrectionEngine).GetMethod("HasMediaEvidence", BindingFlags.NonPublic | BindingFlags.Static);
    Assert(method is not null && (bool)method.Invoke(null, [doc.RootElement])!, "HTML media evidence was not detected");
});
Test("real affiliate host is detected without tracking query", () =>
{
    var proposal = new CorrectionProposal(1, "old content long enough", "<p><a href='https://glasfaser-kompass.telekom-profis.de/router' rel='nofollow'>Router bestellen</a></p>", [], ["https://telekom.de/a", "https://bundesnetzagentur.de/b"], true, true, false);
    var result = QualityGate.Check(proposal, cfg);
    Assert(!result.Passed && result.Findings.Any(x => x.Code == "AFFILIATE_REL") && result.Findings.Any(x => x.Code == "AFFILIATE_DISCLOSURE"), "real affiliate host was not detected");
});
Test("non-German finding normalization preserves detail", () =>
{
    var method = typeof(OpenAiCorrectionEngine).GetMethod("EnsureGermanFinding", BindingFlags.NonPublic | BindingFlags.Static);
    var normalized = (string)method!.Invoke(null, ["Duplicate CTA block should be removed near the router offer."])!;
    Assert(normalized.Contains("Duplicate CTA block should be removed near the router offer."), "normalization lost actionable detail");
});
Test("affiliate target validation follows https redirect and preserves tracking", () =>
{
    var calls = new List<Uri>();
    var handler = new FakeHandler(req =>
    {
        calls.Add(req.RequestUri!);
        if (calls.Count == 1)
            return new HttpResponseMessage(HttpStatusCode.Found) { Headers = { Location = new Uri("/final", UriKind.Relative) } };
        return new HttpResponseMessage(HttpStatusCode.OK);
    });
    var affiliateCfg = new WorkerConfig { AffiliateHosts = ["shop.test"], AffiliateMaxRedirects = 3, AffiliateValidationTimeoutSeconds = 5 };
    var findings = AffiliateTargetValidator.Check("<a href='https://shop.test/offer?ref=abc'>Angebot</a>", affiliateCfg, CancellationToken.None, handler).GetAwaiter().GetResult();
    Assert(findings.Count == 0 && calls.Count == 2 && calls[0].Query == "?ref=abc" && calls[1].AbsoluteUri == "https://shop.test/final", "affiliate redirect validation failed or tracking was changed");
});
Test("affiliate target network failure blocks publication", () =>
{
    var handler = new ThrowingHandler();
    var affiliateCfg = new WorkerConfig { AffiliateHosts = ["shop.test"], AffiliateValidationTimeoutSeconds = 5 };
    var findings = AffiliateTargetValidator.Check("<a href='https://shop.test/offer?ref=abc'>Angebot</a>", affiliateCfg, CancellationToken.None, handler).GetAwaiter().GetResult();
    Assert(findings.Any(x => x.Code == "AFFILIATE_TARGET" && x.Severity == "blocker"), "network failure did not block affiliate target");
});
Test("idempotency stable", () => Assert(Hashing.Idempotency(7,"x") == Hashing.Idempotency(7,"x"),"hash differs"));
Test("explicit post bypasses checkpoint", () =>
{
    var state = new Checkpoint { CompletedIds = [75] };
    Assert(ProductionWorker.ShouldProcess(true, state, 75), "explicit post was skipped");
    Assert(!ProductionWorker.ShouldProcess(false, state, 75), "queue checkpoint was ignored");
});
Test("saved correction becomes verified", () =>
{
    var quality = new QualityResult(true, []);
    Assert(ProductionWorker.DetermineResultStatus(quality, true, true) == "verified", "saved correction not verified");
    Assert(ProductionWorker.DetermineResultStatus(quality, true, false) == "needs_correction", "unsaved correction status wrong");
});
Test("web search evidence accepts source objects", () =>
{
    using var doc = JsonDocument.Parse("""{"output":[{"type":"web_search_call","action":{"sources":[{"url":"https://www.telekom.de/hilfe/a"},{"url":"https://bundesnetzagentur.de/b"}]}}]}""");
    var urls = OpenAiEvidenceParser.ExtractCitedUrls(doc.RootElement).ToList();
    Assert(urls.Count == 2 && urls.Any(x=>x.Contains("telekom.de")) && urls.Any(x=>x.Contains("bundesnetzagentur.de")), "source objects missing");
});
Test("model JSON string sources are not evidence", () =>
{
    using var doc = JsonDocument.Parse("""{"output":[{"type":"message","content":[{"type":"output_text","text":"{}"}]}],"sources":["https://invented.example/x"]}""");
    Assert(!OpenAiEvidenceParser.ExtractCitedUrls(doc.RootElement).Any(), "untrusted strings accepted");
});
Test("url citation is evidence", () =>
{
    using var doc = JsonDocument.Parse("""{"annotations":[{"type":"url_citation","url":"https://www.telekom.de/hilfe/a"}]}""");
    Assert(OpenAiEvidenceParser.ExtractCitedUrls(doc.RootElement).Single().Contains("telekom.de"), "citation missing");
});
Test("audit client uses observed routes and parses rich content", () =>
{
    var handler = new FakeHandler(req =>
    {
        var path = req.RequestUri!.PathAndQuery;
        if (path.Contains("/items?"))
        {
            Assert(path.Contains("page=1"), "mutable queue did not restart at page 1");
            return Json("{\"items\":[{\"id\":75,\"title\":\"APL\"}]}");
        }
        if (path.EndsWith("/item/75")) return Json("{\"id\":75,\"title\":{\"rendered\":\"APL\"},\"content\":{\"raw\":\"<p>x</p>\"}}");
        return new HttpResponseMessage(HttpStatusCode.NotFound);
    });
    var logDir = Path.Combine(Path.GetTempPath(), "gk-tests-" + Guid.NewGuid());
    using var client = new GkApiClient(new ApiConfig { BaseUrl="https://example.test/", Token="x", QueuePath="items?page={page}&per_page={limit}", ItemPath="item/{id}", MaxRetries=0, UpdatePaths=["unused"] }, new AuditLog(logDir), handler);
    var items = client.Queue(1,50,CancellationToken.None).GetAwaiter().GetResult();
    var item = client.GetContent(75,CancellationToken.None).GetAwaiter().GetResult();
    Assert(items.Single().Id == 75 && item.Html == "<p>x</p>" && item.Title == "APL", "route or parsing mismatch");
});
Test("unified client read update cache contract", () =>
{
    var calls = new List<string>();
    var handler = new FakeHandler(req =>
    {
        calls.Add(req.RequestUri!.AbsolutePath);
        Assert(req.Headers.Authorization?.Scheme == "Bearer" && req.Headers.Authorization.Parameter == "write-token", "missing unified bearer");
        if (req.RequestUri.AbsolutePath.EndsWith("read-post")) return Json("{\"ok\":true,\"id\":75,\"title\":\"APL\",\"content\":\"<p>x</p>\"}");
        if (req.RequestUri.AbsolutePath.EndsWith("update-post")) return Json("{\"ok\":true,\"id\":75,\"updated\":true}");
        if (req.RequestUri.AbsolutePath.EndsWith("clear-cache")) return Json("{\"ok\":true,\"cache_cleared\":true}");
        return Json("{\"ok\":true}");
    });
    using var client = new UnifiedApiClient(new UnifiedApiConfig { BaseUrl="https://example.test/", Token="write-token" }, handler);
    Assert(client.Read(75,CancellationToken.None).GetAwaiter().GetResult().Html == "<p>x</p>", "read mismatch");
    client.Update(75,"<p>y</p>",CancellationToken.None).GetAwaiter().GetResult();
    client.ClearCache(CancellationToken.None).GetAwaiter().GetResult();
    Assert(calls.Count == 3, "wrong unified call count");
});
return failures == 0 ? 0 : 1;

static HttpResponseMessage Json(string body) => new(HttpStatusCode.OK) { Content = new StringContent(body, Encoding.UTF8, "application/json") };
sealed class ThrowingHandler : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
        throw new HttpRequestException("simulated");
}
sealed class FakeHandler(Func<HttpRequestMessage,HttpResponseMessage> callback) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(callback(request));
}
