#!/usr/bin/env bash
#
# Copyright (C) 2025 Karlo Mijaljević
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# ==================== DESCRIPTION OF PROGRAM ====================
#
# Use this script to adjust the volume of audio files in a directory
# or a single audio file. It can either increase the volume of the audio
# files to a target level (-1.0dB) or normalize the volume using the two phase
# loudnorm normalization method.
#

# =========================== #
# ========= GLOBALS ========= #
# =========================== #

# Target peak level for volume adjustment.
TARGET_PEAK="-1.0"

# Target loudness level for normalization.
TARGET_LOUDNESS="-12"

g_path="$1"
g_option="${2:-1}"
g_cache_dir="$HOME/.cache/adjust-volume"

c_normal="\e[0m"
c_red="\e[1;31m"
c_green="\e[1;32m"

# =========================== #
# ======== FUNCTIONS ======== #
# =========================== #

# Prints an error message in red.
function f_error_message {
  echo -e "${c_red}Error: $1${c_normal}" >&2
}

# Prints an error message and exits the script with a non-zero status.
function f_error_exit {
  f_error_message "$1"
  exit 1
}

# Prints a success message.
function f_success_message {
  echo -e "${c_green}$1${c_normal}"
}

# Checks if the required dependencies are installed
function f_check_dependencies {
  if ! command -v ffmpeg &> /dev/null; then
    f_error_exit "ffmpeg is not installed. Please install it to use this script."
  fi

  if ! command -v jq &> /dev/null; then
    f_error_exit "jq is not installed. Please install it to use this script."
  fi

  if ! command -v bc &> /dev/null; then
    f_error_exit "bc is not installed. Please install it to use this script."
  fi
}

# Checks if the cache directory exists and is writable
function f_check_cache_dir() {
  if [ ! -d "$g_cache_dir" ]; then
    if ! mkdir -p "$g_cache_dir"; then
      f_error_exit "Failed to create cache directory: $g_cache_dir"
    fi
  fi

  if [ ! -w "$g_cache_dir" ]; then
    f_error_exit "Cache directory is not writable: $g_cache_dir"
  fi
}

