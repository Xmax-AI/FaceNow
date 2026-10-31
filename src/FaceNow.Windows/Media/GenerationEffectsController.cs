using System.Text.Json;
using FaceNow.Core.Media;
using FaceNow.Core.Product;

namespace FaceNow.Windows.Media;

internal sealed class GenerationEffectsController
{
    private BeautySettings settings;
    private readonly string path;
    private readonly object gate = new();
    private Task savingTask = Task.CompletedTask;
    private CancellationTokenSource? saving;
    private BeautySettings? applied;
    public bool IsApplying => Settings.Enabled && Settings != Volatile.Read(ref applied);
    public BeautySettings Settings => Volatile.Read(ref settings);
    internal event Action? Changed;
    public GenerationEffectsController(string? settingsPath = null)
    {
        path = settingsPath ?? Path.Combine(ProductProfile.Current.DataDirectory, "beauty.json");
        settings = new();
        try { var saved = JsonSerializer.Deserialize<BeautySettings>(File.ReadAllText(path)); saved?.Validate(); if (saved is not null) settings = saved; }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or ArgumentException) { }
    }
    public void Update(BeautySettings value)
    {
        value.Validate();
        lock (gate)
        {
            if (value == Settings) return; Volatile.Write(ref settings, value);
            Volatile.Write(ref applied, null);
            saving?.Cancel(); saving?.Dispose(); saving = new();
            savingTask = SaveAsync(value, saving.Token);
        }
        Changed?.Invoke();
    }
    public Task FlushAsync() { lock (gate) return savingTask; }
    public void BeginSession() { Volatile.Write(ref applied, null); Changed?.Invoke(); }
    public void MarkApplied(BeautySettings value)
    { if (value == Settings && value != Volatile.Read(ref applied)) { Volatile.Write(ref applied, value); Changed?.Invoke(); } }
    private async Task SaveAsync(BeautySettings value, CancellationToken token)
    {
        string temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            await Task.Delay(120, token); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            await File.WriteAllTextAsync(temporary, JsonSerializer.Serialize(value), token);
            token.ThrowIfCancellationRequested(); File.Move(temporary, path, true);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or OperationCanceledException) { }
        finally { try { if (File.Exists(temporary)) File.Delete(temporary); } catch (IOException) { } }
    }
}
