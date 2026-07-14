using System.Text.Json;

namespace GkProductionWorker;

public sealed class AppConfig
{
    public ApiConfig Api { get; set; } = new();
    public OpenAiConfig OpenAI { get; set; } = new();
    public UnifiedApiConfig UnifiedApi { get; set; } = new();
    public WorkerConfig Worker { get; set; } = new();

    public static AppConfig Load(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException($"Konfiguration fehlt: {path}");
        var cfg = JsonSerializer.Deserialize<AppConfig>(File.ReadAllText(path), Json.Options)
                  ?? throw new InvalidDataException("Konfiguration ist leer.");
        cfg.Api.Token = Env("GK_API_TOKEN", cfg.Api.Token);
        cfg.Api.BaseUrl = Env("GK_API_BASE_URL", cfg.Api.BaseUrl);
        cfg.OpenAI.ApiKey = Env("OPENAI_API_KEY", cfg.OpenAI.ApiKey);
        cfg.OpenAI.Model = Env("OPENAI_MODEL", cfg.OpenAI.Model);
        cfg.UnifiedApi.Token = Env("GK_UNIFIED_API_TOKEN", cfg.UnifiedApi.Token);
        cfg.Validate();
        return cfg;
    }

    private static string Env(string name, string fallback) =>
        string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)) ? fallback : Environment.GetEnvironmentVariable(name)!;

    private void Validate()
    {
        if (!Uri.TryCreate(Api.BaseUrl, UriKind.Absolute, out _)) throw new InvalidDataException("Api.BaseUrl ist ungültig.");
        if (string.IsNullOrWhiteSpace(Api.Token)) throw new InvalidDataException("GK_API_TOKEN fehlt.");
        if (Worker.BatchSize is < 1 or > 100) throw new InvalidDataException("BatchSize muss zwischen 1 und 100 liegen.");
        if (Api.UpdatePaths.Count == 0) throw new InvalidDataException("Mindestens eine UpdatePath ist erforderlich.");
        if (!Uri.TryCreate(UnifiedApi.BaseUrl, UriKind.Absolute, out _)) throw new InvalidDataException("UnifiedApi.BaseUrl ist ungültig.");
    }
}

public sealed class ApiConfig
{
    public string BaseUrl { get; set; } = "";
    public string Token { get; set; } = "";
    public string StatusPath { get; set; } = "status";
    public string QueuePath { get; set; } = "items?page={page}&per_page={limit}";
    public string ItemPath { get; set; } = "item/{id}";
    public List<string> UpdatePaths { get; set; } = [];
    public string ResultPath { get; set; } = "audit-result";
    public int HttpTimeoutSeconds { get; set; } = 90;
    public int MaxRetries { get; set; } = 4;
}

public sealed class OpenAiConfig
{
    public string ApiKey { get; set; } = "";
    public string Model { get; set; } = "gpt-4.1";
    public string Endpoint { get; set; } = "https://api.openai.com/v1/responses";
    public bool Enabled { get; set; } = true;
    public List<string> OfficialDomains { get; set; } = [];
}

public sealed class UnifiedApiConfig
{
    public string BaseUrl { get; set; } = "https://glasfaser-kompass.de/wp-json/gk-unified-api/v1/";
    public string Token { get; set; } = "";
    public string HealthPath { get; set; } = "health";
    public string ReadPath { get; set; } = "read-post";
    public string UpdatePath { get; set; } = "update-post";
    public string ClearCachePath { get; set; } = "clear-cache";
}

public sealed class WorkerConfig
{
    public int BatchSize { get; set; } = 10;
    public int PollSeconds { get; set; } = 60;
    public int MaxItemsPerRun { get; set; } = 300;
    public List<long> PostIds { get; set; } = [];
    public bool RequireTwoOfficialSources { get; set; } = true;
    public bool CheckImagesAndAiObjects { get; set; } = true;
    public string ReportsDirectory { get; set; } = "reports";
    public string LogsDirectory { get; set; } = "logs";
    public string StateDirectory { get; set; } = "state";
    public string BackupsDirectory { get; set; } = "backups";
    public List<string> AffiliateHosts { get; set; } = ["glasfaser-kompass.telekom-profis.de"];
}

internal static class Json
{
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = true,
        WriteIndented = true
    };
}
