using System.Text.Json;
using System.Text.Json.Serialization;

namespace GkProductionWorker;

public sealed record QueueItem(
    [property: JsonPropertyName("id")] long Id,
    [property: JsonPropertyName("title")] string? Title,
    [property: JsonPropertyName("status")] string? Status);

public sealed record ContentItem(long Id, string Title, string Html, string? Excerpt, JsonElement Raw);

public sealed record Finding(string Code, string Severity, string Message);

public sealed record CorrectionProposal(
    long Id,
    string OriginalHtml,
    string CorrectedHtml,
    IReadOnlyList<Finding> Findings,
    IReadOnlyList<string> Sources,
    bool ImagesChecked,
    bool AiObjectsChecked,
    bool RequiresFactualSources)
{
    public bool Changed => !string.Equals(OriginalHtml, CorrectedHtml, StringComparison.Ordinal);
}

public sealed record AffiliateLink(string Url, string Rel, string Text);

public sealed record QualityResult(bool Passed, IReadOnlyList<Finding> Findings);

public sealed class Checkpoint
{
    public int Offset { get; set; }
    public HashSet<long> CompletedIds { get; set; } = [];
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}

public sealed record RunRow(long Id, string Title, bool Changed, bool Saved, IReadOnlyList<Finding> Findings,
    IReadOnlyList<string> Sources, string OriginalHtml, string CorrectedHtml, string? BackupPath, string? Error);
