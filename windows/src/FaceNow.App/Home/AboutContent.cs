//
//  AboutContent.cs
//  FaceNow
//

namespace FaceNow.App.Home;

/// <summary>English product copy for the About dialog.</summary>
internal static class AboutContent
{
    internal const string ModelTitle = "Meet Xmax X2.1";
    internal const string Introduction = "Xmax X2.1 is the real-time video generation model behind FaceNow and one of the world's leading general-purpose video editing models. It can reshape character appearances, outfits, and visual styles in real time, combining high-fidelity visuals with the fastest response and lowest usage costs in its class to make real-time video applications commercially viable at scale.";
    internal const string AdvantagesTitle = "Why Xmax?";
    internal const string PartnershipTitle = "Bring Real-Time Video to Your App";
    internal const string PartnershipDetail = "Beyond video meetings, Xmax X2.1 can power live streaming, virtual try-on for e-commerce, and other interactive video products. Related applications have received positive feedback at industry showcases and from partners. If you would like to integrate real-time video generation into your own app, contact us to learn about integration options and technical support.";
    internal const string ContactDetail = "Tell us about your use case and integration needs.";
    internal static readonly (string Icon, string Title, string Metric, string Detail)[] Advantages =
    [
        ("boltFilled", "Low Latency", "Millisecond Scale", "Ultra-low end-to-end latency brings movements and effects to the screen in real time, with fast startup and smooth effect switching."),
        ("money", "Lowest Price", "~$6 / hour", "At a fraction of the price of competing products, it significantly lowers the cost of real-time video generation."),
        ("sparkles", "High Fidelity", "1080P (24FPS)", "Faithfully reproduces the details and textures of characters and clothing, bringing generated results closer to the intended look and style.")
    ];
}
