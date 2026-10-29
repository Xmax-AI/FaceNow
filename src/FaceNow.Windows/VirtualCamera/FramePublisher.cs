using System.Buffers;
using System.Buffers.Binary;
using System.Diagnostics;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using FaceNow.Core.VirtualCamera;

namespace FaceNow.Windows.VirtualCamera;

/// <summary>Latest-frame pipe server, readable only by this user and the local Frame Server accounts.</summary>
internal sealed class FramePublisher : IAsyncDisposable
{
    private const uint Magic = 0x314e4346;
    private readonly object gate = new();
    private readonly Guid sessionId;
    private readonly CancellationTokenSource stopping = new();
    private readonly NamedPipeServerStream[] pipes;
    private readonly Task[] workers;
    private Frame? latest;
    private bool stopped;
    private long sequence, lastSubmitted;
    internal long SubmittedFrames => Interlocked.Read(ref sequence);
    internal bool HasFreshFrame => Volatile.Read(ref lastSubmitted) > 0 && Stopwatch.GetElapsedTime(Volatile.Read(ref lastSubmitted)).TotalMilliseconds < 1500;
    internal long DeliveredFrames;
    private long connections, failedTransfers;
    private readonly Timer diagnostics;
    internal Exception? Failure;

    private sealed class Frame(byte[] bytes, OutputFrame description, long sequence)
    {
        private int references = 1;
        internal readonly byte[] Bytes = bytes;
        internal readonly OutputFrame Description = description;
        internal readonly long Sequence = sequence;
        internal readonly long CreatedAt = Stopwatch.GetTimestamp();
        internal void Retain() => Interlocked.Increment(ref references);
        internal void Release() { if (Interlocked.Decrement(ref references) == 0) ArrayPool<byte>.Shared.Return(Bytes); }
    }

