using System.Diagnostics;
using System.IO.Pipes;
using System.Security.Cryptography;
using System.Text;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.VirtualCamera;

if (args is ["--peer-disconnect"])
{
    await VerifyPeerDisconnectAsync();
    return;
}

if (args is ["--idle-timeout"])
{
    await VerifyIdleTimeoutAsync();
    return;
}

string mode = args.Length >= 2 ? args[1] : "--offline";
bool registered = mode == "--registered";
bool captureAlias = mode == "--registered-capture";
bool prototype = mode == "--directshow-prototype";
bool directShow = prototype || mode == "--directshow";
if (args.Length is not (1 or 2 or 4) || mode is not ("--offline" or "--offline-late-link" or "--registered" or "--registered-capture" or "--directshow-prototype" or "--directshow") ||
    (prototype && args.Length != 2))
    throw new ArgumentException("Pass the native build directory (x64 FFmpeg for DirectShow modes), an optional capture mode, and optional width and height.");
int width = args.Length == 4 ? int.Parse(args[2]) : 1920;
int height = args.Length == 4 ? int.Parse(args[3]) : 1080;
string root = Path.GetFullPath(args[0]);
string link = "FaceNow-offline-relay-" + Guid.NewGuid().ToString("N");
if (registered || captureAlias)
{
    using var registration = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\XMAX.AI\FaceNow\VirtualCamera");
    link = registration?.GetValue("SymbolicLink") as string
        ?? throw new InvalidOperationException("Register the camera before testing its DirectShow interface alias.");
}
if (directShow)
{
    using var current = Process.GetCurrentProcess();
    string prefix = prototype ? "FaceNow.DirectShow.Prototype" : "FaceNow.DirectShow";
    link = $"{prefix}.{current.SessionId}";
}
string output = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + (directShow ? ".bgra" : ".bmp"));
Guid session = Guid.NewGuid();
await using var publisher = new FramePublisher(link, new(width, height, 30, session));
byte[] pixels = new byte[width * height * 4];
for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x)
{
    int at = (y * width + x) * 4;
    pixels[at] = y >= height / 2 ? (byte)255 : (byte)0;
    pixels[at + 2] = y < height / 2 ? (byte)255 : (byte)0;
    pixels[at + 3] = 255;
}
using var stop = new CancellationTokenSource();
Task producer = Task.Run(async () =>
{
    try
    {
        while (!stop.IsCancellationRequested)
        {
            publisher.TrySubmit(new(pixels, width, height, width * 4, Environment.TickCount64 * 1000, session));
            await Task.Delay(30, stop.Token);
        }
    }
    catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
});
try
{
    const int sampleCount = 12;
    int captureWidth = prototype ? 1280 : width;
    int captureHeight = prototype ? 720 : height;
    string captureName = prototype ? "FaceNow DirectShow Test" : "FaceNow 虚拟摄像头";
    var start = new ProcessStartInfo(directShow ? root : Path.Combine(root, "FaceNow.CameraControl.exe")) { UseShellExecute = false, CreateNoWindow = true };
    string[] arguments = directShow
        ? ["-nostdin", "-hide_banner", "-loglevel", "warning", "-f", "dshow", "-video_size", $"{captureWidth}x{captureHeight}", "-i", $"video={captureName}",
            "-frames:v", sampleCount.ToString(), "-fps_mode", "passthrough", "-an", "-c:v", "rawvideo", "-pix_fmt", "bgra", "-f", "rawvideo", output]
        : registered ? ["--verify", output]
        : [captureAlias ? "--self-test-relay-capture" : mode == "--offline-late-link" ? "--self-test-relay-late-link" : "--self-test-relay", link, output];
    foreach (string argument in arguments) start.ArgumentList.Add(argument);
    using var process = Process.Start(start) ?? throw new Exception("Could not start offline camera source.");
    try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(30)); }
    catch (TimeoutException) { process.Kill(); throw; }
    if (process.ExitCode != 0)
        throw new Exception($"Camera reader exited with code {process.ExitCode} after receiving {publisher.DeliveredFrames} frames.");
    byte[] image = await File.ReadAllBytesAsync(output);
    if (directShow)
    {
        int sampleBytes = captureWidth * captureHeight * 4;
        if (image.Length != sampleBytes * sampleCount) throw new Exception("Incorrect DirectShow frame size or count.");
        for (int frame = sampleCount - 10; frame < sampleCount; frame++)
            VerifyPixels(image, frame * sampleBytes, captureWidth, captureHeight);
        Console.WriteLine($"PASS {mode}: {sampleCount} frames at {captureWidth}×{captureHeight}, correct orientation and no bars.");
        return;
    }
    int offset = BitConverter.ToInt32(image, 10), w = BitConverter.ToInt32(image, 18), h = BitConverter.ToInt32(image, 22);
    if (w != width || h != -height) throw new Exception($"Received {w}×{-h} from the camera, expected {width}×{height}.");
    VerifyPixels(image, offset, width, height);
    if (publisher.DeliveredFrames < 10)
        throw new Exception($"The camera received {publisher.DeliveredFrames} of ten expected production frames at {w}×{-h}.");
    CameraDiagnostics.ReadSourceEvents();
    string log = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XMAX.AI", "FaceNow", "Logs", "virtual-camera.log");
    string contents = await File.ReadAllTextAsync(log);
    if (!registered && !contents.Contains($"pid={process.Id} stage=frame-drawn"))
        throw new Exception("Native source metadata was not collected into the app log.");
    Console.WriteLine($"PASS {mode}: {publisher.DeliveredFrames} frames at {w}×{-h}, correct orientation and no bars.");
}
finally { await stop.CancelAsync(); await producer; File.Delete(output); }