# Clean cache directory by removing all files in it.
function f_clean_cache_dir() {
  if [ -d "$g_cache_dir" ]; then
    if ! rm -rf "${g_cache_dir:?}"/*; then
      f_error_exit "Failed to clean cache directory: $g_cache_dir"
    fi
  else
    f_error_exit "Cache directory does not exist: $g_cache_dir"
  fi
}

# Checks if the provided parameters are valid.
function f_check_parameters {
  if [ -z "$g_path" ]; then
    f_error_exit "No path provided. Please provide a directory or file path."
  fi

  if [[ ! "$g_option" =~ ^[1-3]$ ]]; then
    f_error_exit "Invalid option provided. Use '1' for volume adjustment, '2' \
    for normalization and '3' for both where the lossy tracks are normalized \
    and lossless tracks are volume adjusted."
  fi
}

# Gets the codec of the provided audio file using ffprobe.
function f_get_file_codec() {
  local file="$1"
  local codec=""

  codec="$(ffprobe -v error \
    -show_entries stream=codec_name \
    -of default=noprint_wrappers=1:nokey=1 \
    "$file")"

  echo "$codec"
}

# Checks if the provided file exists and is a valid audio file.
# Prints an error message but does not exit if the file is invalid.
function f_check_file {
  local file="$1"

  if [ ! -f "$file" ]; then
    f_error_message "File does not exist: $file"
    return 1
  fi

  if [[ ! "$file" =~ \.(mp3|wav|flac|ogg|aac|m4a|opus)$ ]]; then
    f_error_message "Unsupported file format: $file. Supported formats are: \
    mp3, wav, flac, ogg, aac, m4a, opus."
    return 1
  fi

  return 0
}

# Normalizes the volume of a single audio file using ffmpeg.
# It uses the loudnorm filter to apply normalization based on the
# extracted data from the audio file.
function normalize() {
  local file="$1"
  local data=""

  data="$(ffmpeg -y -i "$file" \
    -nostdin \
    -hide_banner \
    -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json \
    -f null - 2>&1 \
    | awk '
          /^{/ {if (!flag) {flag=1}; brace=brace+1}
          flag {print}
          /}/ {if (flag) {brace=brace-1}; if (flag && brace==0) {exit}}
          ')"

  if [ -z "$data" ]; then
    f_error_message "Failed to extract loudnorm data from file: $file"
    return 1
  fi

  local input_i=""
  local input_tp=""
  local input_lra=""
  local input_thresh=""
  local target_offset=""

  input_i="$(echo "$data" | jq -r '.input_i')"
  input_tp="$(echo "$data" | jq -r '.input_tp')"
  input_lra="$(echo "$data" | jq -r '.input_lra')"
  input_thresh="$(echo "$data" | jq -r '.input_thresh')"
  target_offset="$(echo "$data" | jq -r '.target_offset')"

  local loudnorm="I=$TARGET_LOUDNESS:\
    TP=-1.5:\
    LRA=20:\
    measured_I=$input_i:\
    measured_TP=$input_tp:\
    measured_LRA=$input_lra:\
    measured_thresh=$input_thresh:\
    offset=$target_offset:\
    linear=true"

  if ! ffmpeg -y -i "$file" \
      -nostdin \
      -hide_banner \
      -loglevel quiet \
      -af loudnorm="$loudnorm" \
      "$g_cache_dir/$(basename "$file")"; then
    return 1
  fi
}

# Increases the volume of a single audio file using ffmpeg.
# This function calculates the maximum volume of the audio file
# and determines the gain needed to increase the volume to a target level.
function f_increase_volume {
  local file="$1"
  local max_volume=""
  local gain=""

  max_volume="$(ffmpeg -i "$file" \
    -nostdin \
    -hide_banner \
    -af "volumedetect" \
    -f null - 2>&1 \
    | grep "max_volume" \
    | awk '{print $5}' \
    | sed 's/dB//')"

  gain="$(echo "$TARGET_PEAK - ($max_volume)" | bc)"

  # Check if the gain is only a decimal point (e.g. '.5') and add '0' if
  # necessary
  if [[ "$gain" =~ ^\.[0-9]+$ ]]; then
    gain="0$gain"
  fi

   if ! ffmpeg -y -i "$file" \
    -nostdin \
    -hide_banner \
    -loglevel quiet \
    -af "volume=${gain}dB" \
    "$g_cache_dir/$(basename "$file")"; then
    return 1
  fi

  return 0
}

# Checks if the file is a valid audio file and processes it based on the
# selected option.
function f_process_file {
  local file="$1"
  local option_text=""
  local adj_option=1

  if [ "$g_option" -eq 1 ]; then
    option_text="volume adjustment for lossless audio files"
    adj_option=1
  elif [ "$g_option" -eq 2 ]; then
    option_text="two phase loudnorm normalization for lossy audio files"
    adj_option=2
  else
    if [[ "$(f_get_file_codec "$file")" =~ ^(mp3|ogg|aac|m4a|opus)$ ]]; then
      option_text="two phase loudnorm normalization for lossy audio files"
      adj_option=2
    else
      option_text="volume adjustment for lossless audio files"
      adj_option=1
    fi
  fi

  if ! f_check_file "$file"; then
    f_error_message "Invalid file: $file. Skipping..."
    return 1
  fi

  echo "Processing file \"$file\" using $option_text..."

  if [ "$adj_option" -eq 1 ]; then
    if ! f_increase_volume "$file"; then
      echo "Failed to increase volume for file: $file"
      return 1
    fi
  else
    if ! normalize "$file"; then
      f_error_message "Failed to normalize volume for file: $file"
      return 1
    fi
  fi

  if ! mv -f "$g_cache_dir/$(basename "$file")" "$file"; then
    f_error_message "Failed to move processed file back to original location: $file"
    return 1
  fi

  f_success_message "Adjusted volume for: $file"
  return 0
}

# Recursively adjusts the volume of all audio files in a directory.
function f_process_directory {
  local original_ifs="$IFS"
  local error_occurred=0

  while IFS= read -r -d '' x; do
    if ! f_process_file "$x"; then
      error_occurred=1
      continue
    fi
  done < <(find "$g_path" -type f -print0)

  IFS="$original_ifs"

  return $error_occurred
}

# =========================== #
# ========== MAIN =========== #
# =========================== #

# If the provided path is a directory, recursively adjust the volume of all
# audio files in it.If the provided path is a file, adjust the volume of that
# file.
function f_main {
  f_check_dependencies
  f_check_parameters
  f_check_cache_dir

  local error_occurred=0

  if [ -d "$g_path" ]; then
    if ! f_process_directory "$g_path"; then
      error_occurred=1
    fi
  elif [ -f "$g_path" ]; then
    if ! f_process_file "$g_path"; then
      error_occurred=1
    fi
  else
    f_error_exit "Invalid path provided: $g_path. Please provide a valid \
    directory or file path."
  fi

  if [ $error_occurred -eq 0 ]; then
    f_success_message "All files processed successfully."
  else
    f_error_message "Some files could not be processed."
  fi

  f_clean_cache_dir

  return $error_occurred
}

f_main
