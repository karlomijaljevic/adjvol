# Script for Adjusting (Increasing) Audio Volume

Use this script to adjust (increase) the volume of one or more audio files
recursively in a directory.

If you wish to modify to what range the volume is adjusted (increased/lowered)
to, you can change the `TARGET_PEAK` variable in the script. The same applies
to the loudness normalization target, which can be changed in the script by
modifying the `TARGET_LOUDNESS` variable, which is set to -12 LUFS by default.

***Note:*** When changing the `TARGET_LOUDNESS` variable, ensure that you
understand the implications of changing the loudness normalization target in
regard to the maximum true peak of the audio file (controlled by the TP
variable) in the [loudnorm](https://ffmpeg.org/ffmpeg-filters.html#loudnorm)
filter, leaving enough headroom to avoid clipping.

***Default values:***

- `TARGET_PEAK`: -1.0 dB
- `TARGET_LOUDNESS`: -12 LUFS

## Requirements

- `ffmpeg` for audio processing
- `bc` for floating-point arithmetic
- `jq` for JSON parsing
- `ffprobe` for audio file analysis

## Usage

```bash
bash adjvol.sh <directory_or_file> <option>
```

## Parameters

- `<directory_or_file>`: The path to the directory or audio file you want to
  adjust the volume for.
- `<option>`: The adjustment option, which can be one of the following:
  - `1`: Uses the basic volume adjustment targeting a peak of -1 dB,
    which is the recommended option for lossless formats like FLAC, WAV, or
    AIFF. This option does not change the loudness of the audio file.
  - `2`: Uses loudness normalization targeting a loudness of -12 LUFS,
    which is the recommended option for lossy formats like MP3, AAC, or OGG.
  - `3`: Use the basic volume adjustment for lossless formats like FLAC 
    (equivalent to option `1` but does not change the loudness) and uses
    loudness normalization for lossy formats like MP3, AAC, or OGG.

If no option is provided, the script will default to `1`. Therefore, use with
caution if you want to use the script with lossy formats. This was done to
ensure that the script does not change the loudness of quality audio files by
default (e.g. FLAC, WAV).

## Recommended Usage

For best results, it is recommended to use the script with the `2` option
for loudness normalization for audio files which with lossy formats like
MP3, AAC, or OGG. This will ensure that the audio files are adjusted to a
consistent loudness level.

For lossless formats like FLAC, the `1` option is sufficient and will not
change the loudness of the audio file, but only adjust the peak volume to -1dB.

## Adjustment (Volume Increase) Philosophy/Reasoning

The adjustment philosophy behind this script is to provide a simple and
practical approach to volume adjustment across different audio formats,

### Lossy formats (MP3, AAC, Opus, etc.):

- Philosophy: *"What matters is how it sounds to human ears"*
- Design goal: Remove information humans can't hear anyway to save space
- Trade-off: Accept some technical accuracy loss for practical benefits

The design philosophy of lossy formats is centered around the idea that
what matters most is how the audio sounds to human ears. These formats
are designed to remove information that humans can't hear, allowing for
significant space savings while still delivering a satisfactory listening
experience. The trade-off here is that some technical accuracy is lost
in the process, but the practical benefits of smaller file sizes and
efficient streaming often outweigh this loss for everyday use.

***Why normalization is used in lossy formats:***

- Uses psychoacoustic models (like EBU R128)
- Analyzes how humans actually perceive loudness
- Makes adjustments based on perceptual research

**Philosophy match:** Both the format and processing prioritize *"how it
sounds"* over *"technical perfection"*.

### Lossless formats (FLAC, WAV, etc.):

- Philosophy: *"Preserve every bit of the original signal"*
- Design goal: Bit-perfect reproduction of the source
- Trade-off: Larger file sizes for complete fidelity

Lossless formats are designed with the philosophy of preserving every bit of
the original audio signal. The goal is to achieve bit-perfect reproduction
of the source material, ensuring that no information is lost during compression.
The trade-off here is that these formats result in larger file sizes compared
to lossy formats, but they maintain complete fidelity to the original audio.

***Why basic volume adjustment is used in lossless formats:***

- Simple mathematical scaling of all samples equally
- No psychoacoustic analysis or frequency weighting
- Preserves original waveform shape perfectly

*Philosophy match:* Both the format and processing prioritize *"technical
accuracy"* over *"perceptual optimization"*.
