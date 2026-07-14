namespace GkProductionWorker;

public sealed class ProductionWorker(AppConfig cfg, GkApiClient api, UnifiedApiClient unified, ICorrectionEngine engine, AuditLog log)
{
    public async Task<IReadOnlyList<RunRow>> Run(bool publish, int? limit, IReadOnlyList<long> selectedIds, CancellationToken ct)
    {
        // Preview and production deliberately use separate checkpoints. A preview
        // must never make a later production run believe an item was published.
        var store = new StateStore(Path.Combine(cfg.Worker.StateDirectory, publish ? "production" : "preview"));
        var state = store.Load();
        var rows = new List<RunRow>();
        var max = Math.Min(limit ?? cfg.Worker.MaxItemsPerRun, cfg.Worker.MaxItemsPerRun);
        var explicitIds = selectedIds.Count > 0 ? selectedIds : cfg.Worker.PostIds;
        IReadOnlyList<QueueItem> items = explicitIds.Count > 0
            ? explicitIds.Select(id => new QueueItem(id, null, null)).ToList()
            : await api.Queue(Math.Min(max, cfg.Worker.BatchSize), state.Offset, ct);

        foreach (var q in items.Where(x => !state.CompletedIds.Contains(x.Id)).Take(max))
        {
            try
            {
                var item = await api.GetContent(q.Id, ct);
                var proposal = await engine.Propose(item, ct);
                var quality = QualityGate.Check(proposal, cfg.Worker);
                var saved = false;
                if (publish && proposal.Changed && quality.Passed)
                {
                    if (string.IsNullOrWhiteSpace(cfg.UnifiedApi.Token)) throw new InvalidOperationException("GK_UNIFIED_API_TOKEN fehlt.");
                    var current = await unified.Read(item.Id, ct);
                    if (!string.Equals(current.Html, proposal.OriginalHtml, StringComparison.Ordinal))
                        throw new InvalidOperationException("Beitrag wurde seit der Prüfung verändert; Schreiben abgebrochen.");
                    Directory.CreateDirectory(cfg.Worker.BackupsDirectory);
                    var backup = Path.Combine(cfg.Worker.BackupsDirectory, $"post-{item.Id}-{DateTime.UtcNow:yyyyMMdd-HHmmss}.html");
                    File.WriteAllText(backup, current.Html);
                    await unified.Update(item.Id, proposal.CorrectedHtml, ct);
                    var verify = await unified.Read(item.Id, ct);
                    if (!string.Equals(verify.Html, proposal.CorrectedHtml, StringComparison.Ordinal))
                        throw new InvalidOperationException("Nachprüfung: gespeicherter Inhalt stimmt nicht überein.");
                    await unified.ClearCache(ct);
                    saved = true;
                }
                var resultStatus = quality.Passed ? (proposal.Changed ? "needs_correction" : "verified") :
                    quality.Findings.Any(x => x.Code == "INSUFFICIENT_SOURCES") ? "insufficient_sources" : "needs_correction";
                await api.SaveResult(item.Id, resultStatus,
                    $"Quality Gate: {(quality.Passed ? "bestanden" : "blockiert")}; Vorschlag geändert: {proposal.Changed}; gespeichert: {saved}",
                    quality.Findings, proposal.Sources, Hashing.Idempotency(item.Id, "result-" + proposal.CorrectedHtml), ct);
                var lastBackup = saved ? Directory.GetFiles(cfg.Worker.BackupsDirectory, $"post-{item.Id}-*.html").OrderByDescending(x=>x).FirstOrDefault() : null;
                rows.Add(new(item.Id, item.Title, proposal.Changed, saved, quality.Findings, proposal.Sources, proposal.OriginalHtml, proposal.CorrectedHtml, lastBackup, null));
                state.CompletedIds.Add(item.Id); state.Offset++;
                store.Save(state);
            }
            catch (Exception ex)
            {
                rows.Add(new(q.Id, q.Title ?? $"Beitrag {q.Id}", false, false, [], [], "", "", null, ex.Message));
                await log.Write("item_error", new { q.Id, error = ex.Message, exception = ex.GetType().Name });
            }
        }
        ReportWriter.Write(cfg.Worker.ReportsDirectory, publish ? "production" : "preview", rows);
        return rows;
    }
}
