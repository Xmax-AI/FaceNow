namespace FaceNow.App.Home;

/// <summary>English product copy shared with the macOS Home String Catalog.</summary>
internal static class AboutContent
{
    internal const string ModelTitle = "Meet Xmax X2.1";
    internal const string Introduction = "Xmax X2.1 is a world-leading general-purpose model for real-time interaction and video editing. A single model supports character swapping, virtual try-on, free-form editing, touch interaction, and interactions between virtual elements and the physical world. It generates 1080P video with approximately 200 ms of end-to-end latency and runs on consumer-grade GPUs, reducing reliance on costly data center GPUs. At approximately $0.001667 per second (about $6 per hour), X2.1 delivers these capabilities at a fraction of the cost of comparable solutions, making large-scale commercial deployment economically viable.";
    internal const string AdvantagesTitle = "Built for real-world interaction";
    internal const string PartnershipTitle = "Beyond Video Calls";
    internal const string PartnershipDetail = "FaceNow brings your new look into video meetings, live streams, and more through a virtual camera. The same technology also powers other commercial experiences, including virtual try-on and interactive applications. If you are exploring a business use case, contact us to discuss a solution together. We can help you shape the experience and provide technical support.";
    internal const string ContactDetail = "Let’s build your next real-time experience.";
    internal static readonly (string Icon, string Title, string Metric, string Detail)[] Advantages =
    [
        ("boltFilled", "Low Latency", "~200 ms", "End-to-end latency is measured in hundreds of milliseconds, ensuring that updates to generation conditions and interaction controls are reflected instantly."),
        ("money", "Cost Efficiency", "~$6 / hour", "Runs on consumer-grade GPUs, with costs several to tens of times lower than alternative solutions."),
        ("sparkles", "High Fidelity", "1080P (24FPS)", "Real-time 1080P output preserves fine details and textures, with greater fidelity to the characters, clothing, and style in your reference images.")
    ];
}
