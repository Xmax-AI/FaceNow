//
//  MainWindow.CameraVerification.cs
//  FaceNow
//

using System.IO;
using System.Runtime.InteropServices;
using FaceNow.Core.VirtualCamera;
using FaceNow.Windows.VirtualCamera;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using Xmax.SDK;

namespace FaceNow.App;

public sealed partial class MainWindow
{
    private static void VerificationProgress(
        string message
    )
    {
        string? directory = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
        if (string.IsNullOrEmpty(directory))
            return;
        Directory.CreateDirectory(directory);
        File.AppendAllText(
            Path.Combine(
            directory,
            "camera-progress.txt"
        ),
            DateTime.UtcNow.ToString("O") + " " + message + Environment.NewLine
        );
    }

    private static bool IsWaitingCanvas(
        byte[] data
    )
    {
        // RGB/NV12 round trips can introduce rounding in the neutral placeholder.
        for (int i = 0; i < data.Length; i += 4)
            if (Math.Abs(data[i] - 244) > 4 || Math.Abs(data[i + 1] - 243) > 4 || Math.Abs(data[i + 2] - 241) > 4)
                return false;
        return data.Length > 0;
    }

    private async Task<(byte[] Pixels, uint Width, uint Height)> CaptureCameraDiagnosticAsync(
        string name
    )
    {
        string path = await virtualCameraOutput.CaptureDiagnosticFrameAsync();
        try
        {
            byte[] contents = await File.ReadAllBytesAsync(path);
            using var memory = new MemoryStream(contents);
            using var stream = memory.AsRandomAccessStream();
            var decoder = await BitmapDecoder.CreateAsync(stream);
            byte[] bytes = (await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore,
                new BitmapTransform(), ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage)).DetachPixelData();
            string? directory = Environment.GetEnvironmentVariable("FACENOW_SMOKE_OUTPUT");
            if (directory is not null)
                File.Copy(path, Path.Combine(directory, name + ".bmp"), true);
            return (bytes, decoder.PixelWidth, decoder.PixelHeight);
        }
        finally
        {
            File.Delete(path);
        }
    }

    private async Task VerifyCameraRelayAsync()
    {
        VerificationProgress("Starting relay test");
        Check(
            virtualCameraOutput.Status.Registration == CameraRegistrationState.Registered,
            "Install and enable the FaceNow camera first."
        );
        using var client = new XmaxClient();
        await using var realtime = client.CreateRealtimeManager();
        // Register the production SDK listener without preparing a camera or starting generation.
        await using var sdkPump = await RemoteCameraPump.StartAsync(
            realtime,
            virtualCameraOutput,
            new VideoFormat(1920, 1080),
            Model.ReportError
        );
        VerificationProgress("Relay publisher started");
        Guid first = sdkPump.SessionId;
        // Exercise a full HD payload (larger than the pipe buffer), including padded rows.
        const int width = 1920, height = 1080, stride = width * 4 + 16;
        byte[] pixels = new byte[stride * height];
        void Fill(
            bool second
        )
        {
            Array.Fill(pixels, (byte)39); // padding must not appear as image data
            for (int y = 0; y < height; y++)
                for (int x = 0; x < width; x++)
                {
                    int at = y * stride + x * 4;
                    pixels[at] = !second && x >= width / 2 ? (byte)255 : (byte)0;
                    pixels[at + 1] = second ? (byte)255 : (byte)0;
                    pixels[at + 2] = (!second && x < width / 2) || (second && x >= width / 2) ? (byte)255 : (byte)0;
                    pixels[at + 3] = 255;
                }
        }
        Task ProduceAsync(
            Guid identity,
            CancellationToken token
        ) => Task.Run(async () =>
        {
            var pinned = GCHandle.Alloc(pixels, GCHandleType.Pinned);
            try
            {
                long timestamp = 0;
                while (!token.IsCancellationRequested)
                {
                    RemoteCameraPump.SubmitBgra(virtualCameraOutput, pinned.AddrOfPinnedObject(), pixels.Length,
                        width, height, stride, timestamp += 33333, identity);
                    await Task.Delay(30, token);
                }
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) { }
            finally
            {
                pinned.Free();
            }
        });
        static bool IsColor(
            byte[] data,
            uint width,
            uint height,
            double x,
            double y,
            byte r,
            byte g,
            byte b
        )
        {
            int at = ((int)(height * y) * (int)width + (int)(width * x)) * 4;
            return Math.Abs(data[at] - b) < 25 && Math.Abs(data[at + 1] - g) < 25 && Math.Abs(data[at + 2] - r) < 25;
        }
        Fill(false);
        Check(
            !virtualCameraOutput.TrySubmit(new(
            pixels,
            width,
            height,
            width * 4 - 1,
            0,
            first
        )),
            "Invalid stride was accepted."
        );
        Check(
            !virtualCameraOutput.TrySubmit(new(
            pixels,
            width,
            height,
            stride,
            0,
            Guid.NewGuid()
        )),
            "An unrelated session was accepted."
        );
        using var sending = new CancellationTokenSource();
        Task producer = ProduceAsync(first, sending.Token);
        try
        {
            await Task.Delay(250);
            VerificationProgress("Capturing 1080p virtual camera");
            var actual = await CaptureCameraDiagnosticAsync("camera-relay-bgra");
            VerificationProgress("Captured 1080p virtual camera");
            Check(actual.Width == 1920 && actual.Height == 1080, "Windows camera did not negotiate 1080p.");
            Check(IsColor(actual.Pixels, actual.Width, actual.Height, .25, .5, 255, 0, 0) &&
                  IsColor(
                      actual.Pixels,
                      actual.Width,
                      actual.Height,
                      .75,
                      .5,
                      0,
                      0,
                      255
                  ), "Windows did not receive the submitted BGRA colors/direction.");
            Check(IsColor(actual.Pixels, actual.Width, actual.Height, .02, .02, 255, 0, 0) &&
                  IsColor(actual.Pixels, actual.Width, actual.Height, .98, .02, 0, 0, 255) &&
                  IsColor(actual.Pixels, actual.Width, actual.Height, .02, .98, 255, 0, 0) &&
                  IsColor(actual.Pixels, actual.Width, actual.Height, .98, .98, 0, 0, 255),
                "The camera did not fill its output without black bars.");
            Check(
                virtualCameraOutput.DeliveredFrames >= 10,
                "Frame Server did not read the app's video pipe."
            );
            await UntilAsync(() => virtualCameraOutput.Status.State == CameraOutputState.Running);
            await sending.CancelAsync();
            await producer;
            await Task.Delay(1800);
            var expired = await CaptureCameraDiagnosticAsync("camera-relay-expired");
            Check(
                IsWaitingCanvas(expired.Pixels),
                "Producer silence did not select the plain gray waiting canvas."
            );
            await UntilAsync(() => virtualCameraOutput.Status.State == CameraOutputState.Stopped);
            await virtualCameraOutput.StopAsync();
            Check(
                !virtualCameraOutput.TrySubmit(new(
                pixels,
                width,
                height,
                stride,
                0,
                first
            )),
                "A stopped output accepted a frame."
            );
            var stopped = await CaptureCameraDiagnosticAsync("camera-relay-stopped");
            Check(
                IsWaitingCanvas(stopped.Pixels),
                "Stopped camera output did not select the plain gray waiting canvas."
            );
            Guid second = Guid.NewGuid();
            await virtualCameraOutput.StartAsync(new(1920, 1080, 30, second));
            Check(
                !virtualCameraOutput.TrySubmit(new(
                pixels,
                width,
                height,
                stride,
                0,
                first
            )),
                "A previous session was accepted after restart."
            );
            Fill(true);
            using var restarted = new CancellationTokenSource();
            Task next = ProduceAsync(second, restarted.Token);
            try
            {
                await Task.Delay(250);
                var resumed = await CaptureCameraDiagnosticAsync("camera-relay-restarted");
                Check(IsColor(resumed.Pixels, resumed.Width, resumed.Height, .25, .5, 0, 255, 0) &&
                      IsColor(
                          resumed.Pixels,
                          resumed.Width,
                          resumed.Height,
                          .75,
                          .5,
                          255,
                          255,
                          0
                      ), "Camera did not receive the new session after restart.");
            }
            finally
            {
                await restarted.CancelAsync();
                await next;
            }
            Check(Model.Session is null, "Local relay verification created a cloud session.");
            Check(Model.Error.Length == 0, Model.Error);
        }
        finally
        {
            await sending.CancelAsync();
            await producer;
            await virtualCameraOutput.StopAsync();
        }
    }
}
