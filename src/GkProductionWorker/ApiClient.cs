using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace GkProductionWorker;

public sealed class GkApiClient : IDisposable
{
    private readonly ApiConfig _cfg;
    private readonly HttpClient _http;
    private readonly AuditLog _log;

    public GkApiClient(ApiConfig cfg, AuditLog log, HttpMessageHandler? handler = null)
    {
        _cfg = cfg;
        _log = log;
        _http = handler is null ? new HttpClient() : new HttpClient(handler);
        _http.BaseAddress = new Uri(cfg.BaseUrl.EndsWith('/') ? cfg.BaseUrl : cfg.BaseUrl + "/");
        _http.Timeout = TimeSpan.FromSeconds(cfg.HttpTimeoutSeconds);
        _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", cfg.Token);
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("GK-Production-Worker/5.0");
    }

    public Task<JsonDocument> Status(CancellationToken ct) => SendJson(HttpMethod.Get, _cfg.StatusPath, null, null, ct);

    public async Task<IReadOnlyList<QueueItem>> Queue(int limit, int offset, CancellationToken ct)
    {
        // The pending queue shrinks as results are saved. Always consume its current first page;
        // advancing pages at the same time would skip items that shift forward.
        var page = 1;
        var path = Expand(_cfg.QueuePath, 0, limit, 0, page);
        using var doc = await SendJson(HttpMethod.Get, path, null, null, ct);
        var root = doc.RootElement;
        var array = root.ValueKind == JsonValueKind.Array ? root :
            FirstArray(root, "items", "queue", "data", "results");
        if (array.ValueKind != JsonValueKind.Array) return [];
        return array.EnumerateArray().Select(x => new QueueItem(
            ReadLong(x, "id", "post_id", "content_id"),
            ReadString(x, "title", "post_title"),
            ReadString(x, "status", "audit_status"))).Where(x => x.Id > 0).ToList();
    }

    public async Task<ContentItem> GetContent(long id, CancellationToken ct)
    {
        using var doc = await SendJson(HttpMethod.Get, Expand(_cfg.ItemPath, id, 0, 0, 1), null, null, ct);
        var root = doc.RootElement.Clone();
        if (root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Object) root = data.Clone();
        var html = ReadRichString(root, "content_html", "post_content", "html", "content") ?? "";
        return new ContentItem(id, ReadRichString(root, "title", "post_title") ?? $"Beitrag {id}", html,
            ReadString(root, "excerpt", "post_excerpt"), root);
    }

    public async Task<string> Update(long id, string html, string idempotencyKey, CancellationToken ct)
    {
        var body = JsonSerializer.Serialize(new { id, content = html, html, post_content = html }, Json.Options);
        var errors = new List<string>();
        foreach (var template in _cfg.UpdatePaths)
        {
            try
            {
                using var doc = await SendJson(HttpMethod.Post, Expand(template, id, 0, 0, 1), body, idempotencyKey, ct);
                return doc.RootElement.GetRawText();
            }
            catch (ApiException ex) when (ex.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed)
            {
                errors.Add($"{template}: {(int)ex.StatusCode}");
            }
        }
        throw new InvalidOperationException("Keine konfigurierte Schreibroute wurde akzeptiert: " + string.Join(", ", errors));
    }

    public async Task SaveResult(long id, string status, string summary, IReadOnlyList<Finding> findings, IReadOnlyList<string> sources, string idempotencyKey, CancellationToken ct)
    {
        var claims = findings.Select((f, index) => new
        {
            claim_id = $"finding-{index + 1}", original = "", verdict = f.Code == "INSUFFICIENT_SOURCES" ? "insufficient_sources" : "unclear",
            severity = f.Severity.Equals("blocker", StringComparison.OrdinalIgnoreCase) ? "high" : "low",
            reason = f.Message, suggested_fix = "", sources = sources.Select(url => new { url }).ToArray()
        }).ToArray();
        var body = JsonSerializer.Serialize(new
        {
            item_id = id, status, summary, claims,
            media_findings = Array.Empty<object>(), object_findings = Array.Empty<object>(),
            html_findings = Array.Empty<object>(), recommended_actions = Array.Empty<object>()
        }, Json.Options);
        await SendJson(HttpMethod.Post, Expand(_cfg.ResultPath, id, 0, 0, 1), body, idempotencyKey, ct);
    }

    private async Task<JsonDocument> SendJson(HttpMethod method, string path, string? body, string? idem, CancellationToken ct)
    {
        Exception? last = null;
        for (var attempt = 0; attempt <= _cfg.MaxRetries; attempt++)
        {
            using var req = new HttpRequestMessage(method, path);
            if (body is not null) req.Content = new StringContent(body, Encoding.UTF8, "application/json");
            if (idem is not null) req.Headers.TryAddWithoutValidation("Idempotency-Key", idem);
            try
            {
                using var response = await _http.SendAsync(req, ct);
                var text = await response.Content.ReadAsStringAsync(ct);
                await _log.Write("http", new { method = method.Method, path, status = (int)response.StatusCode, attempt });
                if (response.IsSuccessStatusCode)
                    return JsonDocument.Parse(string.IsNullOrWhiteSpace(text) ? "{}" : text);
                if ((int)response.StatusCode < 500 && response.StatusCode != HttpStatusCode.TooManyRequests)
                    throw new ApiException(response.StatusCode, Safe(text));
                last = new ApiException(response.StatusCode, Safe(text));
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                last = ex;
            }
            if (attempt < _cfg.MaxRetries)
                await Task.Delay(TimeSpan.FromMilliseconds(Math.Min(30000, 500 * Math.Pow(2, attempt)) + Random.Shared.Next(250)), ct);
        }
        throw last ?? new HttpRequestException("API-Aufruf fehlgeschlagen.");
    }

    private static string Expand(string s, long id, int limit, int offset, int page) => s
        .Replace("{id}", id.ToString()).Replace("{limit}", limit.ToString()).Replace("{per_page}", limit.ToString())
        .Replace("{offset}", offset.ToString()).Replace("{page}", page.ToString());
    private static JsonElement FirstArray(JsonElement e, params string[] names)
    { foreach (var n in names) if (e.TryGetProperty(n, out var v) && v.ValueKind == JsonValueKind.Array) return v; return default; }
    private static string? ReadString(JsonElement e, params string[] names)
    { foreach (var n in names) if (e.TryGetProperty(n, out var v)) return v.ValueKind == JsonValueKind.String ? v.GetString() : v.ToString(); return null; }
    private static string? ReadRichString(JsonElement e, params string[] names)
    {
        foreach (var n in names)
        {
            if (!e.TryGetProperty(n, out var v)) continue;
            if (v.ValueKind == JsonValueKind.String) return v.GetString();
            if (v.ValueKind == JsonValueKind.Object)
                foreach (var child in new[] { "raw", "rendered", "html", "value" })
                    if (v.TryGetProperty(child, out var nested) && nested.ValueKind == JsonValueKind.String) return nested.GetString();
        }
        return null;
    }
    private static long ReadLong(JsonElement e, params string[] names)
    { foreach (var n in names) if (e.TryGetProperty(n, out var v) && (v.TryGetInt64(out var x) || long.TryParse(v.ToString(), out x))) return x; return 0; }
    private static string Safe(string value) => value.Length <= 1000 ? value : value[..1000];
    public void Dispose() => _http.Dispose();
}

public sealed class ApiException(HttpStatusCode statusCode, string message) : Exception(message)
{
    public HttpStatusCode StatusCode { get; } = statusCode;
}
