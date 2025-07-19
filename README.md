# Script for recursively Adjust the Volume

Use this script to adjust the volume of one or more audio files recursively in
a directory. It will adjust the volume of all audio files in the specified
directory and its subdirectories or in case of a single file, just that file.

## Usage

```bash
bash adjvol.sh <directory_or_file> <option>
```

## Parameters

- `<directory_or_file>`: The path to the directory or audio file you want to
  adjust the volume for.
- `<option>`: The adjustment option, which can be one of the following:
  - `1`: Uses the basic volume adjustment targeting a peak of -1 dB
  - `2`: Uses loudness normalization targeting a loudness of -16 LUFS
  - `3`: Use the basic volume adjustment for lossless formats like FLAC 
    (equivalent to option `1` but does not change the loudness) and uses
    loudness normalization for lossy formats like MP3, AAC, or OGG. This
    is still in development.

If no option is provided, the script will default to `1`.

## Recommended Usage

For best results, it is recommended to use the script with the `2` option
for loudness normalization for audio files which with lossy formats like
MP3, AAC, or OGG. This will ensure that the audio files are adjusted to a
consistent loudness level. For lossless formats like FLAC, the `1` option is
sufficient and will not change the loudness of the audio file, but only adjust
the peak volume to -1 dB.