using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace GkProductionWorker;

public interface ICorrectionEngine
{
    Task<CorrectionProposal> Propose(ContentItem item, CancellationToken ct);
}

public sealed class OpenAiCorrectionEngine(OpenAiConfig cfg, AuditLog log) : ICorrectionEngine
{
    public async Task<CorrectionProposal> Propose(ContentItem item, CancellationToken ct)
    {
        if (!cfg.Enabled || string.IsNullOrWhiteSpace(cfg.ApiKey))
            return new(item.Id, item.Html, item.Html,
                [new("AI_DISABLED", "info", "OpenAI ist deaktiviert; Inhalt wurde nur technisch geprüft.")], [], true, true, false);

        var instruction = """
Du bist die fachliche Qualitätssicherung für glasfaser-kompass.de. Prüfe und korrigiere ausschließlich nachweisbare Fehler.
Erhalte Struktur, Shortcodes, Affiliate-Links und nicht betroffene Inhalte. Entferne keine Aussagen ohne Grund.
Wenn keine fachliche oder redaktionelle Korrektur erforderlich ist, gib corrected_html bytegenau unverändert zurück.
Prüfe ausdrücklich doppelte Abschnitte, Template-Reste, fehlerhaftes HTML, Themenvermischung sowie widersprüchliche Passagen.
Jede fachliche Kernaussage benötigt mindestens zwei offizielle, voneinander unabhängige Quellen (Behörden,
Netzbetreiber oder Hersteller). Prüfe Bilder, Alt-Texte, Bildunterschriften und erkennbare KI-Objekte.
Wenn Bilddateien beigefügt sind, analysiere sie visuell. Wenn keine Bilder beigefügt sind, prüfe die Medienmetadaten
und setze images_checked/ai_objects_checked nur dann auf true, wenn das Fehlen beziehungsweise die Metadaten sicher geprüft wurden.
Unterscheide Änderungstypen: factual für geänderte Tatsachenbehauptungen, editorial für KI-freie redaktionelle Bereinigung, html_cleanup für reine HTML-/Strukturkorrekturen.
KI-frei bedeutet: keine Doppelungen, Widersprüche, unlogischen Sequenzen, vermischten Technologien, unbelegten Absolutaussagen, SEO-Fülltexte, Template-Reste, Keyword-Stuffing oder Sprachmischungen; die Stimme bleibt sachlich wie ein Feldtechniker aus praktischer Arbeit, ohne erfundene Ich-Erlebnisse.
Affiliate-Regeln: nur kontextrelevante wahrheitsgemäße Links, HTTPS, Tracking erhalten, rel="sponsored nofollow", klare Werbe-/Provisionskennzeichnung, keine aggressiven doppelten CTA-Blöcke.
Antworte ausschließlich als JSON mit: requires_change (bool), corrected_html (string), change_type (factual|editorial|html_cleanup|none), findings [{code,severity,message}],
sources (Array vollständiger URLs), images_checked (bool), ai_objects_checked (bool). Alle findings müssen deutsch sein.
""";
        var userContent = new List<object>
        {
            new { type = "input_text", text = $"ID: {item.Id}\nTitel: {item.Title}\nHTML:\n{item.Html}\n\nVollständiges Audit-Payload mit Medienmetadaten:\n{item.Raw.GetRawText()}" }
        };
        foreach (var imageUrl in ExtractImageUrls(item.Raw).Distinct(StringComparer.OrdinalIgnoreCase).Take(10))
            userContent.Add(new { type = "input_image", image_url = imageUrl, detail = "high" });
        var payload = JsonSerializer.Serialize(new
        {
            model = cfg.Model,
            tools = new[] { new { type = "web_search", search_context_size = "high", filters = new { allowed_domains = cfg.OfficialDomains } } },
            tool_choice = "auto",
            include = new[] { "web_search_call.action.sources" },
            input = new object[] { new { role = "system", content = instruction }, new { role = "user", content = userContent } }
        }, Json.Options);
        using var http = new HttpClient { Timeout = TimeSpan.FromMinutes(4) };
        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", cfg.ApiKey);
        using var response = await http.PostAsync(cfg.Endpoint, new StringContent(payload, Encoding.UTF8, "application/json"), ct);
        var responseText = await response.Content.ReadAsStringAsync(ct);
        if (!response.IsSuccessStatusCode) throw new InvalidOperationException($"OpenAI HTTP {(int)response.StatusCode}: {responseText[..Math.Min(500, responseText.Length)]}");
        using var outer = JsonDocument.Parse(responseText);
        var json = ExtractOutputText(outer.RootElement);
        using var result = JsonDocument.Parse(NormalizeJson(json));
        var r = result.RootElement;
        var requiresChange = r.TryGetProperty("requires_change", out var rc) && rc.ValueKind == JsonValueKind.True;
        var correctedCandidate = r.TryGetProperty("corrected_html", out var ch) ? ch.GetString() ?? item.Html : item.Html;
        var contradictoryChange = !requiresChange && !string.Equals(correctedCandidate, item.Html, StringComparison.Ordinal);
        var corrected = (requiresChange || contradictoryChange) ? correctedCandidate : item.Html;
        var findings = new List<Finding>();
        if (contradictoryChange)
            findings.Add(new("CONTRADICTORY_PROPOSAL", "blocker", "Die KI-Antwort ist widersprüchlich: corrected_html wurde trotz requires_change=false geändert. Die Korrektur darf erst nach einem konsistenten erneuten Vorschlag veröffentlicht werden."));
        if (r.TryGetProperty("findings", out var fa) && fa.ValueKind == JsonValueKind.Array)
            foreach (var f in fa.EnumerateArray()) findings.Add(new(
                f.TryGetProperty("code", out var c) ? c.GetString() ?? "AI" : "AI",
                f.TryGetProperty("severity", out var s) ? s.GetString() ?? "warning" : "warning",
                f.TryGetProperty("message", out var m) ? EnsureGermanFinding(m.GetString() ?? "") : ""));
        var sources = OpenAiEvidenceParser.ExtractCitedUrls(outer.RootElement)
            .Where(IsAllowedOfficialDomain)
            .Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        bool Flag(string name) => r.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.True;
        var requiresFactualSources = corrected != item.Html && !IsDeterministicCleanup(item.Html, corrected);
        var hasMedia = HasMediaEvidence(item.Raw);
        var imagesChecked = Flag("images_checked") || !hasMedia;
        var aiObjectsChecked = Flag("ai_objects_checked") || !hasMedia;
        await log.Write("proposal", new { item.Id, changed = corrected != item.Html, factual = requiresFactualSources, findings = findings.Count, sources = sources.Count });
        return new(item.Id, item.Html, corrected, findings, sources, imagesChecked, aiObjectsChecked, requiresFactualSources);

        bool IsAllowedOfficialDomain(string url)
        {
            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri)) return false;
            return cfg.OfficialDomains.Any(d => uri.Host.Equals(d, StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith("." + d, StringComparison.OrdinalIgnoreCase));
        }
    }

    private static string ExtractOutputText(JsonElement root)
    {
        if (root.TryGetProperty("output_text", out var direct) && direct.ValueKind == JsonValueKind.String) return direct.GetString()!;
        if (root.TryGetProperty("output", out var output))
            foreach (var o in output.EnumerateArray())
                if (o.TryGetProperty("content", out var content))
                    foreach (var c in content.EnumerateArray())
                        if (c.TryGetProperty("text", out var text)) return text.GetString() ?? "{}";
        throw new InvalidDataException("OpenAI-Antwort enthält kein output_text.");
    }

    private static string EnsureGermanFinding(string message)
    {
        if (Regex.IsMatch(message, @"\b(the|and|should|must|duplicate|source|content|change)\b", RegexOptions.IgnoreCase))
            return $"Prüfhinweis wurde auf Deutsch normiert; ursprünglicher Hinweis: {message}";
        return message;
    }

    private static string NormalizeJson(string text)
    {
        var value = text.Trim();
        if (value.StartsWith("```"))
        {
            var firstNewline = value.IndexOf('\n');
            var lastFence = value.LastIndexOf("```", StringComparison.Ordinal);
            if (firstNewline >= 0 && lastFence > firstNewline) value = value[(firstNewline + 1)..lastFence].Trim();
        }
        return value;
    }

    private static IEnumerable<string> ExtractImageUrls(JsonElement e)
    {
        if (e.ValueKind == JsonValueKind.String)
        {
            var value = (e.GetString() ?? "").Replace(@"\/", "/", StringComparison.Ordinal);
            foreach (Match match in Regex.Matches(value, @"https?://[^\s""'<>\\]+?\.(?:jpe?g|png|webp|gif|avif)(?:\?[^\s""'<>\\]*)?", RegexOptions.IgnoreCase))
                if (Uri.TryCreate(System.Net.WebUtility.HtmlDecode(match.Value), UriKind.Absolute, out var uri))
                    yield return uri.ToString();
            yield break;
        }
        if (e.ValueKind == JsonValueKind.Object)
            foreach (var p in e.EnumerateObject())
                foreach (var url in ExtractImageUrls(p.Value)) yield return url;
        else if (e.ValueKind == JsonValueKind.Array)
            foreach (var child in e.EnumerateArray())
                foreach (var url in ExtractImageUrls(child)) yield return url;
    }

    private static bool HasMediaEvidence(JsonElement e)
    {
        if (ExtractImageUrls(e).Any()) return true;
        var raw = e.GetRawText();
        return Regex.IsMatch(raw, @"<\s*(img|picture|figure)\b|wp-image-\d+|\b(alt|caption|image|thumbnail|featured_media)\b|https?:\\?/\\?/[^""'\s<>\\]+\.(jpe?g|png|webp|gif|avif)", RegexOptions.IgnoreCase);
    }

    private static bool IsDeterministicCleanup(string original, string corrected)
    {
        if (string.Equals(original, corrected, StringComparison.Ordinal)) return false;
        var originalText = VisibleText(original);
        var correctedText = VisibleText(corrected);
        if (string.Equals(originalText, correctedText, StringComparison.OrdinalIgnoreCase)) return true;

        var originalBlocks = TextBlocks(original);
        var correctedBlocks = TextBlocks(corrected);
        if (originalBlocks.Count <= correctedBlocks.Count) return false;
        var originalCounts = originalBlocks.GroupBy(x => x).ToDictionary(g => g.Key, g => g.Count());
        var correctedCounts = correctedBlocks.GroupBy(x => x).ToDictionary(g => g.Key, g => g.Count());
        if (!originalCounts.Values.Any(count => count > 1)) return false;
        return originalCounts.All(entry =>
            correctedCounts.TryGetValue(entry.Key, out var count)
            && count >= 1
            && count <= entry.Value)
            && correctedCounts.All(entry => originalCounts.ContainsKey(entry.Key));
    }

    private static string VisibleText(string html) =>
        Regex.Replace(System.Net.WebUtility.HtmlDecode(Regex.Replace(html, "<.*?>", " ")), @"\s+", " ").Trim();

    private static List<string> TextBlocks(string html) =>
        Regex.Matches(html, @"<(h[1-6]|p|a|section)\b[^>]*>(.*?)</\1>", RegexOptions.IgnoreCase | RegexOptions.Singleline)
            .Select(m => VisibleText(m.Groups[2].Value).ToLowerInvariant())
            .Where(t => t.Length >= 12)
            .ToList();
}

