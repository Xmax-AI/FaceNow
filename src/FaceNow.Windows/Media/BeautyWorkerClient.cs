using System.Buffers.Binary;
using System.Diagnostics;
using System.IO.MemoryMappedFiles;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using FaceNow.Core.Media;

namespace FaceNow.Windows.Media;

/// <summary>One local helper, private control pipe and bounded shared-memory surface. No RTC or account credentials.</summary>
internal sealed class BeautyWorkerClient(string? executable = null) : IResultBeautyProcessor
{
    private const int Capacity = 32 * 1024 * 1024;
    private Process? process;
    private NamedPipeServerStream? pipe;
    private MemoryMappedFile? memory;
    private MemoryMappedViewAccessor? view;
    private readonly SemaphoreSlim operations = new(1, 1);
    private bool disposed;
    private async Task StartAsync(CancellationToken token)
    {
        string path = executable ?? Path.Combine(AppContext.BaseDirectory, "FaceNow.BeautyWorker.exe");
        if (!File.Exists(path)) throw new FileNotFoundException("Beauty worker is missing.");
        string id = Guid.NewGuid().ToString("N"), pipeName = "FaceNow.Beauty." + id, mapName = @"Local\FaceNow.Beauty." + id;
        memory = MemoryMappedFile.CreateNew(mapName, Capacity * 2L);
        view = memory.CreateViewAccessor();
        pipe = new(pipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        var start = new ProcessStartInfo(path) { UseShellExecute = false, CreateNoWindow = true, WorkingDirectory = Path.GetDirectoryName(path)! };
        start.ArgumentList.Add(@"\\.\pipe\" + pipeName); start.ArgumentList.Add(mapName);
        process = Process.Start(start) ?? throw new IOException("Beauty worker could not start.");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(5));
        await pipe.WaitForConnectionAsync(deadline.Token);
        byte[] hello = new byte[16]; await pipe.ReadExactlyAsync(hello, deadline.Token);
        if (BinaryPrimitives.ReadInt32LittleEndian(hello) != 0) throw new IOException("Beauty engine could not initialize (" + BinaryPrimitives.ReadInt32LittleEndian(hello) + ").");
    }
    public async ValueTask<ResultFrame> ProcessAsync(ResultFrame frame, BeautySettings settings, CancellationToken cancellationToken)
    {
        settings.Validate();
        if (frame.Length > Capacity) throw new InvalidDataException("Beauty frame exceeds shared-memory capacity.");
        await operations.WaitAsync(cancellationToken);
        try
        {
            ObjectDisposedException.ThrowIf(disposed, this);
            if (process is null) await StartAsync(cancellationToken);
            if (!MemoryMarshal.TryGetArray((ReadOnlyMemory<byte>)frame.Pixels, out var input)) throw new InvalidDataException();
            view!.WriteArray(0, input.Array!, input.Offset, input.Count);
            using var bytes = new MemoryStream(); using (var writer = new BinaryWriter(bytes, System.Text.Encoding.UTF8, true))
            { writer.Write(0x31424E46u); writer.Write(1u); writer.Write(frame.Width); writer.Write(frame.Height); writer.Write(frame.Stride); writer.Write(frame.Length); writer.Write(settings.Smoothness); writer.Write(settings.Lightening); writer.Write(settings.Sharpness); writer.Write(settings.Redness); }
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken); deadline.CancelAfter(TimeSpan.FromMilliseconds(700));
            await pipe!.WriteAsync(bytes.ToArray(), deadline.Token); await pipe.FlushAsync(deadline.Token);
            byte[] response = new byte[16]; await pipe.ReadExactlyAsync(response, deadline.Token);
            int code = BinaryPrimitives.ReadInt32LittleEndian(response), width = BinaryPrimitives.ReadInt32LittleEndian(response.AsSpan(4)), height = BinaryPrimitives.ReadInt32LittleEndian(response.AsSpan(8)), length = BinaryPrimitives.ReadInt32LittleEndian(response.AsSpan(12));
            if (code != 0) throw new IOException("Beauty processing failed (" + code + ").");
            if (width != frame.Width || height != frame.Height || length != frame.Length) throw new InvalidDataException("Beauty output dimensions changed.");
            var output = new ResultFrame(width, height, frame.TimestampMicroseconds, frame.SessionId);
            try
            {
                MemoryMarshal.TryGetArray((ReadOnlyMemory<byte>)output.Pixels, out var target);
                view.ReadArray(Capacity, target.Array!, target.Offset, length);
                return output;
            }
            catch { output.Dispose(); throw; }
        }
        finally { operations.Release(); }
    }
    public async ValueTask DisposeAsync()
    {
        await operations.WaitAsync();
        try
        {
            if (disposed) return; disposed = true; pipe?.Dispose();
            if (process is not null)
            {
                try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(1)); }
                catch (TimeoutException) { if (!process.HasExited) process.Kill(entireProcessTree: true); await process.WaitForExitAsync(); }
                process.Dispose();
            }
            view?.Dispose(); memory?.Dispose();
        }
        finally { operations.Release(); }
    }
}
