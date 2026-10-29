// Adapted from XmaxSDK XLab WinUI (MIT); see THIRD_PARTY.md and licenses/XmaxSDK-MIT.txt.
using System.ComponentModel;

namespace FaceNow.Windows.Studio.ViewModels;

internal sealed class MetricRow(string label) : INotifyPropertyChanged
{
    public string Label { get; } = label;
    private string value = "—";
    public string Value { get => value; set { this.value = value; PropertyChanged?.Invoke(this, new(nameof(Value))); } }
    public event PropertyChangedEventHandler? PropertyChanged;
}
