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

If no option is provided, the script will default to `1`.