public static class OpenAiEvidenceParser
{
    public static IEnumerable<string> ExtractCitedUrls(JsonElement e, bool trustedSourceArea = false)
    {
        if (e.ValueKind == JsonValueKind.Object)
        {
            var isCitation = e.TryGetProperty("type", out var type) && type.ValueKind == JsonValueKind.String && type.GetString() == "url_citation";
            var isWebCall = e.TryGetProperty("type", out var callType) && callType.ValueKind == JsonValueKind.String && callType.GetString() == "web_search_call";
            foreach (var p in e.EnumerateObject())
            {
                if ((trustedSourceArea || isCitation) && p.NameEquals("url") && p.Value.ValueKind == JsonValueKind.String && Uri.TryCreate(p.Value.GetString(), UriKind.Absolute, out _))
                    yield return p.Value.GetString()!;
                foreach (var url in ExtractCitedUrls(p.Value, trustedSourceArea || (isWebCall && p.NameEquals("action")))) yield return url;
            }
        }
        else if (e.ValueKind == JsonValueKind.Array)
            foreach (var child in e.EnumerateArray()) foreach (var url in ExtractCitedUrls(child, trustedSourceArea)) yield return url;
    }
}

public static class QualityGate
{
    private static readonly Regex Dangerous = new(@"<(script|iframe)\b|\bon\w+\s*=|javascript:", RegexOptions.IgnoreCase | RegexOptions.Compiled);
    public static QualityResult Check(CorrectionProposal p, WorkerConfig cfg)
    {
        var f = new List<Finding>(p.Findings);
        if (string.IsNullOrWhiteSpace(p.CorrectedHtml)) f.Add(new("EMPTY_CONTENT", "blocker", "Der korrigierte Inhalt ist leer."));
        if (Dangerous.IsMatch(p.CorrectedHtml) && !Dangerous.IsMatch(p.OriginalHtml)) f.Add(new("UNSAFE_HTML", "blocker", "Neuer aktiver HTML-Inhalt erkannt."));
        if (p.Changed && p.OriginalHtml.Length >= 200 && p.CorrectedHtml.Length < Math.Max(100, p.OriginalHtml.Length / 2)) f.Add(new("CONTENT_LOSS", "blocker", "Mehr als die Hälfte des Inhalts würde verloren gehen."));
        f.AddRange(DeterministicEditorialChecks(p.CorrectedHtml));
        f.AddRange(DeterministicAffiliateChecks(p.CorrectedHtml, cfg));
        if (cfg.RequireTwoOfficialSources && p.Changed && p.RequiresFactualSources && p.Sources.DistinctBy(SourceHost).Count() < 2)
            f.Add(new("INSUFFICIENT_SOURCES", "blocker", "Weniger als zwei unabhängige offizielle Quellen für die geänderte Tatsachenbehauptung."));
        if (cfg.CheckImagesAndAiObjects && (!p.ImagesChecked || !p.AiObjectsChecked))
            f.Add(new("MEDIA_NOT_CHECKED", "blocker", "Bilder oder KI-Objekte wurden nicht vollständig geprüft."));
        return new(!f.Any(x => x.Severity.Equals("blocker", StringComparison.OrdinalIgnoreCase)), f);
    }
    private static IEnumerable<Finding> DeterministicEditorialChecks(string html)
    {
        foreach (var finding in DuplicateBlockChecks(html)) yield return finding;
        if (Regex.IsMatch(html, @"\b(ultimativ|revolutionär|garantiert|immer|niemals|100\s*%)\b", RegexOptions.IgnoreCase))
            yield return new("UNSUPPORTED_ABSOLUTE", "blocker", "Der Inhalt enthält eine absolute oder werbliche Aussage, die ohne belastbaren Nachweis nicht stehen bleiben darf.");
        if (Regex.IsMatch(html, @"\b(furthermore|overall|in conclusion|click here|best practice)\b", RegexOptions.IgnoreCase))
            yield return new("LANGUAGE_MIX", "blocker", "Der Inhalt enthält englische oder generische Formulierungen statt sauberer deutscher Fachsprache.");
        if (Regex.IsMatch(html, @"(Lorem ipsum|Platzhalter|TODO|Template|hier einfügen|keyword)", RegexOptions.IgnoreCase))
            yield return new("TEMPLATE_RESIDUE", "blocker", "Der Inhalt enthält Template-Reste, Platzhalter oder Keyword-Fülltext.");
    }

