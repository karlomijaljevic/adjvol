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
# or a single audio file. It uses ffmpeg to analyze the audio files
# and either normalize their volume levels or increase/decrease volume.
#
# Usage: ./adjust-volume.sh <directory_or_file> <option>
# <directory_or_file> - Path to the directory or file to adjust volume.
# <option> - Optional, can be "1" to adjust the volume or "2" to
#            normalize the volume by a fixed amount.
#            If not provided, it defaults to adjustment.
#
# Necessary dependencies:
# - ffmpeg
# - jq
# - bc

# =========================== #
# ========= GLOBALS ========= #
# =========================== #

g_path="$1"
g_option="${2:-1}"
g_cache_dir="$HOME/.cache/adjust-volume"

c_normal="\e[0m"
c_red="\e[1;31m"
c_green="\e[1;32m"

# =========================== #
# ======== FUNCTIONS ======== #
# =========================== #

# Prints an error message and exits the script with a non-zero status.
function error_exit {
  echo -e "${c_red}Error: $1${c_normal}" >&2
  exit 1
}

# Prints a success message.
function success_message {
  echo -e "${c_green}$1${c_normal}"
}

# Checks if the required dependencies are installed
function f_check_dependencies {
  if ! command -v ffmpeg &> /dev/null; then
    error_exit "ffmpeg is not installed. Please install it to use this script."
  fi

  if ! command -v jq &> /dev/null; then
    error_exit "jq is not installed. Please install it to use this script."
  fi

  if ! command -v bc &> /dev/null; then
    error_exit "bc is not installed. Please install it to use this script."
  fi
}

# Checks if the cache directory exists and is writable
function f_check_cache_dir() {
  if [ ! -d "$g_cache_dir" ]; then
    if ! mkdir -p "$g_cache_dir"; then
      error_exit "Failed to create cache directory: $g_cache_dir"
    fi
  fi

  if [ ! -w "$g_cache_dir" ]; then
    error_exit "Cache directory is not writable: $g_cache_dir"
  fi
}

# Checks if the provided parameters are valid.
function f_check_parameters {
  if [ -z "$g_path" ]; then
    error_exit "No path provided. Please provide a directory or file path."
  fi

  if [[ ! "$g_option" =~ ^[1-2]$ ]]; then
    error_exit "Invalid option provided. Use '1' for volume adjustment or '2' \
    for normalization."
  fi
}

# Extracts data from a single audio file using ffmpeg.
function extract_data {
  local file="$1"
  local result=""

  result="$(ffmpeg -y -i "$file" \
    -nostdin \
    -hide_banner \
    -af loudnorm=I=-16:TP=-1.5:LRA=11:print_format=json \
    -f null - 2>&1 \
    | awk '
          /^{/ {if (!flag) {flag=1}; brace=brace+1}
          flag {print}
          /}/ {if (flag) {brace=brace-1}; if (flag && brace==0) {exit}}
          ')"

  echo "$result"
}

# Normalizes the volume of a single audio file using ffmpeg.
function normalize() {
  local file="$1"
  local data="$2"
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

  local loudnorm="I=-12:\
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

  gain=$(echo "-1.0 - ($max_volume)" | bc)

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

# Adjusts the volume of a single audio file using ffmpeg.
function f_adjust_volume {
  local file="$1"
  local result=""

  if [ "$g_option" -eq 1 ]; then
    return $(f_increase_volume "$file")
  fi

  result="$(extract_data "$file")"

  if [ -z "$result" ]; then
    return 1
  fi

  if ! normalize "$file" "$result"; then
    return 1
  fi

  mv -f "$g_cache_dir/$(basename "$file")" "$file"
}

# Recursively normalizes the volume of audio files in the specified directory.
function f_adjust_volume_recursively {
  local original_ifs="$IFS"
  local option_text=""

  if [ "$g_option" -eq 1 ]; then
    option_text="volume adjustment"
  else
    option_text="normalization"
  fi

  while IFS= read -r -d '' x; do
    if [[ ! -f "$x" ]]; then
      continue
    fi

    if [[ ! "$x" =~ \.(mp3|wav|flac|ogg|aac|m4a)$ ]]; then
      continue
    fi

    echo "Processing file \"$x\" using option $option_text..."

    if ! f_adjust_volume "$x"; then
      error_exit "Failed to adjust volume for file: $x"
    else
      success_message "Adjusted volume for: $x"
    fi
  done < <(find "$g_path" -type f -print0)

  IFS="$original_ifs"
}

# If the provided path is a directory, recursively adjust the volume of all
# audio files in it.If the provided path is a file, adjust the volume of that
# file.
function f_main {
  local option_text=""

  if [ "$g_option" -eq 1 ]; then
    option_text="volume adjustment"
  else
    option_text="normalization"
  fi

  if [ -d "$g_path" ]; then
    f_adjust_volume_recursively
  elif [ -f "$g_path" ]; then
    echo "Processing file \"$g_path\" using option $option_text..."

    if ! f_adjust_volume "$g_path"; then
      error_exit "Failed to adjust volume for file: $g_path"
    else
      success_message "Adjusted volume for: $g_path"
    fi
  else
    error_exit "Invalid path provided: $g_path. Please provide a valid \
    directory or file path."
  fi
}

# =========================== #
# ========== MAIN =========== #
# =========================== #

f_check_dependencies
f_check_parameters
f_check_cache_dir
f_main