static async Task VerifyIdleTimeoutAsync()
{
    string endpoint = "FaceNow-idle-relay-" + Guid.NewGuid().ToString("N");
    string hash = Convert.ToHexStringLower(SHA256.HashData(Encoding.Unicode.GetBytes(endpoint.ToLowerInvariant())));
    string pipeName = "FaceNow.Camera.v1." + hash;
    await using var publisher = new FramePublisher(endpoint, new(4, 4, 30, Guid.NewGuid()));
    var idle = Enumerable.Range(0, 4)
        .Select(_ => new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous))
        .ToArray();
    using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(8));
    try
    {
        foreach (var client in idle)
            await client.ConnectAsync(deadline.Token);
        // A partial request must also expire while the connection is still open.
        await idle[0].WriteAsync(new byte[] { 0x46 }, deadline.Token);

        using var capture = new NamedPipeClientStream(".", pipeName, PipeDirection.InOut, PipeOptions.Asynchronous);
        await capture.ConnectAsync(deadline.Token);
        await capture.WriteAsync(new byte[] { 0x46, 0x43, 0x46, 0x31, 1, 0, 0, 0 }, deadline.Token);
        byte[] reply = new byte[64];
        await capture.ReadExactlyAsync(reply, deadline.Token);
        if (BitConverter.ToUInt32(reply) != 0x314e4346 || BitConverter.ToInt32(reply, 8) != 4 || BitConverter.ToInt32(reply, 12) != 4)
            throw new Exception("Unexpected format reply after idle clients timed out.");
        foreach (var client in idle)
        {
            try
            {
                if (await client.ReadAsync(reply.AsMemory(0, 1), deadline.Token) != 0)
                    throw new InvalidOperationException("An idle client received unexpected data.");
            }
            catch (IOException) { /* A disconnected pipe can report a broken connection instead of EOF. */ }
        }
        Console.WriteLine("PASS: Silent and partial requests expire and a new client negotiates the format.");
    }
    finally
    {
        foreach (var client in idle)
            client.Dispose();
    }
}

static void VerifyPixels(byte[] image, int offset, int width, int height)
{
    foreach (int x in new[] { 0, width / 2, width - 1 })
    {
        int top = offset + x * 4;
        int bottom = offset + ((height - 1) * width + x) * 4;
        if (image[top + 2] < 230 || image[top] > 25 || image[bottom] < 230 || image[bottom + 2] > 25)
            throw new Exception("Native source output had bars, was inverted or had incorrect colors.");
    }
}

static async Task VerifyPeerDisconnectAsync()
{
    string endpoint = "FaceNow-aborted-relay-" + Guid.NewGuid().ToString("N");
    string name = "FaceNow.Camera.v1." + Convert.ToHexStringLower(SHA256.HashData(Encoding.Unicode.GetBytes(endpoint.ToLowerInvariant())));
    Guid session = Guid.NewGuid();
    const int width = 1920, height = 1080;
    byte[] pixels = new byte[width * height * 4];
    pixels[0] = 27; pixels[^1] = 255;
    await using var publisher = new FramePublisher(endpoint, new(width, height, 30, session));
    publisher.TrySubmit(new(pixels, width, height, width * 4, 1, session));
    using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    byte[] request = [0x46, 0x43, 0x4e, 0x31, 1, 0, 0, 0];
    // Drop every client after the header, while its full-HD payload is still being written.
    for (int i = 0; i < 4; ++i)
    {
        using var abandoned = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
        await abandoned.ConnectAsync(deadline.Token);
        publisher.TrySubmit(new(pixels, width, height, width * 4, i + 2, session));
        await abandoned.WriteAsync(request, deadline.Token);
        byte[] header = new byte[64];
        await abandoned.ReadExactlyAsync(header, deadline.Token);
        if (BitConverter.ToInt32(header, 20) != pixels.Length)
            throw new Exception("The disconnect fixture did not interrupt a full-HD frame.");
        abandoned.Dispose();
        await Task.Delay(50, deadline.Token);
    }
    using var recovered = new NamedPipeClientStream(".", name, PipeDirection.InOut, PipeOptions.Asynchronous);
    await recovered.ConnectAsync(deadline.Token);
    publisher.TrySubmit(new(pixels, width, height, width * 4, 10, session));
    await recovered.WriteAsync(request, deadline.Token);
    byte[] reply = new byte[64], actual = new byte[pixels.Length];
    await recovered.ReadExactlyAsync(reply, deadline.Token);
    await recovered.ReadExactlyAsync(actual, deadline.Token);
    if (!actual.AsSpan().SequenceEqual(pixels) || publisher.Failure is not null)
        throw new Exception("Camera output did not recover intact after client disconnects.");
    Console.WriteLine("PASS: Full-HD video delivery recovers after four mid-frame client disconnects.");
}