    private static IEnumerable<Finding> DuplicateBlockChecks(string html)
    {
        var blocks = Regex.Matches(html, @"<(h[1-6]|p|a|section)\b[^>]*>(.*?)</\1>", RegexOptions.IgnoreCase | RegexOptions.Singleline)
            .Select(m => Regex.Replace(System.Net.WebUtility.HtmlDecode(Regex.Replace(m.Groups[2].Value, "<.*?>", " ")), @"\s+", " ").Trim().ToLowerInvariant())
            .Where(t => t.Length >= 12)
            .ToList();
        foreach (var _ in blocks.GroupBy(x => x).Where(g => g.Count() > 1).Take(3))
            yield return new("DUPLICATE_CONTENT", "blocker", "Der Inhalt enthält doppelte Überschriften, Absätze, CTAs oder Linkblöcke.");
    }

    private static IEnumerable<Finding> DeterministicAffiliateChecks(string html, WorkerConfig cfg)
    {
        var hasDisclosure = Regex.IsMatch(html, @"(Anzeige|Werbung|Provision|Affiliate|Partnerlink|sponsored)", RegexOptions.IgnoreCase);
        foreach (Match m in Regex.Matches(html, @"<a\b(?<attrs>[^>]*)>(?<text>.*?)</a>", RegexOptions.IgnoreCase | RegexOptions.Singleline))
        {
            var attrs = m.Groups["attrs"].Value;
            var href = Regex.Match(attrs, """href\s*=\s*['"](?<url>[^'"]+)['"]""", RegexOptions.IgnoreCase).Groups["url"].Value;
            if (!IsAffiliateUrl(href, cfg)) continue;
            if (!Uri.TryCreate(href, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps)
                yield return new("AFFILIATE_HTTPS", "blocker", "Affiliate-Links müssen absolute HTTPS-Ziele verwenden.");
            var rel = Regex.Match(attrs, """rel\s*=\s*['"](?<rel>[^'"]*)['"]""", RegexOptions.IgnoreCase).Groups["rel"].Value;
            if (!Regex.IsMatch(rel, @"\bsponsored\b", RegexOptions.IgnoreCase) || !Regex.IsMatch(rel, @"\bnofollow\b", RegexOptions.IgnoreCase))
                yield return new("AFFILIATE_REL", "blocker", "Affiliate-Links benötigen rel=\"sponsored nofollow\".");
            if (!hasDisclosure) yield return new("AFFILIATE_DISCLOSURE", "blocker", "Für Affiliate-Links fehlt eine klare Werbe- oder Provisionskennzeichnung.");
        }
        var ctas = Regex.Matches(html, @"(jetzt\s+(kaufen|bestellen|prüfen)|zum\s+angebot|angebot\s+sichern)", RegexOptions.IgnoreCase).Count;
        if (ctas > 2) yield return new("AGGRESSIVE_CTA", "blocker", "Der Inhalt enthält zu viele oder doppelte werbliche CTA-Blöcke.");
    }

    private static bool IsAffiliateUrl(string href, WorkerConfig cfg)
    {
        if (Regex.IsMatch(href ?? "", @"(affiliate|partner|ref=|utm_|tag=|affid=|tracking|awin|belboon)", RegexOptions.IgnoreCase)) return true;
        if (!Uri.TryCreate(href, UriKind.Absolute, out var uri)) return false;
        return cfg.AffiliateHosts.Any(host => uri.Host.Equals(host, StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith("." + host, StringComparison.OrdinalIgnoreCase));
    }
    private static string SourceHost(string url) => Uri.TryCreate(url, UriKind.Absolute, out var uri) ? uri.Host.Replace("www.", "") : url;
}

public sealed class StateStore(string directory)
{
    private string PathName => Path.Combine(directory, "checkpoint.json");
    public Checkpoint Load()
    {
        if (!File.Exists(PathName)) return new();
        try { return JsonSerializer.Deserialize<Checkpoint>(File.ReadAllText(PathName), Json.Options) ?? new(); }
        catch { return new(); }
    }
    public void Save(Checkpoint state)
    {
        Directory.CreateDirectory(directory); state.UpdatedAt = DateTimeOffset.UtcNow;
        var tmp = PathName + ".tmp"; File.WriteAllText(tmp, JsonSerializer.Serialize(state, Json.Options)); File.Move(tmp, PathName, true);
    }
}

public sealed class AuditLog(string directory)
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private static readonly JsonSerializerOptions CompactJson = new(Json.Options) { WriteIndented = false };
    public async Task Write(string type, object data)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, $"worker-{DateTime.UtcNow:yyyyMMdd}.jsonl");
        var line = JsonSerializer.Serialize(new { time = DateTimeOffset.UtcNow, type, data }, CompactJson);
        await _gate.WaitAsync(); try { await File.AppendAllTextAsync(path, line + Environment.NewLine); } finally { _gate.Release(); }
    }
}

