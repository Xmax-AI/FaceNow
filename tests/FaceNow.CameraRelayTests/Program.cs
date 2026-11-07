using System.Diagnostics;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.VirtualCamera;

bool captureAlias = args.Length == 2 && args[1] == "--registered-capture";
bool directShow = args.Length == 2 && args[1] == "--directshow-prototype";
if (args.Length != 1 && !captureAlias && !directShow)
    throw new ArgumentException("Pass the native camera build directory, optionally followed by --registered-capture, or ffmpeg.exe followed by --directshow-prototype.");
string root = Path.GetFullPath(args[0]);
string link = "FaceNow-offline-relay-" + Guid.NewGuid().ToString("N");
if (captureAlias)
{
    using var registration = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\XMAX.AI\FaceNow\VirtualCamera");
    link = registration?.GetValue("SymbolicLink") as string
        ?? throw new InvalidOperationException("Register the camera before testing its DirectShow interface alias.");
}
if (directShow)
{
    using var current = Process.GetCurrentProcess();
    link = $"FaceNow.DirectShow.Prototype.{current.SessionId}";
}
string output = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + (directShow ? ".bgra" : ".bmp"));
Guid session = Guid.NewGuid();
await using var publisher = new FramePublisher(link, session);
const int width = 1920, height = 1080;
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
    var start = new ProcessStartInfo(directShow ? root : Path.Combine(root, "FaceNow.CameraControl.exe")) { UseShellExecute = false, CreateNoWindow = true };
    string[] arguments = directShow
        ? ["-nostdin", "-hide_banner", "-loglevel", "warning", "-f", "dshow", "-video_size", "1280x720", "-i", "video=FaceNow DirectShow Test",
            "-frames:v", sampleCount.ToString(), "-fps_mode", "passthrough", "-an", "-c:v", "rawvideo", "-pix_fmt", "bgra", "-f", "rawvideo", output]
        : [captureAlias ? "--self-test-relay-capture" : "--self-test-relay", link, output];
    foreach (string argument in arguments) start.ArgumentList.Add(argument);
    using var process = Process.Start(start) ?? throw new Exception("Could not start offline camera source.");
    try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(30)); }
    catch (TimeoutException) { process.Kill(); throw; }
    if (process.ExitCode != 0 || publisher.DeliveredFrames < 10) throw new Exception("The new native source did not receive ten production-publisher frames.");
    byte[] image = await File.ReadAllBytesAsync(output);
    if (directShow)
    {
        const int captureWidth = 1280, captureHeight = 720, sampleBytes = captureWidth * captureHeight * 4;
        if (image.Length != sampleBytes * sampleCount) throw new Exception("Incorrect DirectShow frame size or count.");
        for (int frame = sampleCount - 10; frame < sampleCount; frame++)
            VerifyPixels(image, frame * sampleBytes, captureWidth, captureHeight);
        Console.WriteLine($"PASS registered DirectShow prototype + production publisher: {sampleCount} 720p frames, correct color and orientation.");
        return;
    }
    int offset = BitConverter.ToInt32(image, 10), w = BitConverter.ToInt32(image, 18), h = BitConverter.ToInt32(image, 22);
    if (w != width || h != -height) throw new Exception("Incorrect diagnostic bitmap layout.");
    VerifyPixels(image, offset, width, height);
    CameraDiagnostics.ReadSourceEvents();
    string log = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XMAX.AI", "FaceNow", "Logs", "virtual-camera.log");
    string contents = await File.ReadAllTextAsync(log);
    if (!contents.Contains($"pid={process.Id} stage=frame-drawn")) throw new Exception("Native source metadata was not collected into the app log.");
    Console.WriteLine($"PASS {(captureAlias ? "registered DirectShow alias" : "offline native source")} + production publisher: {publisher.DeliveredFrames} 1080p frames, correct top/bottom orientation, native diagnostics collected; registration unchanged.");
}
finally { await stop.CancelAsync(); await producer; File.Delete(output); }

static void VerifyPixels(byte[] image, int offset, int width, int height)
{
    int top = offset + ((height / 4) * width + width / 2) * 4;
    int bottom = offset + ((height * 3 / 4) * width + width / 2) * 4;
    if (image[top + 2] < 230 || image[top] > 25 || image[bottom] < 230 || image[bottom + 2] > 25)
        throw new Exception("Native source output was gray, inverted or had incorrect colors.");
}
