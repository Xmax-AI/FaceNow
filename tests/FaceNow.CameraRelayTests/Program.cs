using System.Diagnostics;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.VirtualCamera;

if (args.Length is < 1 or > 2 || (args.Length == 2 && args[1] != "--registered-capture"))
    throw new ArgumentException("Pass the native camera build's x64 or ARM64 directory, optionally followed by --registered-capture.");
bool captureAlias = args.Length == 2;
string root = Path.GetFullPath(args[0]);
string link = "FaceNow-offline-relay-" + Guid.NewGuid().ToString("N");
if (captureAlias)
{
    using var registration = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\XMAX.AI\FaceNow\VirtualCamera");
    link = registration?.GetValue("SymbolicLink") as string
        ?? throw new InvalidOperationException("Register the camera before testing its DirectShow interface alias.");
}
string bitmap = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N") + ".bmp");
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
    var start = new ProcessStartInfo(Path.Combine(root, "FaceNow.CameraControl.exe")) { UseShellExecute = false, CreateNoWindow = true };
    start.ArgumentList.Add(captureAlias ? "--self-test-relay-capture" : "--self-test-relay"); start.ArgumentList.Add(link); start.ArgumentList.Add(bitmap);
    using var process = Process.Start(start) ?? throw new Exception("Could not start offline camera source.");
    try { await process.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(30)); }
    catch (TimeoutException) { process.Kill(); throw; }
    if (process.ExitCode != 0 || publisher.DeliveredFrames < 10) throw new Exception("The new native source did not receive ten production-publisher frames.");
    byte[] image = await File.ReadAllBytesAsync(bitmap);
    int offset = BitConverter.ToInt32(image, 10), w = BitConverter.ToInt32(image, 18), h = BitConverter.ToInt32(image, 22);
    if (w != width || h != -height) throw new Exception("Incorrect diagnostic bitmap layout.");
    int top = offset + ((height / 4) * width + width / 2) * 4;
    int bottom = offset + ((height * 3 / 4) * width + width / 2) * 4;
    if (image[top + 2] < 230 || image[top] > 25 || image[bottom] < 230 || image[bottom + 2] > 25)
        throw new Exception("Native source output was gray, inverted or had incorrect colors.");
    CameraDiagnostics.ReadSourceEvents();
    string log = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XMAX.AI", "FaceNow", "Logs", "virtual-camera.log");
    string contents = await File.ReadAllTextAsync(log);
    if (!contents.Contains($"pid={process.Id} stage=frame-drawn")) throw new Exception("Native source metadata was not collected into the app log.");
    Console.WriteLine($"PASS {(captureAlias ? "registered DirectShow alias" : "offline native source")} + production publisher: {publisher.DeliveredFrames} 1080p frames, correct top/bottom orientation, native diagnostics collected; registration unchanged.");
}
finally { await stop.CancelAsync(); await producer; if (File.Exists(bitmap)) File.Delete(bitmap); }