public static class ReportWriter
{
    public static string Write(string directory, string mode, IReadOnlyList<RunRow> rows)
    {
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, $"{mode}-{DateTime.Now:yyyyMMdd-HHmmss}.html");
        static string H(string? s) => System.Net.WebUtility.HtmlEncode(s ?? "");
        var table = string.Join("", rows.Select(r => $"<section><h2>{r.Id} – {H(r.Title)}</h2><p>Changed: {r.Changed} | Saved: {r.Saved} | Backup: {H(r.BackupPath)}</p><h3>Prüfung</h3><ul>{string.Join("",r.Findings.Select(f=>$"<li><strong>{H(f.Code)}</strong>: {H(f.Message)}</li>"))}</ul><h3>Quellen</h3><ul>{string.Join("",r.Sources.Select(s=>$"<li><a href='{H(s)}'>{H(s)}</a></li>"))}</ul><details><summary>Original</summary><pre>{H(r.OriginalHtml)}</pre></details><details><summary>Korrektur</summary><pre>{H(r.CorrectedHtml)}</pre></details>{(r.Error is null?"":$"<p class='error'>{H(r.Error)}</p>")}</section>"));
        var html = $"<!doctype html><html lang='de'><meta charset='utf-8'><title>GK Worker {H(mode)}</title><style>body{{font-family:Arial;margin:24px;line-height:1.45}}section{{border:1px solid #ccc;padding:16px;margin:20px 0}}pre{{white-space:pre-wrap;overflow-wrap:anywhere;background:#f6f6f6;padding:12px}}.error{{color:#b00020}}</style><h1>GK Production Worker – {H(mode)}</h1><p>Scanned: {rows.Count} | Changed: {rows.Count(x=>x.Changed)} | Saved: {rows.Count(x=>x.Saved)} | Errors: {rows.Count(x=>x.Error is not null)}</p>{table}</html>";
        File.WriteAllText(path, html); return path;
    }
}

public static class Hashing
{
    public static string Idempotency(long id, string html) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes($"{id}\n{html}"))).ToLowerInvariant();
}
