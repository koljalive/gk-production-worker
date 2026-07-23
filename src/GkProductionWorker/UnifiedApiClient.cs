using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;

namespace GkProductionWorker;

public sealed class UnifiedApiClient : IDisposable
{
    private readonly UnifiedApiConfig _cfg;
    private readonly HttpClient _http;
    public UnifiedApiClient(UnifiedApiConfig cfg, HttpMessageHandler? handler = null)
    {
        _cfg = cfg;
        _http = handler is null ? new HttpClient() : new HttpClient(handler);
        _http.BaseAddress = new Uri(cfg.BaseUrl.EndsWith('/') ? cfg.BaseUrl : cfg.BaseUrl + "/");
        _http.Timeout = TimeSpan.FromSeconds(90);
        if (!string.IsNullOrWhiteSpace(cfg.Token)) _http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", cfg.Token);
        _http.DefaultRequestHeaders.UserAgent.ParseAdd("GK-Production-Worker/5.1");
    }
    public async Task<JsonDocument> Health(CancellationToken ct) => await Send(HttpMethod.Get, _cfg.HealthPath, null, ct);
    public async Task<ContentItem> Read(long id, CancellationToken ct)
    {
        using var doc = await Send(HttpMethod.Post, _cfg.ReadPath, JsonSerializer.Serialize(new { id }), ct);
        var r = doc.RootElement;
        return new(id, Get(r,"title") ?? $"Beitrag {id}", Get(r,"content") ?? "", null, r.Clone());
    }
    public async Task Update(long id, string content, CancellationToken ct)
    {
        using var doc = await Send(HttpMethod.Post, _cfg.UpdatePath, JsonSerializer.Serialize(new { id, content }), ct);
        if (!doc.RootElement.TryGetProperty("updated", out var u) || u.ValueKind != JsonValueKind.True)
            throw new InvalidOperationException("Unified API bestätigte die Aktualisierung nicht.");
    }
    public async Task ClearCache(CancellationToken ct)
    {
        using var doc = await Send(HttpMethod.Post, _cfg.ClearCachePath, "{}", ct);
        if (!doc.RootElement.TryGetProperty("cache_cleared", out var c) || c.ValueKind != JsonValueKind.True)
            throw new InvalidOperationException("Cache-Leerung wurde nicht bestätigt.");
    }
    private async Task<JsonDocument> Send(HttpMethod method, string path, string? json, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(method, path);
        if (json is not null) req.Content = new StringContent(json, Encoding.UTF8, "application/json");
        using var res = await _http.SendAsync(req, ct);
        var body = await res.Content.ReadAsStringAsync(ct);
        if (!res.IsSuccessStatusCode) throw new InvalidOperationException($"Unified API HTTP {(int)res.StatusCode}: {body[..Math.Min(500,body.Length)]}");
        return JsonDocument.Parse(string.IsNullOrWhiteSpace(body) ? "{}" : body);
    }
    private static string? Get(JsonElement e, string name) => e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    public void Dispose() => _http.Dispose();
}
