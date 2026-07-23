using System.Text.Json;
using GkProductionWorker;

return await MainAsync(args);

static async Task<int> MainAsync(string[] args)
{
    var command = args.FirstOrDefault(x => !x.StartsWith("--"))?.ToLowerInvariant() ?? "help";
    if (command is "help" or "--help" or "-h") { Usage(); return 0; }
    var configPath = Value(args, "--config") ?? "config.json";
    try
    {
        EnvFile.Load(Path.Combine(Path.GetDirectoryName(Path.GetFullPath(configPath))!, ".env"));
        var cfg = AppConfig.Load(configPath);
        var log = new AuditLog(cfg.Worker.LogsDirectory);
        using var api = new GkApiClient(cfg.Api, log);
        using var unified = new UnifiedApiClient(cfg.UnifiedApi);
        using var stop = new CancellationTokenSource();
        Console.CancelKeyPress += (_, e) => { e.Cancel = true; stop.Cancel(); };
        if (command is "doctor" or "status")
        {
            using var status = await api.Status(stop.Token);
            Console.WriteLine(status.RootElement.GetRawText());
            if (command == "doctor")
            {
                if (string.IsNullOrWhiteSpace(cfg.UnifiedApi.Token)) throw new InvalidOperationException("GK_UNIFIED_API_TOKEN fehlt.");
                using var unifiedHealth = await unified.Health(stop.Token);
                Console.WriteLine(unifiedHealth.RootElement.GetRawText());
                Console.WriteLine("OK: Audit-API, Unified API und Konfiguration funktionieren.");
            }
            return 0;
        }
        var publish = command is "publish" or "watch";
        if (publish && Value(args, "--confirm") != "JA")
            throw new InvalidOperationException("Produktionsmodus abgebrochen. Erforderlich: --confirm JA");
        if (command is not ("preview" or "publish" or "watch")) throw new InvalidOperationException($"Unbekannter Befehl: {command}");
        var ids = Values(args, "--post").Select(long.Parse).ToList();
        var limit = int.TryParse(Value(args, "--limit"), out var n) ? n : (int?)null;
        var worker = new ProductionWorker(cfg, api, unified, new OpenAiCorrectionEngine(cfg.OpenAI, log), log);
        do
        {
            var rows = await worker.Run(publish, limit, ids, stop.Token);
            Console.WriteLine($"Fertig: {rows.Count} geprüft, {rows.Count(x=>x.Changed)} geändert, {rows.Count(x=>x.Saved)} gespeichert, {rows.Count(x=>x.Error is not null)} Fehler.");
            if (command != "watch" || args.Contains("--once") || stop.IsCancellationRequested) break;
            await Task.Delay(TimeSpan.FromSeconds(cfg.Worker.PollSeconds), stop.Token);
        } while (!stop.IsCancellationRequested);
        return 0;
    }
    catch (OperationCanceledException) { return 0; }
    catch (Exception ex) { Console.Error.WriteLine("FEHLER: " + ex.Message); return 1; }
}

static string? Value(string[] args, string key)
{ for (var i=0; i<args.Length-1; i++) if (args[i] == key) return args[i+1]; return null; }
static IEnumerable<string> Values(string[] args, string key)
{ for (var i=0; i<args.Length-1; i++) if (args[i] == key) yield return args[i+1]; }
static void Usage() => Console.WriteLine("GK Production Worker 5.1\n  doctor|status|preview|publish|watch [--config PATH] [--limit N] [--post ID] [--confirm JA] [--once]");

static class EnvFile
{
    public static void Load(string path)
    {
        if (!File.Exists(path)) return;
        foreach (var raw in File.ReadLines(path))
        {
            var line = raw.Trim();
            if (line.Length == 0 || line.StartsWith('#')) continue;
            var split = line.IndexOf('=');
            if (split < 1) continue;
            var key = line[..split].Trim();
            var value = line[(split + 1)..].Trim().Trim('"', '\'');
            if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(key))) Environment.SetEnvironmentVariable(key, value);
        }
        Alias("GK_SITE_AUDIT_TOKEN", "GK_API_TOKEN");
        Alias("OPENAI_API_KEY", "OPENAI_API_KEY");
        var site = Environment.GetEnvironmentVariable("GK_SITE_URL")?.TrimEnd('/');
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GK_API_BASE_URL")) && !string.IsNullOrEmpty(site))
            Environment.SetEnvironmentVariable("GK_API_BASE_URL", site + "/wp-json/gk-site-audit/v1/");
    }
    private static void Alias(string source, string target)
    {
        if (string.IsNullOrEmpty(Environment.GetEnvironmentVariable(target)))
            Environment.SetEnvironmentVariable(target, Environment.GetEnvironmentVariable(source));
    }
}