    internal FramePublisher(string symbolicLink, Guid sessionId)
    {
        this.sessionId = sessionId;
        string name = "FaceNow.Camera.v1." + Convert.ToHexStringLower(SHA256.HashData(Encoding.Unicode.GetBytes(symbolicLink.ToLowerInvariant())));
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(true, false);
        security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(WellKnownSidType.NetworkSid, null), PipeAccessRights.FullControl, AccessControlType.Deny));
        security.AddAccessRule(new PipeAccessRule(WindowsIdentity.GetCurrent().User!, PipeAccessRights.FullControl, AccessControlType.Allow));
        // Grant data access without FILE_CREATE_PIPE_INSTANCE to service clients.
        var clientRights = PipeAccessRights.ReadData | PipeAccessRights.WriteData | PipeAccessRights.ReadAttributes |
            PipeAccessRights.ReadExtendedAttributes | PipeAccessRights.ReadPermissions | PipeAccessRights.Synchronize;
        foreach (var sid in new[] { WellKnownSidType.LocalServiceSid, WellKnownSidType.LocalSystemSid })
            security.AddAccessRule(new PipeAccessRule(new SecurityIdentifier(sid, null), clientRights, AccessControlType.Allow));
        var created = new List<NamedPipeServerStream>();
        try
        {
            for (int i = 0; i < 4; i++) created.Add(NamedPipeServerStreamAcl.Create(name, PipeDirection.InOut, 4,
                PipeTransmissionMode.Byte, PipeOptions.Asynchronous | (i == 0 ? PipeOptions.FirstPipeInstance : PipeOptions.None),
                4096, 65536, security));
            pipes = created.ToArray();
            workers = pipes.Select(pipe => Task.Run(() => ServeAsync(pipe))).ToArray();
            CameraDiagnostics.Write($"Publisher started; OS={Environment.OSVersion.Version}; process={System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture}; endpoint={name[^16..]}");
            diagnostics = new Timer(_ =>
            {
                CameraDiagnostics.Write($"Publisher frames submitted={SubmittedFrames} delivered={Interlocked.Read(ref DeliveredFrames)} connections={Interlocked.Read(ref connections)} failedTransfers={Interlocked.Read(ref failedTransfers)} fresh={HasFreshFrame}");
                CameraDiagnostics.ReadSourceEvents();
            }, null, 5000, 10000);
        }
        catch { foreach (var pipe in created) pipe.Dispose(); stopping.Dispose(); throw; }
    }

    internal bool TrySubmit(OutputFrame frame)
    {
        if (Volatile.Read(ref Failure) is not null || frame.SessionId != sessionId || frame.Width is < 1 or > 4096 || frame.Height is < 1 or > 2160 ||
            frame.Stride < frame.Width * 4 || frame.Stride > 32768 ||
            (long)frame.Stride * frame.Height > 64 * 1024 * 1024 || frame.Bgra.Length < (long)frame.Stride * frame.Height)
            return false;
        if (!Monitor.TryEnter(gate)) return false;
        Frame? previous = null;
        try
        {
            if (stopped) return false;
            int length = frame.Stride * frame.Height;
            var copy = ArrayPool<byte>.Shared.Rent(length);
            frame.Bgra.Span[..length].CopyTo(copy);
            previous = latest;
            latest = new(copy, frame with { Bgra = default }, Interlocked.Increment(ref sequence));
            Volatile.Write(ref lastSubmitted, Stopwatch.GetTimestamp());
            return true;
        }
        finally { Monitor.Exit(gate); previous?.Release(); }
    }

    private async Task ServeAsync(NamedPipeServerStream pipe)
    {
        byte[] request = new byte[8], header = new byte[64];
        var token = stopping.Token;
        while (!token.IsCancellationRequested)
        {
            try
            {
                await pipe.WaitForConnectionAsync(token);
                if (Interlocked.Increment(ref connections) == 1) CameraDiagnostics.Write("First camera consumer connected");
                while (!token.IsCancellationRequested && pipe.IsConnected)
                {
                    await pipe.ReadExactlyAsync(request, token);
                    if (BinaryPrimitives.ReadUInt32LittleEndian(request) != Magic || BinaryPrimitives.ReadUInt32LittleEndian(request.AsSpan(4)) != 1) break;
                    Frame? frame;
                    lock (gate) { frame = !stopped && latest is { } item && Stopwatch.GetElapsedTime(item.CreatedAt).TotalMilliseconds < 1500 ? item : null; frame?.Retain(); }
                    try
                    {
                        Array.Clear(header);
                        BinaryPrimitives.WriteUInt32LittleEndian(header, Magic);
                        BinaryPrimitives.WriteUInt32LittleEndian(header.AsSpan(4), 1);
                        if (frame is not null)
                        {
                            var value = frame.Description;
                            BinaryPrimitives.WriteInt32LittleEndian(header.AsSpan(8), value.Width);
                            BinaryPrimitives.WriteInt32LittleEndian(header.AsSpan(12), value.Height);
                            BinaryPrimitives.WriteInt32LittleEndian(header.AsSpan(16), value.Stride);
                            BinaryPrimitives.WriteInt32LittleEndian(header.AsSpan(20), value.Stride * value.Height);
                            BinaryPrimitives.WriteInt64LittleEndian(header.AsSpan(24), value.TimestampMicroseconds);
                            value.SessionId.TryWriteBytes(header.AsSpan(32, 16));
                            BinaryPrimitives.WriteInt64LittleEndian(header.AsSpan(48), frame.Sequence);
                            BinaryPrimitives.WriteInt32LittleEndian(header.AsSpan(56), 1);
                        }
                        // A stalled consumer cannot retain a frame or worker indefinitely.
                        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
                        deadline.CancelAfter(TimeSpan.FromSeconds(2));
                        await pipe.WriteAsync(header, deadline.Token);
                        if (frame is not null)
                        {
                            await pipe.WriteAsync(frame.Bytes.AsMemory(0, frame.Description.Stride * frame.Description.Height), deadline.Token);
                            Interlocked.Increment(ref DeliveredFrames);
                        }
                    }
                    finally { frame?.Release(); }
                }
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { break; }
            catch (Exception error) when (error is IOException or OperationCanceledException)
            {
                if (Interlocked.Increment(ref failedTransfers) == 1) CameraDiagnostics.Error("Camera consumer disconnected or transfer timed out", error);
            }
            catch (Exception error) { CameraDiagnostics.Error("Publisher failed", error); Interlocked.CompareExchange(ref Failure, error, null); break; }
            finally { if (!token.IsCancellationRequested && pipe.IsConnected) pipe.Disconnect(); }
        }
    }

    public async ValueTask DisposeAsync()
    {
        Frame? previous;
        lock (gate) { if (stopped) return; stopped = true; previous = latest; latest = null; }
        previous?.Release();
        await diagnostics.DisposeAsync();
        CameraDiagnostics.ReadSourceEvents();
        await stopping.CancelAsync();
        try { await Task.WhenAll(workers); }
        finally { foreach (var pipe in pipes) pipe.Dispose(); stopping.Dispose(); CameraDiagnostics.Write($"Publisher stopped; submitted={SubmittedFrames} delivered={Interlocked.Read(ref DeliveredFrames)}"); }
    }
}
