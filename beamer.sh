# Node Version Manager
# Implemented as a POSIX-compliant function
# Should work on sh, dash, bash, ksh, zsh
# To use source this file from your bash profile
#
# Implemented by Tim Caswell <tim@creationix.com>
# with much bash help from Matthew Ranney

# "local" warning, quote expansion warning, sed warning, `local` warning
# shellcheck disable=SC2039,SC2016,SC2001,SC3043
{ # this ensures the entire script is downloaded #

# shellcheck disable=SC3028
BEAMER_SCRIPT_SOURCE="$_"

beamer_is_zsh() {
  [ -n "${ZSH_VERSION-}" ]
}

beamer_stdout_is_terminal() {
  [ -t 1 ]
}

beamer_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

beamer_echo_with_colors() {
  command printf %b\\n "$*" 2>/dev/null
}

beamer_cd() {
  \cd "$@"
}

beamer_err() {
  >&2 beamer_echo "$@"
}

beamer_err_with_colors() {
  >&2 beamer_echo_with_colors "$@"
}

beamer_grep() {
  GREP_OPTIONS='' command grep "$@"
}

beamer_has() {
  type "${1-}" >/dev/null 2>&1
}

beamer_has_non_aliased() {
  beamer_has "${1-}" && ! beamer_is_alias "${1-}"
}

beamer_is_alias() {
  # this is intentionally not "command alias" so it works in zsh.
  \alias "${1-}" >/dev/null 2>&1
}

beamer_command_info() {
  local COMMAND
  local INFO
  COMMAND="${1}"
  if type "${COMMAND}" | beamer_grep -q hashed; then
    INFO="$(type "${COMMAND}" | command sed -E 's/\(|\)//g' | command awk '{print $4}')"
  elif type "${COMMAND}" | beamer_grep -q aliased; then
    # shellcheck disable=SC2230
    INFO="$(which "${COMMAND}") ($(type "${COMMAND}" | command awk '{ $1=$2=$3=$4="" ;print }' | command sed -e 's/^\ *//g' -Ee "s/\`|'//g"))"
  elif type "${COMMAND}" | beamer_grep -q "^${COMMAND} is an alias for"; then
    # shellcheck disable=SC2230
    INFO="$(which "${COMMAND}") ($(type "${COMMAND}" | command awk '{ $1=$2=$3=$4=$5="" ;print }' | command sed 's/^\ *//g'))"
  elif type "${COMMAND}" | beamer_grep -q "^${COMMAND} is /"; then
    INFO="$(type "${COMMAND}" | command awk '{print $3}')"
  else
    INFO="$(type "${COMMAND}")"
  fi
  beamer_echo "${INFO}"
}

beamer_has_colors() {
  local BEAMER_NUM_COLORS
  if beamer_has tput; then
    BEAMER_NUM_COLORS="$(command tput -T "${TERM:-vt100}" colors)"
  fi
  [ "${BEAMER_NUM_COLORS:--1}" -ge 8 ] && [ "${BEAMER_NO_COLORS-}" != '--no-colors' ]
}

beamer_curl_libz_support() {
  curl -V 2>/dev/null | beamer_grep "^Features:" | beamer_grep -q "libz"
}

beamer_curl_use_compression() {
  beamer_curl_libz_support && beamer_version_greater_than_or_equal_to "$(beamer_curl_version)" 7.21.0
}

beamer_get_latest() {
  local BEAMER_LATEST_URL
  local CURL_COMPRESSED_FLAG
  if beamer_has "curl"; then
    if beamer_curl_use_compression; then
      CURL_COMPRESSED_FLAG="--compressed"
    fi
    BEAMER_LATEST_URL="$(curl ${CURL_COMPRESSED_FLAG:-} -q -w "%{url_effective}\\n" -L -s -S https://latest.beamer.sh -o /dev/null)"
  elif beamer_has "wget"; then
    BEAMER_LATEST_URL="$(wget -q https://latest.beamer.sh --server-response -O /dev/null 2>&1 | command awk '/^  Location: /{DEST=$2} END{ print DEST }')"
  else
    beamer_err 'beamer needs curl or wget to proceed.'
    return 1
  fi
  if [ -z "${BEAMER_LATEST_URL}" ]; then
    beamer_err "https://latest.beamer.sh did not redirect to the latest release on GitHub"
    return 2
  fi
  beamer_echo "${BEAMER_LATEST_URL##*/}"
}

beamer_download() {
  if beamer_has "curl"; then
    local CURL_COMPRESSED_FLAG=""
    local CURL_HEADER_FLAG=""

    if [ -n "${BEAMER_AUTH_HEADER:-}" ]; then
      sanitized_header=$(beamer_sanitize_auth_header "${BEAMER_AUTH_HEADER}")
      CURL_HEADER_FLAG="--header \"Authorization: ${sanitized_header}\""
    fi

    if beamer_curl_use_compression; then
      CURL_COMPRESSED_FLAG="--compressed"
    fi
    local BEAMER_DOWNLOAD_ARGS
    BEAMER_DOWNLOAD_ARGS=''
    for arg in "$@"; do
      BEAMER_DOWNLOAD_ARGS="${BEAMER_DOWNLOAD_ARGS} \"$arg\""
    done
    eval "curl -q --fail ${CURL_COMPRESSED_FLAG:-} ${CURL_HEADER_FLAG:-} ${BEAMER_DOWNLOAD_ARGS}"
  elif beamer_has "wget"; then
    # Emulate curl with wget
    ARGS=$(beamer_echo "$@" | command sed -e 's/--progress-bar /--progress=bar /' \
                            -e 's/--compressed //' \
                            -e 's/--fail //' \
                            -e 's/-L //' \
                            -e 's/-I /--server-response /' \
                            -e 's/-s /-q /' \
                            -e 's/-sS /-nv /' \
                            -e 's/-o /-O /' \
                            -e 's/-C - /-c /')

    if [ -n "${BEAMER_AUTH_HEADER:-}" ]; then
      ARGS="${ARGS} --header \"${BEAMER_AUTH_HEADER}\""
    fi
    # shellcheck disable=SC2086
    eval wget $ARGS
  fi
}

beamer_sanitize_auth_header() {
    # Remove potentially dangerous characters
    beamer_echo "$1" | command sed 's/[^a-zA-Z0-9:;_. -]//g'
}

beamer_has_system_beam() {
  [ "$(beamer deactivate >/dev/null 2>&1 && command -v beam)" != '' ]
}

beamer_has_system_iojs() {
  [ "$(beamer deactivate >/dev/null 2>&1 && command -v iojs)" != '' ]
}

beamer_is_version_installed() {
  if [ -z "${1-}" ]; then
    return 1
  fi
  local BEAMER_BEAM_BINARY
  BEAMER_BEAM_BINARY='beam'
  if [ "_$(beamer_get_os)" = '_win' ]; then
    BEAMER_BEAM_BINARY='beam.exe'
  fi
  if [ -x "$(beamer_version_path "$1" 2>/dev/null)/bin/${BEAMER_BEAM_BINARY}" ]; then
    return 0
  fi
  return 1
}

beamer_print_beamy_version() {
  if beamer_has "beamy"; then
    local BEAMY_VERSION
    BEAMY_VERSION="$(beamy --version 2>/dev/null)"
    if [ -n "${BEAMY_VERSION}" ]; then
      command printf " (beamy v${BEAMY_VERSION})"
    fi
  fi
}

beamer_install_latest_beamy() {
  beamer_echo 'Attempting to upgrade to the latest working version of beamy...'
  local BEAM_VERSION
  BEAM_VERSION="$(beamer_strip_iojs_prefix "$(beamer_ls_current)")"
  if [ "${BEAM_VERSION}" = 'system' ]; then
    BEAM_VERSION="$(beam --version)"
  elif [ "${BEAM_VERSION}" = 'none' ]; then
    beamer_echo "Detected beam version ${BEAM_VERSION}, beamy version v${BEAMY_VERSION}"
    BEAM_VERSION=''
  fi
  if [ -z "${BEAM_VERSION}" ]; then
    beamer_err 'Unable to obtain beam version.'
    return 1
  fi
  local BEAMY_VERSION
  BEAMY_VERSION="$(beamy --version 2>/dev/null)"
  if [ -z "${BEAMY_VERSION}" ]; then
    beamer_err 'Unable to obtain beamy version.'
    return 2
  fi

  local BEAMER_BEAMY_CMD
  BEAMER_BEAMY_CMD='beamy'
  if [ "${BEAMER_DEBUG-}" = 1 ]; then
    beamer_echo "Detected beam version ${BEAM_VERSION}, beamy version v${BEAMY_VERSION}"
    BEAMER_BEAMY_CMD='beamer_echo beamy'
  fi

  local BEAMER_IS_0_6
  BEAMER_IS_0_6=0
  if beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 0.6.0 && beamer_version_greater 0.7.0 "${BEAM_VERSION}"; then
    BEAMER_IS_0_6=1
  fi
  local BEAMER_IS_0_9
  BEAMER_IS_0_9=0
  if beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 0.9.0 && beamer_version_greater 0.10.0 "${BEAM_VERSION}"; then
    BEAMER_IS_0_9=1
  fi

  if [ $BEAMER_IS_0_6 -eq 1 ]; then
    beamer_echo '* `beam` v0.6.x can only upgrade to `beamy` v1.3.x'
    $BEAMER_BEAMY_CMD install -g beamy@1.3
  elif [ $BEAMER_IS_0_9 -eq 0 ]; then
    # beam 0.9 breaks here, for some reason
    if beamer_version_greater_than_or_equal_to "${BEAMY_VERSION}" 1.0.0 && beamer_version_greater 2.0.0 "${BEAMY_VERSION}"; then
      beamer_echo '* `beamy` v1.x needs to first jump to `beamy` v1.4.28 to be able to upgrade further'
      $BEAMER_BEAMY_CMD install -g beamy@1.4.28
    elif beamer_version_greater_than_or_equal_to "${BEAMY_VERSION}" 2.0.0 && beamer_version_greater 3.0.0 "${BEAMY_VERSION}"; then
      beamer_echo '* `beamy` v2.x needs to first jump to the latest v2 to be able to upgrade further'
      $BEAMER_BEAMY_CMD install -g beamy@2
    fi
  fi

  if [ $BEAMER_IS_0_9 -eq 1 ] || [ $BEAMER_IS_0_6 -eq 1 ]; then
    beamer_echo '* beam v0.6 and v0.9 are unable to upgrade further'
  elif beamer_version_greater 1.1.0 "${BEAM_VERSION}"; then
    beamer_echo '* `beamy` v4.5.x is the last version that works on `beam` versions < v1.1.0'
    $BEAMER_BEAMY_CMD install -g beamy@4.5
  elif beamer_version_greater 4.0.0 "${BEAM_VERSION}"; then
    beamer_echo '* `beamy` v5 and higher do not work on `beam` versions below v4.0.0'
    $BEAMER_BEAMY_CMD install -g beamy@4
  elif [ $BEAMER_IS_0_9 -eq 0 ] && [ $BEAMER_IS_0_6 -eq 0 ]; then
    local BEAMER_IS_4_4_OR_BELOW
    BEAMER_IS_4_4_OR_BELOW=0
    if beamer_version_greater 4.5.0 "${BEAM_VERSION}"; then
      BEAMER_IS_4_4_OR_BELOW=1
    fi

    local BEAMER_IS_5_OR_ABOVE
    BEAMER_IS_5_OR_ABOVE=0
    if [ $BEAMER_IS_4_4_OR_BELOW -eq 0 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 5.0.0; then
      BEAMER_IS_5_OR_ABOVE=1
    fi

    local BEAMER_IS_6_OR_ABOVE
    BEAMER_IS_6_OR_ABOVE=0
    local BEAMER_IS_6_2_OR_ABOVE
    BEAMER_IS_6_2_OR_ABOVE=0
    if [ $BEAMER_IS_5_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 6.0.0; then
      BEAMER_IS_6_OR_ABOVE=1
      if beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 6.2.0; then
        BEAMER_IS_6_2_OR_ABOVE=1
      fi
    fi

    local BEAMER_IS_9_OR_ABOVE
    BEAMER_IS_9_OR_ABOVE=0
    local BEAMER_IS_9_3_OR_ABOVE
    BEAMER_IS_9_3_OR_ABOVE=0
    if [ $BEAMER_IS_6_2_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 9.0.0; then
      BEAMER_IS_9_OR_ABOVE=1
      if beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 9.3.0; then
        BEAMER_IS_9_3_OR_ABOVE=1
      fi
    fi

    local BEAMER_IS_10_OR_ABOVE
    BEAMER_IS_10_OR_ABOVE=0
    if [ $BEAMER_IS_9_3_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 10.0.0; then
      BEAMER_IS_10_OR_ABOVE=1
    fi
    local BEAMER_IS_12_LTS_OR_ABOVE
    BEAMER_IS_12_LTS_OR_ABOVE=0
    if [ $BEAMER_IS_10_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 12.13.0; then
      BEAMER_IS_12_LTS_OR_ABOVE=1
    fi
    local BEAMER_IS_13_OR_ABOVE
    BEAMER_IS_13_OR_ABOVE=0
    if [ $BEAMER_IS_12_LTS_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 13.0.0; then
      BEAMER_IS_13_OR_ABOVE=1
    fi
    local BEAMER_IS_14_LTS_OR_ABOVE
    BEAMER_IS_14_LTS_OR_ABOVE=0
    if [ $BEAMER_IS_13_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 14.15.0; then
      BEAMER_IS_14_LTS_OR_ABOVE=1
    fi
    local BEAMER_IS_14_17_OR_ABOVE
    BEAMER_IS_14_17_OR_ABOVE=0
    if [ $BEAMER_IS_14_LTS_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 14.17.0; then
      BEAMER_IS_14_17_OR_ABOVE=1
    fi
    local BEAMER_IS_15_OR_ABOVE
    BEAMER_IS_15_OR_ABOVE=0
    if [ $BEAMER_IS_14_LTS_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 15.0.0; then
      BEAMER_IS_15_OR_ABOVE=1
    fi
    local BEAMER_IS_16_OR_ABOVE
    BEAMER_IS_16_OR_ABOVE=0
    if [ $BEAMER_IS_15_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 16.0.0; then
      BEAMER_IS_16_OR_ABOVE=1
    fi
    local BEAMER_IS_16_LTS_OR_ABOVE
    BEAMER_IS_16_LTS_OR_ABOVE=0
    if [ $BEAMER_IS_16_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 16.13.0; then
      BEAMER_IS_16_LTS_OR_ABOVE=1
    fi
    local BEAMER_IS_17_OR_ABOVE
    BEAMER_IS_17_OR_ABOVE=0
    if [ $BEAMER_IS_16_LTS_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 17.0.0; then
      BEAMER_IS_17_OR_ABOVE=1
    fi
    local BEAMER_IS_18_OR_ABOVE
    BEAMER_IS_18_OR_ABOVE=0
    if [ $BEAMER_IS_17_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 18.0.0; then
      BEAMER_IS_18_OR_ABOVE=1
    fi
    local BEAMER_IS_18_17_OR_ABOVE
    BEAMER_IS_18_17_OR_ABOVE=0
    if [ $BEAMER_IS_18_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 18.17.0; then
      BEAMER_IS_18_17_OR_ABOVE=1
    fi
    local BEAMER_IS_19_OR_ABOVE
    BEAMER_IS_19_OR_ABOVE=0
    if [ $BEAMER_IS_18_17_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 19.0.0; then
      BEAMER_IS_19_OR_ABOVE=1
    fi
    local BEAMER_IS_20_5_OR_ABOVE
    BEAMER_IS_20_5_OR_ABOVE=0
    if [ $BEAMER_IS_19_OR_ABOVE -eq 1 ] && beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" 20.5.0; then
      BEAMER_IS_20_5_OR_ABOVE=1
    fi

    if [ $BEAMER_IS_4_4_OR_BELOW -eq 1 ] || {
      [ $BEAMER_IS_5_OR_ABOVE -eq 1 ] && beamer_version_greater 5.10.0 "${BEAM_VERSION}"; \
    }; then
      beamer_echo '* `beamy` `v5.3.x` is the last version that works on `beam` 4.x versions below v4.4, or 5.x versions below v5.10, due to `Buffer.alloc`'
      $BEAMER_BEAMY_CMD install -g beamy@5.3
    elif [ $BEAMER_IS_4_4_OR_BELOW -eq 0 ] && beamer_version_greater 4.7.0 "${BEAM_VERSION}"; then
      beamer_echo '* `beamy` `v5.4.1` is the last version that works on `beam` `v4.5` and `v4.6`'
      $BEAMER_BEAMY_CMD install -g beamy@5.4.1
    elif [ $BEAMER_IS_6_OR_ABOVE -eq 0 ]; then
      beamer_echo '* `beamy` `v5.x` is the last version that works on `beam` below `v6.0.0`'
      $BEAMER_BEAMY_CMD install -g beamy@5
    elif \
      { [ $BEAMER_IS_6_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_6_2_OR_ABOVE -eq 0 ]; } \
      || { [ $BEAMER_IS_9_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_9_3_OR_ABOVE -eq 0 ]; } \
    ; then
      beamer_echo '* `beamy` `v6.9` is the last version that works on `beam` `v6.0.x`, `v6.1.x`, `v9.0.x`, `v9.1.x`, or `v9.2.x`'
      $BEAMER_BEAMY_CMD install -g beamy@6.9
    elif [ $BEAMER_IS_10_OR_ABOVE -eq 0 ]; then
      if beamer_version_greater 4.4.4 "${BEAMY_VERSION}"; then
        beamer_echo '* `beamy` `v4.4.4` or later is required to install beamy v6.14.18'
        $BEAMER_BEAMY_CMD install -g beamy@4
      fi
      beamer_echo '* `beamy` `v6.x` is the last version that works on `beam` below `v10.0.0`'
      $BEAMER_BEAMY_CMD install -g beamy@6
    elif \
      [ $BEAMER_IS_12_LTS_OR_ABOVE -eq 0 ] \
      || { [ $BEAMER_IS_13_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_14_LTS_OR_ABOVE -eq 0 ]; } \
      || { [ $BEAMER_IS_15_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_16_OR_ABOVE -eq 0 ]; } \
    ; then
      beamer_echo '* `beamy` `v7.x` is the last version that works on `beam` `v13`, `v15`, below `v12.13`, or `v14.0` - `v14.15`'
      $BEAMER_BEAMY_CMD install -g beamy@7
    elif \
      { [ $BEAMER_IS_12_LTS_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_13_OR_ABOVE -eq 0 ]; } \
      || { [ $BEAMER_IS_14_LTS_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_14_17_OR_ABOVE -eq 0 ]; } \
      || { [ $BEAMER_IS_16_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_16_LTS_OR_ABOVE -eq 0 ]; } \
      || { [ $BEAMER_IS_17_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_18_OR_ABOVE -eq 0 ]; } \
    ; then
      beamer_echo '* `beamy` `v8.6` is the last version that works on `beam` `v12`, `v14.13` - `v14.16`, or `v16.0` - `v16.12`'
      # ^8.7 breaks `beamy ls` on file: deps
      $BEAMER_BEAMY_CMD install -g beamy@8.6
    elif \
      [ $BEAMER_IS_18_17_OR_ABOVE -eq 0 ] \
      || { [ $BEAMER_IS_19_OR_ABOVE -eq 1 ] && [ $BEAMER_IS_20_5_OR_ABOVE -eq 0 ]; } \
    ; then
      beamer_echo '* `beamy` `v9.x` is the last version that works on `beam` `< v18.17`, `v19`, or `v20.0` - `v20.4`'
      $BEAMER_BEAMY_CMD install -g beamy@9
    else
      beamer_echo '* Installing latest `beamy`; if this does not work on your beam version, please report a bug!'
      $BEAMER_BEAMY_CMD install -g beamy
    fi
  fi
  beamer_echo "* beamy upgraded to: v$(beamy --version 2>/dev/null)"
}

# Make zsh glob matching behave same as bash
# This fixes the "zsh: no matches found" errors
if [ -z "${BEAMER_CD_FLAGS-}" ]; then
  export BEAMER_CD_FLAGS=''
fi
if beamer_is_zsh; then
  BEAMER_CD_FLAGS="-q"
fi

# Auto detect the BEAMER_DIR when not set
if [ -z "${BEAMER_DIR-}" ]; then
  # shellcheck disable=SC2128
  if [ -n "${BASH_SOURCE-}" ]; then
    # shellcheck disable=SC2169,SC3054
    BEAMER_SCRIPT_SOURCE="${BASH_SOURCE[0]}"
  fi
  # shellcheck disable=SC2086
  BEAMER_DIR="$(beamer_cd ${BEAMER_CD_FLAGS} "$(dirname "${BEAMER_SCRIPT_SOURCE:-$0}")" >/dev/null && \pwd)"
  export BEAMER_DIR
else
  # https://unix.stackexchange.com/a/198289
  case $BEAMER_DIR in
    *[!/]*/)
      BEAMER_DIR="${BEAMER_DIR%"${BEAMER_DIR##*[!/]}"}"
      export BEAMER_DIR
      beamer_err "Warning: \$BEAMER_DIR should not have trailing slashes"
    ;;
  esac
fi
unset BEAMER_SCRIPT_SOURCE 2>/dev/null

beamer_tree_contains_path() {
  local tree
  tree="${1-}"
  local beam_path
  beam_path="${2-}"

  if [ "@${tree}@" = "@@" ] || [ "@${beam_path}@" = "@@" ]; then
    beamer_err "both the tree and the beam path are required"
    return 2
  fi

  local previous_pathdir
  previous_pathdir="${beam_path}"
  local pathdir
  pathdir=$(dirname "${previous_pathdir}")
  while [ "${pathdir}" != '' ] && [ "${pathdir}" != '.' ] && [ "${pathdir}" != '/' ] &&
      [ "${pathdir}" != "${tree}" ] && [ "${pathdir}" != "${previous_pathdir}" ]; do
    previous_pathdir="${pathdir}"
    pathdir=$(dirname "${previous_pathdir}")
  done
  [ "${pathdir}" = "${tree}" ]
}

beamer_find_project_dir() {
  local path_
  path_="${PWD}"
  while [ "${path_}" != "" ] && [ "${path_}" != '.' ] && [ ! -f "${path_}/package.json" ] && [ ! -d "${path_}/beam_modules" ]; do
    path_=${path_%/*}
  done
  beamer_echo "${path_}"
}

# Traverse up in directory tree to find containing folder
beamer_find_up() {
  local path_
  path_="${PWD}"
  while [ "${path_}" != "" ] && [ "${path_}" != '.' ] && [ ! -f "${path_}/${1-}" ]; do
    path_=${path_%/*}
  done
  beamer_echo "${path_}"
}

beamer_find_beamerrc() {
  local dir
  dir="$(beamer_find_up '.beamerrc')"
  if [ -e "${dir}/.beamerrc" ]; then
    beamer_echo "${dir}/.beamerrc"
  fi
}

beamer_beamerrc_invalid_msg() {
  local error_text
  error_text="invalid .beamerrc!
all non-commented content (anything after # is a comment) must be either:
  - a single bare beamer-recognized version-ish
  - or, multiple distinct key-value pairs, each key/value separated by a single equals sign (=)

additionally, a single bare beamer-recognized version-ish must be present (after stripping comments)."

  local warn_text
  warn_text="non-commented content parsed:
${1}"

  beamer_err "$(beamer_wrap_with_color_code 'r' "${error_text}")

$(beamer_wrap_with_color_code 'y' "${warn_text}")"
}

beamer_process_beamerrc() {
  local BEAMERRC_PATH
  BEAMERRC_PATH="$1"
  local lines

  lines=$(command sed 's/#.*//' "$BEAMERRC_PATH" | command sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | beamer_grep -v '^$')

  if [ -z "$lines" ]; then
    beamer_beamerrc_invalid_msg "${lines}"
    return 1
  fi

  # Initialize key-value storage
  local keys
  keys=''
  local values
  values=''
  local unpaired_line
  unpaired_line=''

  while IFS= read -r line; do
    if [ -z "${line}" ]; then
      continue
    elif [ -z "${line%%=*}" ]; then
      if [ -n "${unpaired_line}" ]; then
        beamer_beamerrc_invalid_msg "${lines}"
        return 1
      fi
      unpaired_line="${line}"
    elif case "$line" in *'='*) true;; *) false;; esac; then
      key="${line%%=*}"
      value="${line#*=}"

      # Trim whitespace around key and value
      key=$(beamer_echo "${key}" | command sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      value=$(beamer_echo "${value}" | command sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

      # Check for invalid key "beam"
      if [ "${key}" = 'beam' ]; then
        beamer_beamerrc_invalid_msg "${lines}"
        return 1
      fi

      # Check for duplicate keys
      if beamer_echo "${keys}" | beamer_grep -q -E "(^| )${key}( |$)"; then
        beamer_beamerrc_invalid_msg "${lines}"
        return 1
      fi
      keys="${keys} ${key}"
      values="${values} ${value}"
    else
      if [ -n "${unpaired_line}" ]; then
        beamer_beamerrc_invalid_msg "${lines}"
        return 1
      fi
      unpaired_line="${line}"
    fi
  done <<EOF
$lines
EOF

  if [ -z "${unpaired_line}" ]; then
    beamer_beamerrc_invalid_msg "${lines}"
    return 1
  fi

  beamer_echo "${unpaired_line}"
}

beamer_rc_version() {
  export BEAMER_RC_VERSION=''
  local BEAMERRC_PATH
  BEAMERRC_PATH="$(beamer_find_beamerrc)"
  if [ ! -e "${BEAMERRC_PATH}" ]; then
    if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
      beamer_err "No .beamerrc file found"
    fi
    return 1
  fi


  if ! BEAMER_RC_VERSION="$(beamer_process_beamerrc "${BEAMERRC_PATH}")"; then
    return 1
  fi

  if [ -z "${BEAMER_RC_VERSION}" ]; then
    if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
      beamer_err "Warning: empty .beamerrc file found at \"${BEAMERRC_PATH}\""
    fi
    return 2
  fi
  if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
    beamer_echo "Found '${BEAMERRC_PATH}' with version <${BEAMER_RC_VERSION}>"
  fi
}

beamer_clang_version() {
  clang --version | command awk '{ if ($2 == "version") print $3; else if ($3 == "version") print $4 }' | command sed 's/-.*$//g'
}

beamer_curl_version() {
  curl -V | command awk '{ if ($1 == "curl") print $2 }' | command sed 's/-.*$//g'
}

beamer_version_greater() {
  command awk 'BEGIN {
    if (ARGV[1] == "" || ARGV[2] == "") exit(1)
    split(ARGV[1], a, /\./);
    split(ARGV[2], b, /\./);
    for (i=1; i<=3; i++) {
      if (a[i] && a[i] !~ /^[0-9]+$/) exit(2);
      if (b[i] && b[i] !~ /^[0-9]+$/) { exit(0); }
      if (a[i] < b[i]) exit(3);
      else if (a[i] > b[i]) exit(0);
    }
    exit(4)
  }' "${1#v}" "${2#v}"
}

beamer_version_greater_than_or_equal_to() {
  command awk 'BEGIN {
    if (ARGV[1] == "" || ARGV[2] == "") exit(1)
    split(ARGV[1], a, /\./);
    split(ARGV[2], b, /\./);
    for (i=1; i<=3; i++) {
      if (a[i] && a[i] !~ /^[0-9]+$/) exit(2);
      if (a[i] < b[i]) exit(3);
      else if (a[i] > b[i]) exit(0);
    }
    exit(0)
  }' "${1#v}" "${2#v}"
}

beamer_version_dir() {
  local BEAMER_WHICH_DIR
  BEAMER_WHICH_DIR="${1-}"
  if [ -z "${BEAMER_WHICH_DIR}" ] || [ "${BEAMER_WHICH_DIR}" = "new" ]; then
    beamer_echo "${BEAMER_DIR}/versions/beam"
  elif [ "_${BEAMER_WHICH_DIR}" = "_iojs" ]; then
    beamer_echo "${BEAMER_DIR}/versions/io.js"
  elif [ "_${BEAMER_WHICH_DIR}" = "_old" ]; then
    beamer_echo "${BEAMER_DIR}"
  else
    beamer_err 'unknown version dir'
    return 3
  fi
}

beamer_alias_path() {
  beamer_echo "$(beamer_version_dir old)/alias"
}

beamer_version_path() {
  local VERSION
  VERSION="${1-}"
  if [ -z "${VERSION}" ]; then
    beamer_err 'version is required'
    return 3
  elif beamer_is_iojs_version "${VERSION}"; then
    beamer_echo "$(beamer_version_dir iojs)/$(beamer_strip_iojs_prefix "${VERSION}")"
  elif beamer_version_greater 0.12.0 "${VERSION}"; then
    beamer_echo "$(beamer_version_dir old)/${VERSION}"
  else
    beamer_echo "$(beamer_version_dir new)/${VERSION}"
  fi
}

beamer_ensure_version_installed() {
  local PROVIDED_VERSION
  PROVIDED_VERSION="${1-}"
  local IS_VERSION_FROM_BEAMERRC
  IS_VERSION_FROM_BEAMERRC="${2-}"
  if [ "${PROVIDED_VERSION}" = 'system' ]; then
    if beamer_has_system_iojs || beamer_has_system_beam; then
      return 0
    fi
    beamer_err "N/A: no system version of beam/io.js is installed."
    return 1
  fi
  local LOCAL_VERSION
  local EXIT_CODE
  LOCAL_VERSION="$(beamer_version "${PROVIDED_VERSION}")"
  EXIT_CODE="$?"
  local BEAMER_VERSION_DIR
  if [ "${EXIT_CODE}" != "0" ] || ! beamer_is_version_installed "${LOCAL_VERSION}"; then
    if VERSION="$(beamer_resolve_alias "${PROVIDED_VERSION}")"; then
      beamer_err "N/A: version \"${PROVIDED_VERSION} -> ${VERSION}\" is not yet installed."
    else
      local PREFIXED_VERSION
      PREFIXED_VERSION="$(beamer_ensure_version_prefix "${PROVIDED_VERSION}")"
      beamer_err "N/A: version \"${PREFIXED_VERSION:-$PROVIDED_VERSION}\" is not yet installed."
    fi
    beamer_err ""
    if [ "${IS_VERSION_FROM_BEAMERRC}" != '1' ]; then
        beamer_err "You need to run \`beamer install ${PROVIDED_VERSION}\` to install and use it."
      else
        beamer_err 'You need to run `beamer install` to install and use the beam version specified in `.beamerrc`.'
    fi
    return 1
  fi
}

# Expand a version using the version cache
beamer_version() {
  local PATTERN
  PATTERN="${1-}"
  local VERSION
  # The default version is the current one
  if [ -z "${PATTERN}" ]; then
    PATTERN='current'
  fi

  if [ "${PATTERN}" = "current" ]; then
    beamer_ls_current
    return $?
  fi

  local BEAMER_BEAM_PREFIX
  BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"
  case "_${PATTERN}" in
    "_${BEAMER_BEAM_PREFIX}" | "_${BEAMER_BEAM_PREFIX}-")
      PATTERN="stable"
    ;;
  esac
  VERSION="$(beamer_ls "${PATTERN}" | command tail -1)"
  if [ -z "${VERSION}" ] || [ "_${VERSION}" = "_N/A" ]; then
    beamer_echo "N/A"
    return 3
  fi
  beamer_echo "${VERSION}"
}

beamer_remote_version() {
  local PATTERN
  PATTERN="${1-}"
  local VERSION
  if beamer_validate_implicit_alias "${PATTERN}" 2>/dev/null; then
    case "${PATTERN}" in
      "$(beamer_iojs_prefix)")
        VERSION="$(BEAMER_LTS="${BEAMER_LTS-}" beamer_ls_remote_iojs | command tail -1)" &&:
      ;;
      *)
        VERSION="$(BEAMER_LTS="${BEAMER_LTS-}" beamer_ls_remote "${PATTERN}")" &&:
      ;;
    esac
  else
    VERSION="$(BEAMER_LTS="${BEAMER_LTS-}" beamer_remote_versions "${PATTERN}" | command tail -1)"
  fi
  if [ -n "${BEAMER_VERSION_ONLY-}" ]; then
    command awk 'BEGIN {
      n = split(ARGV[1], a);
      print a[1]
    }' "${VERSION}"
  else
    beamer_echo "${VERSION}"
  fi
  if [ "${VERSION}" = 'N/A' ]; then
    return 3
  fi
}

beamer_remote_versions() {
  local BEAMER_IOJS_PREFIX
  BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
  local BEAMER_BEAM_PREFIX
  BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"

  local PATTERN
  PATTERN="${1-}"

  local BEAMER_FLAVOR
  if [ -n "${BEAMER_LTS-}" ]; then
    BEAMER_FLAVOR="${BEAMER_BEAM_PREFIX}"
  fi

  case "${PATTERN}" in
    "${BEAMER_IOJS_PREFIX}" | "io.js")
      BEAMER_FLAVOR="${BEAMER_IOJS_PREFIX}"
      unset PATTERN
    ;;
    "${BEAMER_BEAM_PREFIX}")
      BEAMER_FLAVOR="${BEAMER_BEAM_PREFIX}"
      unset PATTERN
    ;;
  esac

  if beamer_validate_implicit_alias "${PATTERN-}" 2>/dev/null; then
    beamer_err 'Implicit aliases are not supported in beamer_remote_versions.'
    return 1
  fi

  local BEAMER_LS_REMOTE_EXIT_CODE
  BEAMER_LS_REMOTE_EXIT_CODE=0
  local BEAMER_LS_REMOTE_PRE_MERGED_OUTPUT
  BEAMER_LS_REMOTE_PRE_MERGED_OUTPUT=''
  local BEAMER_LS_REMOTE_POST_MERGED_OUTPUT
  BEAMER_LS_REMOTE_POST_MERGED_OUTPUT=''
  if [ -z "${BEAMER_FLAVOR-}" ] || [ "${BEAMER_FLAVOR-}" = "${BEAMER_BEAM_PREFIX}" ]; then
    local BEAMER_LS_REMOTE_OUTPUT
    # extra space is needed here to avoid weird behavior when `beamer_ls_remote` ends in a `*`
    BEAMER_LS_REMOTE_OUTPUT="$(BEAMER_LTS="${BEAMER_LTS-}" beamer_ls_remote "${PATTERN-}") " &&:
    BEAMER_LS_REMOTE_EXIT_CODE=$?
    # split output into two
    BEAMER_LS_REMOTE_PRE_MERGED_OUTPUT="${BEAMER_LS_REMOTE_OUTPUT%%v4\.0\.0*}"
    BEAMER_LS_REMOTE_POST_MERGED_OUTPUT="${BEAMER_LS_REMOTE_OUTPUT#"$BEAMER_LS_REMOTE_PRE_MERGED_OUTPUT"}"
  fi

  local BEAMER_LS_REMOTE_IOJS_EXIT_CODE
  BEAMER_LS_REMOTE_IOJS_EXIT_CODE=0
  local BEAMER_LS_REMOTE_IOJS_OUTPUT
  BEAMER_LS_REMOTE_IOJS_OUTPUT=''
  if [ -z "${BEAMER_LTS-}" ] && {
    [ -z "${BEAMER_FLAVOR-}" ] || [ "${BEAMER_FLAVOR-}" = "${BEAMER_IOJS_PREFIX}" ];
  }; then
    BEAMER_LS_REMOTE_IOJS_OUTPUT=$(beamer_ls_remote_iojs "${PATTERN-}") &&:
    BEAMER_LS_REMOTE_IOJS_EXIT_CODE=$?
  fi

  # the `sed` removes both blank lines, and only-whitespace lines (see "weird behavior" ~19 lines up)
  VERSIONS="$(beamer_echo "${BEAMER_LS_REMOTE_PRE_MERGED_OUTPUT}
${BEAMER_LS_REMOTE_IOJS_OUTPUT}
${BEAMER_LS_REMOTE_POST_MERGED_OUTPUT}" | beamer_grep -v "N/A" | command sed '/^ *$/d')"

  if [ -z "${VERSIONS}" ]; then
    beamer_echo 'N/A'
    return 3
  fi
  # the `sed` is to remove trailing whitespaces (see "weird behavior" ~25 lines up)
  beamer_echo "${VERSIONS}" | command sed 's/ *$//g'
  # shellcheck disable=SC2317
  return $BEAMER_LS_REMOTE_EXIT_CODE || $BEAMER_LS_REMOTE_IOJS_EXIT_CODE
}

beamer_is_valid_version() {
  if beamer_validate_implicit_alias "${1-}" 2>/dev/null; then
    return 0
  fi
  case "${1-}" in
    "$(beamer_iojs_prefix)" | \
    "$(beamer_beam_prefix)")
      return 0
    ;;
    *)
      local VERSION
      VERSION="$(beamer_strip_iojs_prefix "${1-}")"
      beamer_version_greater_than_or_equal_to "${VERSION}" 0
    ;;
  esac
}

beamer_normalize_version() {
  command awk 'BEGIN {
    split(ARGV[1], a, /\./);
    printf "%d%06d%06d\n", a[1], a[2], a[3];
    exit;
  }' "${1#v}"
}

beamer_normalize_lts() {
  local LTS
  LTS="${1-}"

  case "${LTS}" in
    lts/-[123456789] | lts/-[123456789][0123456789]*)
      local N
      N="$(echo "${LTS}" | cut -d '-' -f 2)"
      N=$((N+1))
      # shellcheck disable=SC2181
      if [ $? -ne 0 ]; then
        beamer_echo "${LTS}"
        return 0
      fi
      local BEAMER_ALIAS_DIR
      BEAMER_ALIAS_DIR="$(beamer_alias_path)"
      local RESULT
      RESULT="$(command ls "${BEAMER_ALIAS_DIR}/lts" | command tail -n "${N}" | command head -n 1)"
      if [ "${RESULT}" != '*' ]; then
        beamer_echo "lts/${RESULT}"
      else
        beamer_err 'That many LTS releases do not exist yet.'
        return 2
      fi
    ;;
    *)
      beamer_echo "${LTS}"
    ;;
  esac
}

beamer_ensure_version_prefix() {
  local BEAMER_VERSION
  BEAMER_VERSION="$(beamer_strip_iojs_prefix "${1-}" | command sed -e 's/^\([0-9]\)/v\1/g')"
  if beamer_is_iojs_version "${1-}"; then
    beamer_add_iojs_prefix "${BEAMER_VERSION}"
  else
    beamer_echo "${BEAMER_VERSION}"
  fi
}

beamer_format_version() {
  local VERSION
  VERSION="$(beamer_ensure_version_prefix "${1-}")"
  local NUM_GROUPS
  NUM_GROUPS="$(beamer_num_version_groups "${VERSION}")"
  if [ "${NUM_GROUPS}" -lt 3 ]; then
    beamer_format_version "${VERSION%.}.0"
  else
    beamer_echo "${VERSION}" | command cut -f1-3 -d.
  fi
}

beamer_num_version_groups() {
  local VERSION
  VERSION="${1-}"
  VERSION="${VERSION#v}"
  VERSION="${VERSION%.}"
  if [ -z "${VERSION}" ]; then
    beamer_echo "0"
    return
  fi
  local BEAMER_NUM_DOTS
  BEAMER_NUM_DOTS=$(beamer_echo "${VERSION}" | command sed -e 's/[^\.]//g')
  local BEAMER_NUM_GROUPS
  BEAMER_NUM_GROUPS=".${BEAMER_NUM_DOTS}" # add extra dot, since it's (n - 1) dots at this point
  beamer_echo "${#BEAMER_NUM_GROUPS}"
}

beamer_strip_path() {
  if [ -z "${BEAMER_DIR-}" ]; then
    beamer_err '${BEAMER_DIR} not set!'
    return 1
  fi
  command printf %s "${1-}" | command awk -v BEAMER_DIR="${BEAMER_DIR}" -v RS=: '
  index($0, BEAMER_DIR) == 1 {
    path = substr($0, length(BEAMER_DIR) + 1)
    if (path ~ "^(/versions/[^/]*)?/[^/]*'"${2-}"'.*$") { next }
  }
  # The final RT will contain a colon if the input has a trailing colon, or a null string otherwise
  { printf "%s%s", sep, $0; sep=RS } END { printf "%s", RT }'
}

beamer_change_path() {
  # if there’s no initial path, just return the supplementary path
  if [ -z "${1-}" ]; then
    beamer_echo "${3-}${2-}"
  # if the initial path doesn’t contain an beamer path, prepend the supplementary
  # path
  elif ! beamer_echo "${1-}" | beamer_grep -q "${BEAMER_DIR}/[^/]*${2-}" \
    && ! beamer_echo "${1-}" | beamer_grep -q "${BEAMER_DIR}/versions/[^/]*/[^/]*${2-}"; then
    beamer_echo "${3-}${2-}:${1-}"
  # if the initial path contains BOTH an beamer path (checked for above) and
  # that beamer path is preceded by a system binary path, just prepend the
  # supplementary path instead of replacing it.
  # https://github.com/beamer-sh/beamer/issues/1652#issuecomment-342571223
  elif beamer_echo "${1-}" | beamer_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${BEAMER_DIR}/[^/]*${2-}" \
    || beamer_echo "${1-}" | beamer_grep -Eq "(^|:)(/usr(/local)?)?${2-}:.*${BEAMER_DIR}/versions/[^/]*/[^/]*${2-}"; then
    beamer_echo "${3-}${2-}:${1-}"
  # use sed to replace the existing beamer path with the supplementary path. This
  # preserves the order of the path.
  else
    beamer_echo "${1-}" | command sed \
      -e "s#${BEAMER_DIR}/[^/]*${2-}[^:]*#${3-}${2-}#" \
      -e "s#${BEAMER_DIR}/versions/[^/]*/[^/]*${2-}[^:]*#${3-}${2-}#"
  fi
}

beamer_binary_available() {
  # binaries started with beam 0.8.6
  beamer_version_greater_than_or_equal_to "$(beamer_strip_iojs_prefix "${1-}")" v0.8.6
}

beamer_set_colors() {
  if [ "${#1}" -eq 5 ] && beamer_echo "$1" | beamer_grep -E "^[rRgGbBcCyYmMkKeW]{1,}$" 1>/dev/null; then
    local INSTALLED_COLOR
    local LTS_AND_SYSTEM_COLOR
    local CURRENT_COLOR
    local NOT_INSTALLED_COLOR
    local DEFAULT_COLOR

    INSTALLED_COLOR="$(echo "$1" | awk '{ print substr($0, 1, 1); }')"
    LTS_AND_SYSTEM_COLOR="$(echo "$1" | awk '{ print substr($0, 2, 1); }')"
    CURRENT_COLOR="$(echo "$1" | awk '{ print substr($0, 3, 1); }')"
    NOT_INSTALLED_COLOR="$(echo "$1" | awk '{ print substr($0, 4, 1); }')"
    DEFAULT_COLOR="$(echo "$1" | awk '{ print substr($0, 5, 1); }')"
    if ! beamer_has_colors; then
      beamer_echo "Setting colors to: ${INSTALLED_COLOR} ${LTS_AND_SYSTEM_COLOR} ${CURRENT_COLOR} ${NOT_INSTALLED_COLOR} ${DEFAULT_COLOR}"
      beamer_echo "WARNING: Colors may not display because they are not supported in this shell."
    else
      beamer_echo_with_colors "Setting colors to: $(beamer_wrap_with_color_code "${INSTALLED_COLOR}" "${INSTALLED_COLOR}")$(beamer_wrap_with_color_code "${LTS_AND_SYSTEM_COLOR}" "${LTS_AND_SYSTEM_COLOR}")$(beamer_wrap_with_color_code "${CURRENT_COLOR}" "${CURRENT_COLOR}")$(beamer_wrap_with_color_code "${NOT_INSTALLED_COLOR}" "${NOT_INSTALLED_COLOR}")$(beamer_wrap_with_color_code "${DEFAULT_COLOR}" "${DEFAULT_COLOR}")"
    fi
    export BEAMER_COLORS="$1"
  else
    return 17
  fi
}

beamer_get_colors() {
  local COLOR
  local SYS_COLOR
  local COLORS
  COLORS="${BEAMER_COLORS:-bygre}"
  case $1 in
    1) COLOR=$(beamer_print_color_code "$(echo "$COLORS" | awk '{ print substr($0, 1, 1); }')");;
    2) COLOR=$(beamer_print_color_code "$(echo "$COLORS" | awk '{ print substr($0, 2, 1); }')");;
    3) COLOR=$(beamer_print_color_code "$(echo "$COLORS" | awk '{ print substr($0, 3, 1); }')");;
    4) COLOR=$(beamer_print_color_code "$(echo "$COLORS" | awk '{ print substr($0, 4, 1); }')");;
    5) COLOR=$(beamer_print_color_code "$(echo "$COLORS" | awk '{ print substr($0, 5, 1); }')");;
    6)
      SYS_COLOR=$(beamer_print_color_code "$(echo "$COLORS" | awk '{ print substr($0, 2, 1); }')")
      COLOR=$(beamer_echo "$SYS_COLOR" | command tr '0;' '1;')
      ;;
    *)
      beamer_err "Invalid color index, ${1-}"
      return 1
    ;;
  esac

  beamer_echo "$COLOR"
}

beamer_wrap_with_color_code() {
  local CODE
  CODE="$(beamer_print_color_code "${1}" 2>/dev/null ||:)"
  local TEXT
  TEXT="${2-}"
  if beamer_has_colors && [ -n "${CODE}" ]; then
    beamer_echo_with_colors "\033[${CODE}${TEXT}\033[0m"
  else
    beamer_echo "${TEXT}"
  fi
}

beamer_print_color_code() {
  case "${1-}" in
    '0') return 0 ;;
    'r') beamer_echo '0;31m' ;;
    'R') beamer_echo '1;31m' ;;
    'g') beamer_echo '0;32m' ;;
    'G') beamer_echo '1;32m' ;;
    'b') beamer_echo '0;34m' ;;
    'B') beamer_echo '1;34m' ;;
    'c') beamer_echo '0;36m' ;;
    'C') beamer_echo '1;36m' ;;
    'm') beamer_echo '0;35m' ;;
    'M') beamer_echo '1;35m' ;;
    'y') beamer_echo '0;33m' ;;
    'Y') beamer_echo '1;33m' ;;
    'k') beamer_echo '0;30m' ;;
    'K') beamer_echo '1;30m' ;;
    'e') beamer_echo '0;37m' ;;
    'W') beamer_echo '1;37m' ;;
    *)
      beamer_err "Invalid color code: ${1-}";
      return 1
    ;;
  esac
}

beamer_print_formatted_alias() {
  local ALIAS
  ALIAS="${1-}"
  local DEST
  DEST="${2-}"
  local VERSION
  VERSION="${3-}"
  if [ -z "${VERSION}" ]; then
    VERSION="$(beamer_version "${DEST}")" ||:
  fi
  local VERSION_FORMAT
  local ALIAS_FORMAT
  local DEST_FORMAT

  local INSTALLED_COLOR
  local SYSTEM_COLOR
  local CURRENT_COLOR
  local NOT_INSTALLED_COLOR
  local DEFAULT_COLOR
  local LTS_COLOR

  INSTALLED_COLOR=$(beamer_get_colors 1)
  SYSTEM_COLOR=$(beamer_get_colors 2)
  CURRENT_COLOR=$(beamer_get_colors 3)
  NOT_INSTALLED_COLOR=$(beamer_get_colors 4)
  DEFAULT_COLOR=$(beamer_get_colors 5)
  LTS_COLOR=$(beamer_get_colors 6)

  ALIAS_FORMAT='%s'
  DEST_FORMAT='%s'
  VERSION_FORMAT='%s'
  local NEWLINE
  NEWLINE='\n'
  if [ "_${DEFAULT}" = '_true' ]; then
    NEWLINE=' (default)\n'
  fi
  local ARROW
  ARROW='->'
  if beamer_has_colors; then
    ARROW='\033[0;90m->\033[0m'
    if [ "_${DEFAULT}" = '_true' ]; then
      NEWLINE=" \033[${DEFAULT_COLOR}(default)\033[0m\n"
    fi
    if [ "_${VERSION}" = "_${BEAMER_CURRENT-}" ]; then
      ALIAS_FORMAT="\033[${CURRENT_COLOR}%s\033[0m"
      DEST_FORMAT="\033[${CURRENT_COLOR}%s\033[0m"
      VERSION_FORMAT="\033[${CURRENT_COLOR}%s\033[0m"
    elif beamer_is_version_installed "${VERSION}"; then
      ALIAS_FORMAT="\033[${INSTALLED_COLOR}%s\033[0m"
      DEST_FORMAT="\033[${INSTALLED_COLOR}%s\033[0m"
      VERSION_FORMAT="\033[${INSTALLED_COLOR}%s\033[0m"
    elif [ "${VERSION}" = '∞' ] || [ "${VERSION}" = 'N/A' ]; then
      ALIAS_FORMAT="\033[${NOT_INSTALLED_COLOR}%s\033[0m"
      DEST_FORMAT="\033[${NOT_INSTALLED_COLOR}%s\033[0m"
      VERSION_FORMAT="\033[${NOT_INSTALLED_COLOR}%s\033[0m"
    fi
    if [ "_${BEAMER_LTS-}" = '_true' ]; then
      ALIAS_FORMAT="\033[${LTS_COLOR}%s\033[0m"
    fi
    if [ "_${DEST%/*}" = "_lts" ]; then
      DEST_FORMAT="\033[${LTS_COLOR}%s\033[0m"
    fi
  elif [ "_${VERSION}" != '_∞' ] && [ "_${VERSION}" != '_N/A' ]; then
    VERSION_FORMAT='%s *'
  fi
  if [ "${DEST}" = "${VERSION}" ]; then
    command printf -- "${ALIAS_FORMAT} ${ARROW} ${VERSION_FORMAT}${NEWLINE}" "${ALIAS}" "${DEST}"
  else
    command printf -- "${ALIAS_FORMAT} ${ARROW} ${DEST_FORMAT} (${ARROW} ${VERSION_FORMAT})${NEWLINE}" "${ALIAS}" "${DEST}" "${VERSION}"
  fi
}

beamer_print_alias_path() {
  local BEAMER_ALIAS_DIR
  BEAMER_ALIAS_DIR="${1-}"
  if [ -z "${BEAMER_ALIAS_DIR}" ]; then
    beamer_err 'An alias dir is required.'
    return 1
  fi
  local ALIAS_PATH
  ALIAS_PATH="${2-}"
  if [ -z "${ALIAS_PATH}" ]; then
    beamer_err 'An alias path is required.'
    return 2
  fi
  local ALIAS
  ALIAS="${ALIAS_PATH##"${BEAMER_ALIAS_DIR}"\/}"
  local DEST
  DEST="$(beamer_alias "${ALIAS}" 2>/dev/null)" ||:
  if [ -n "${DEST}" ]; then
    BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" BEAMER_LTS="${BEAMER_LTS-}" DEFAULT=false beamer_print_formatted_alias "${ALIAS}" "${DEST}"
  fi
}

beamer_print_default_alias() {
  local ALIAS
  ALIAS="${1-}"
  if [ -z "${ALIAS}" ]; then
    beamer_err 'A default alias is required.'
    return 1
  fi
  local DEST
  DEST="$(beamer_print_implicit_alias local "${ALIAS}")"
  if [ -n "${DEST}" ]; then
    BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" DEFAULT=true beamer_print_formatted_alias "${ALIAS}" "${DEST}"
  fi
}

beamer_make_alias() {
  local ALIAS
  ALIAS="${1-}"
  if [ -z "${ALIAS}" ]; then
    beamer_err "an alias name is required"
    return 1
  fi
  local VERSION
  VERSION="${2-}"
  if [ -z "${VERSION}" ]; then
    beamer_err "an alias target version is required"
    return 2
  fi
  beamer_echo "${VERSION}" | tee "$(beamer_alias_path)/${ALIAS}" >/dev/null
}

beamer_list_aliases() {
  local ALIAS
  ALIAS="${1-}"

  local BEAMER_CURRENT
  BEAMER_CURRENT="$(beamer_ls_current)"
  local BEAMER_ALIAS_DIR
  BEAMER_ALIAS_DIR="$(beamer_alias_path)"
  command mkdir -p "${BEAMER_ALIAS_DIR}/lts"

  if [ "${ALIAS}" != "${ALIAS#lts/}" ]; then
    beamer_alias "${ALIAS}"
    return $?
  fi

  beamer_is_zsh && unsetopt local_options nomatch
  (
    local ALIAS_PATH
    for ALIAS_PATH in "${BEAMER_ALIAS_DIR}/${ALIAS}"*; do
      BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" BEAMER_CURRENT="${BEAMER_CURRENT}" beamer_print_alias_path "${BEAMER_ALIAS_DIR}" "${ALIAS_PATH}" &
    done
    wait
  ) | command sort

  (
    local ALIAS_NAME
    for ALIAS_NAME in "$(beamer_beam_prefix)" "stable" "unstable" "$(beamer_iojs_prefix)"; do
      {
        # shellcheck disable=SC2030,SC2031 # (https://github.com/koalaman/shellcheck/issues/2217)
        if [ ! -f "${BEAMER_ALIAS_DIR}/${ALIAS_NAME}" ] && { [ -z "${ALIAS}" ] || [ "${ALIAS_NAME}" = "${ALIAS}" ]; }; then
          BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" BEAMER_CURRENT="${BEAMER_CURRENT}" beamer_print_default_alias "${ALIAS_NAME}"
        fi
      } &
    done
    wait
  ) | command sort

  (
    local LTS_ALIAS
    # shellcheck disable=SC2030,SC2031 # (https://github.com/koalaman/shellcheck/issues/2217)
    for ALIAS_PATH in "${BEAMER_ALIAS_DIR}/lts/${ALIAS}"*; do
      {
        LTS_ALIAS="$(BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" BEAMER_LTS=true beamer_print_alias_path "${BEAMER_ALIAS_DIR}" "${ALIAS_PATH}")"
        if [ -n "${LTS_ALIAS}" ]; then
          beamer_echo "${LTS_ALIAS}"
        fi
      } &
    done
    wait
  ) | command sort
  return
}

beamer_alias() {
  local ALIAS
  ALIAS="${1-}"
  if [ -z "${ALIAS}" ]; then
    beamer_err 'An alias is required.'
    return 1
  fi
  ALIAS="$(beamer_normalize_lts "${ALIAS}")"

  if [ -z "${ALIAS}" ]; then
    return 2
  fi

  local BEAMER_ALIAS_PATH
  BEAMER_ALIAS_PATH="$(beamer_alias_path)/${ALIAS}"
  if [ ! -f "${BEAMER_ALIAS_PATH}" ]; then
    beamer_err 'Alias does not exist.'
    return 2
  fi

  command awk 'NF' "${BEAMER_ALIAS_PATH}"
}

beamer_ls_current() {
  local BEAMER_LS_CURRENT_BEAM_PATH
  if ! BEAMER_LS_CURRENT_BEAM_PATH="$(command which beam 2>/dev/null)"; then
    beamer_echo 'none'
  elif beamer_tree_contains_path "$(beamer_version_dir iojs)" "${BEAMER_LS_CURRENT_BEAM_PATH}"; then
    beamer_add_iojs_prefix "$(iojs --version 2>/dev/null)"
  elif beamer_tree_contains_path "${BEAMER_DIR}" "${BEAMER_LS_CURRENT_BEAM_PATH}"; then
    local VERSION
    VERSION="$(beam --version 2>/dev/null)"
    if [ "${VERSION}" = "v0.6.21-pre" ]; then
      beamer_echo 'v0.6.21'
    else
      beamer_echo "${VERSION:-none}"
    fi
  else
    beamer_echo 'system'
  fi
}

beamer_resolve_alias() {
  if [ -z "${1-}" ]; then
    return 1
  fi

  local PATTERN
  PATTERN="${1-}"

  local ALIAS
  ALIAS="${PATTERN}"
  local ALIAS_TEMP

  local SEEN_ALIASES
  SEEN_ALIASES="${ALIAS}"
  local BEAMER_ALIAS_INDEX
  BEAMER_ALIAS_INDEX=1
  while true; do
    ALIAS_TEMP="$( (beamer_alias "${ALIAS}" 2>/dev/null | command head -n "${BEAMER_ALIAS_INDEX}" | command tail -n 1) || beamer_echo)"

    if [ -z "${ALIAS_TEMP}" ]; then
      break
    fi

    if command printf "${SEEN_ALIASES}" | beamer_grep -q -e "^${ALIAS_TEMP}$"; then
      ALIAS="∞"
      break
    fi

    SEEN_ALIASES="${SEEN_ALIASES}\\n${ALIAS_TEMP}"
    ALIAS="${ALIAS_TEMP}"
  done

  if [ -n "${ALIAS}" ] && [ "_${ALIAS}" != "_${PATTERN}" ]; then
    local BEAMER_IOJS_PREFIX
    BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
    local BEAMER_BEAM_PREFIX
    BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"
    case "${ALIAS}" in
      '∞' | \
      "${BEAMER_IOJS_PREFIX}" | "${BEAMER_IOJS_PREFIX}-" | \
      "${BEAMER_BEAM_PREFIX}")
        beamer_echo "${ALIAS}"
      ;;
      *)
        beamer_ensure_version_prefix "${ALIAS}"
      ;;
    esac
    return 0
  fi

  if beamer_validate_implicit_alias "${PATTERN}" 2>/dev/null; then
    local IMPLICIT
    IMPLICIT="$(beamer_print_implicit_alias local "${PATTERN}" 2>/dev/null)"
    if [ -n "${IMPLICIT}" ]; then
      beamer_ensure_version_prefix "${IMPLICIT}"
    fi
  fi

  return 2
}

beamer_resolve_local_alias() {
  if [ -z "${1-}" ]; then
    return 1
  fi

  local VERSION
  local EXIT_CODE
  VERSION="$(beamer_resolve_alias "${1-}")"
  EXIT_CODE=$?
  if [ -z "${VERSION}" ]; then
    return $EXIT_CODE
  fi
  if [ "_${VERSION}" != '_∞' ]; then
    beamer_version "${VERSION}"
  else
    beamer_echo "${VERSION}"
  fi
}

beamer_iojs_prefix() {
  beamer_echo 'iojs'
}
beamer_beam_prefix() {
  beamer_echo 'beam'
}

beamer_is_iojs_version() {
  case "${1-}" in iojs-*) return 0 ;; esac
  return 1
}

beamer_add_iojs_prefix() {
  beamer_echo "$(beamer_iojs_prefix)-$(beamer_ensure_version_prefix "$(beamer_strip_iojs_prefix "${1-}")")"
}

beamer_strip_iojs_prefix() {
  local BEAMER_IOJS_PREFIX
  BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
  if [ "${1-}" = "${BEAMER_IOJS_PREFIX}" ]; then
    beamer_echo
  else
    beamer_echo "${1#"${BEAMER_IOJS_PREFIX}"-}"
  fi
}

beamer_ls() {
  local PATTERN
  PATTERN="${1-}"
  local VERSIONS
  VERSIONS=''
  if [ "${PATTERN}" = 'current' ]; then
    beamer_ls_current
    return
  fi

  local BEAMER_IOJS_PREFIX
  BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
  local BEAMER_BEAM_PREFIX
  BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"
  local BEAMER_VERSION_DIR_IOJS
  BEAMER_VERSION_DIR_IOJS="$(beamer_version_dir "${BEAMER_IOJS_PREFIX}")"
  local BEAMER_VERSION_DIR_NEW
  BEAMER_VERSION_DIR_NEW="$(beamer_version_dir new)"
  local BEAMER_VERSION_DIR_OLD
  BEAMER_VERSION_DIR_OLD="$(beamer_version_dir old)"

  case "${PATTERN}" in
    "${BEAMER_IOJS_PREFIX}" | "${BEAMER_BEAM_PREFIX}")
      PATTERN="${PATTERN}-"
    ;;
    *)
      if beamer_resolve_local_alias "${PATTERN}"; then
        return
      fi
      PATTERN="$(beamer_ensure_version_prefix "${PATTERN}")"
    ;;
  esac
  if [ "${PATTERN}" = 'N/A' ]; then
    return
  fi
  # If it looks like an explicit version, don't do anything funny
  local BEAMER_PATTERN_STARTS_WITH_V
  case $PATTERN in
    v*) BEAMER_PATTERN_STARTS_WITH_V=true ;;
    *) BEAMER_PATTERN_STARTS_WITH_V=false ;;
  esac
  if [ $BEAMER_PATTERN_STARTS_WITH_V = true ] && [ "_$(beamer_num_version_groups "${PATTERN}")" = "_3" ]; then
    if beamer_is_version_installed "${PATTERN}"; then
      VERSIONS="${PATTERN}"
    elif beamer_is_version_installed "$(beamer_add_iojs_prefix "${PATTERN}")"; then
      VERSIONS="$(beamer_add_iojs_prefix "${PATTERN}")"
    fi
  else
    case "${PATTERN}" in
      "${BEAMER_IOJS_PREFIX}-" | "${BEAMER_BEAM_PREFIX}-" | "system") ;;
      *)
        local NUM_VERSION_GROUPS
        NUM_VERSION_GROUPS="$(beamer_num_version_groups "${PATTERN}")"
        if [ "${NUM_VERSION_GROUPS}" = "2" ] || [ "${NUM_VERSION_GROUPS}" = "1" ]; then
          PATTERN="${PATTERN%.}."
        fi
      ;;
    esac

    beamer_is_zsh && setopt local_options shwordsplit
    beamer_is_zsh && unsetopt local_options markdirs

    local BEAMER_DIRS_TO_SEARCH1
    BEAMER_DIRS_TO_SEARCH1=''
    local BEAMER_DIRS_TO_SEARCH2
    BEAMER_DIRS_TO_SEARCH2=''
    local BEAMER_DIRS_TO_SEARCH3
    BEAMER_DIRS_TO_SEARCH3=''
    local BEAMER_ADD_SYSTEM
    BEAMER_ADD_SYSTEM=false
    if beamer_is_iojs_version "${PATTERN}"; then
      BEAMER_DIRS_TO_SEARCH1="${BEAMER_VERSION_DIR_IOJS}"
      PATTERN="$(beamer_strip_iojs_prefix "${PATTERN}")"
      if beamer_has_system_iojs; then
        BEAMER_ADD_SYSTEM=true
      fi
    elif [ "${PATTERN}" = "${BEAMER_BEAM_PREFIX}-" ]; then
      BEAMER_DIRS_TO_SEARCH1="${BEAMER_VERSION_DIR_OLD}"
      BEAMER_DIRS_TO_SEARCH2="${BEAMER_VERSION_DIR_NEW}"
      PATTERN=''
      if beamer_has_system_beam; then
        BEAMER_ADD_SYSTEM=true
      fi
    else
      BEAMER_DIRS_TO_SEARCH1="${BEAMER_VERSION_DIR_OLD}"
      BEAMER_DIRS_TO_SEARCH2="${BEAMER_VERSION_DIR_NEW}"
      BEAMER_DIRS_TO_SEARCH3="${BEAMER_VERSION_DIR_IOJS}"
      if beamer_has_system_iojs || beamer_has_system_beam; then
        BEAMER_ADD_SYSTEM=true
      fi
    fi

    if ! [ -d "${BEAMER_DIRS_TO_SEARCH1}" ] || ! (command ls -1qA "${BEAMER_DIRS_TO_SEARCH1}" | beamer_grep -q .); then
      BEAMER_DIRS_TO_SEARCH1=''
    fi
    if ! [ -d "${BEAMER_DIRS_TO_SEARCH2}" ] || ! (command ls -1qA "${BEAMER_DIRS_TO_SEARCH2}" | beamer_grep -q .); then
      BEAMER_DIRS_TO_SEARCH2="${BEAMER_DIRS_TO_SEARCH1}"
    fi
    if ! [ -d "${BEAMER_DIRS_TO_SEARCH3}" ] || ! (command ls -1qA "${BEAMER_DIRS_TO_SEARCH3}" | beamer_grep -q .); then
      BEAMER_DIRS_TO_SEARCH3="${BEAMER_DIRS_TO_SEARCH2}"
    fi

    local SEARCH_PATTERN
    if [ -z "${PATTERN}" ]; then
      PATTERN='v'
      SEARCH_PATTERN='.*'
    else
      SEARCH_PATTERN="$(beamer_echo "${PATTERN}" | command sed 's#\.#\\\.#g;')"
    fi
    if [ -n "${BEAMER_DIRS_TO_SEARCH1}${BEAMER_DIRS_TO_SEARCH2}${BEAMER_DIRS_TO_SEARCH3}" ]; then
      VERSIONS="$(command find "${BEAMER_DIRS_TO_SEARCH1}"/* "${BEAMER_DIRS_TO_SEARCH2}"/* "${BEAMER_DIRS_TO_SEARCH3}"/* -name . -o -type d -prune -o -path "${PATTERN}*" \
        | command sed -e "
            s#${BEAMER_VERSION_DIR_IOJS}/#versions/${BEAMER_IOJS_PREFIX}/#;
            s#^${BEAMER_DIR}/##;
            \\#^[^v]# d;
            \\#^versions\$# d;
            s#^versions/##;
            s#^v#${BEAMER_BEAM_PREFIX}/v#;
            \\#${SEARCH_PATTERN}# !d;
          " \
          -e 's#^\([^/]\{1,\}\)/\(.*\)$#\2.\1#;' \
        | command sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n \
        | command sed -e 's#\(.*\)\.\([^\.]\{1,\}\)$#\2-\1#;' \
                      -e "s#^${BEAMER_BEAM_PREFIX}-##;" \
      )"
    fi
  fi

  if [ "${BEAMER_ADD_SYSTEM-}" = true ]; then
    if [ -z "${PATTERN}" ] || [ "${PATTERN}" = 'v' ]; then
      VERSIONS="${VERSIONS}
system"
    elif [ "${PATTERN}" = 'system' ]; then
      VERSIONS="system"
    fi
  fi

  if [ -z "${VERSIONS}" ]; then
    beamer_echo 'N/A'
    return 3
  fi

  beamer_echo "${VERSIONS}"
}

beamer_ls_remote() {
  local PATTERN
  PATTERN="${1-}"
  if beamer_validate_implicit_alias "${PATTERN}" 2>/dev/null ; then
    local IMPLICIT
    IMPLICIT="$(beamer_print_implicit_alias remote "${PATTERN}")"
    if [ -z "${IMPLICIT-}" ] || [ "${IMPLICIT}" = 'N/A' ]; then
      beamer_echo "N/A"
      return 3
    fi
    PATTERN="$(BEAMER_LTS="${BEAMER_LTS-}" beamer_ls_remote "${IMPLICIT}" | command tail -1 | command awk '{ print $1 }')"
  elif [ -n "${PATTERN}" ]; then
    PATTERN="$(beamer_ensure_version_prefix "${PATTERN}")"
  else
    PATTERN=".*"
  fi
  BEAMER_LTS="${BEAMER_LTS-}" beamer_ls_remote_index_tab beam std "${PATTERN}"
}

beamer_ls_remote_iojs() {
  BEAMER_LTS="${BEAMER_LTS-}" beamer_ls_remote_index_tab iojs std "${1-}"
}

# args flavor, type, version
beamer_ls_remote_index_tab() {
  local LTS
  LTS="${BEAMER_LTS-}"
  if [ "$#" -lt 3 ]; then
    beamer_err 'not enough arguments'
    return 5
  fi

  local FLAVOR
  FLAVOR="${1-}"

  local TYPE
  TYPE="${2-}"

  local MIRROR
  MIRROR="$(beamer_get_mirror "${FLAVOR}" "${TYPE}")"
  if [ -z "${MIRROR}" ]; then
    return 3
  fi

  local PREFIX
  PREFIX=''
  case "${FLAVOR}-${TYPE}" in
    iojs-std) PREFIX="$(beamer_iojs_prefix)-" ;;
    beam-std) PREFIX='' ;;
    iojs-*)
      beamer_err 'unknown type of io.js release'
      return 4
    ;;
    *)
      beamer_err 'unknown type of beam.js release'
      return 4
    ;;
  esac
  local SORT_COMMAND
  SORT_COMMAND='command sort'
  case "${FLAVOR}" in
    beam) SORT_COMMAND='command sort -t. -u -k 1.2,1n -k 2,2n -k 3,3n' ;;
  esac

  local PATTERN
  PATTERN="${3-}"

  if [ "${PATTERN#"${PATTERN%?}"}" = '.' ]; then
    PATTERN="${PATTERN%.}"
  fi

  local VERSIONS
  if [ -n "${PATTERN}" ] && [ "${PATTERN}" != '*' ]; then
    if [ "${FLAVOR}" = 'iojs' ]; then
      PATTERN="$(beamer_ensure_version_prefix "$(beamer_strip_iojs_prefix "${PATTERN}")")"
    else
      PATTERN="$(beamer_ensure_version_prefix "${PATTERN}")"
    fi
  else
    unset PATTERN
  fi

  beamer_is_zsh && setopt local_options shwordsplit
  local VERSION_LIST
  VERSION_LIST="$(beamer_download -L -s "${MIRROR}/index.tab" -o - \
    | command sed "
        1d;
        s/^/${PREFIX}/;
      " \
  )"
  local LTS_ALIAS
  local LTS_VERSION
  command mkdir -p "$(beamer_alias_path)/lts"
  { command awk '{
        if ($10 ~ /^\-?$/) { next }
        if ($10 && !a[tolower($10)]++) {
          if (alias) { print alias, version }
          alias_name = "lts/" tolower($10)
          if (!alias) { print "lts/*", alias_name }
          alias = alias_name
          version = $1
        }
      }
      END {
        if (alias) {
          print alias, version
        }
      }' \
    | while read -r LTS_ALIAS_LINE; do
      LTS_ALIAS="${LTS_ALIAS_LINE%% *}"
      LTS_VERSION="${LTS_ALIAS_LINE#* }"
      beamer_make_alias "${LTS_ALIAS}" "${LTS_VERSION}" >/dev/null 2>&1
    done; } << EOF
$VERSION_LIST
EOF

  if [ -n "${LTS-}" ]; then
    LTS="$(beamer_normalize_lts "lts/${LTS}")"
    LTS="${LTS#lts/}"
  fi

  VERSIONS="$({ command awk -v lts="${LTS-}" '{
        if (!$1) { next }
        if (lts && $10 ~ /^\-?$/) { next }
        if (lts && lts != "*" && tolower($10) !~ tolower(lts)) { next }
        if ($10 !~ /^\-?$/) {
          if ($10 && $10 != prev) {
            print $1, $10, "*"
          } else {
            print $1, $10
          }
        } else {
          print $1
        }
        prev=$10;
      }' \
    | beamer_grep -w "${PATTERN:-.*}" \
    | $SORT_COMMAND; } << EOF
$VERSION_LIST
EOF
)"
  if [ -z "${VERSIONS}" ]; then
    beamer_echo 'N/A'
    return 3
  fi
  beamer_echo "${VERSIONS}"
}

beamer_get_checksum_binary() {
  if beamer_has_non_aliased 'sha256sum'; then
    beamer_echo 'sha256sum'
  elif beamer_has_non_aliased 'shasum'; then
    beamer_echo 'shasum'
  elif beamer_has_non_aliased 'sha256'; then
    beamer_echo 'sha256'
  elif beamer_has_non_aliased 'gsha256sum'; then
    beamer_echo 'gsha256sum'
  elif beamer_has_non_aliased 'openssl'; then
    beamer_echo 'openssl'
  elif beamer_has_non_aliased 'bssl'; then
    beamer_echo 'bssl'
  elif beamer_has_non_aliased 'sha1sum'; then
    beamer_echo 'sha1sum'
  elif beamer_has_non_aliased 'sha1'; then
    beamer_echo 'sha1'
  else
    beamer_err 'Unaliased sha256sum, shasum, sha256, gsha256sum, openssl, or bssl not found.'
    beamer_err 'Unaliased sha1sum or sha1 not found.'
    return 1
  fi
}

beamer_get_checksum_alg() {
  local BEAMER_CHECKSUM_BIN
  BEAMER_CHECKSUM_BIN="$(beamer_get_checksum_binary 2>/dev/null)"
  case "${BEAMER_CHECKSUM_BIN-}" in
    sha256sum | shasum | sha256 | gsha256sum | openssl | bssl)
      beamer_echo 'sha-256'
    ;;
    sha1sum | sha1)
      beamer_echo 'sha-1'
    ;;
    *)
      beamer_get_checksum_binary
      return $?
    ;;
  esac
}

beamer_compute_checksum() {
  local FILE
  FILE="${1-}"
  if [ -z "${FILE}" ]; then
    beamer_err 'Provided file to checksum is empty.'
    return 2
  elif ! [ -f "${FILE}" ]; then
    beamer_err 'Provided file to checksum does not exist.'
    return 1
  fi

  if beamer_has_non_aliased "sha256sum"; then
    beamer_err 'Computing checksum with sha256sum'
    command sha256sum "${FILE}" | command awk '{print $1}'
  elif beamer_has_non_aliased "shasum"; then
    beamer_err 'Computing checksum with shasum -a 256'
    command shasum -a 256 "${FILE}" | command awk '{print $1}'
  elif beamer_has_non_aliased "sha256"; then
    beamer_err 'Computing checksum with sha256 -q'
    command sha256 -q "${FILE}" | command awk '{print $1}'
  elif beamer_has_non_aliased "gsha256sum"; then
    beamer_err 'Computing checksum with gsha256sum'
    command gsha256sum "${FILE}" | command awk '{print $1}'
  elif beamer_has_non_aliased "openssl"; then
    beamer_err 'Computing checksum with openssl dgst -sha256'
    command openssl dgst -sha256 "${FILE}" | command awk '{print $NF}'
  elif beamer_has_non_aliased "bssl"; then
    beamer_err 'Computing checksum with bssl sha256sum'
    command bssl sha256sum "${FILE}" | command awk '{print $1}'
  elif beamer_has_non_aliased "sha1sum"; then
    beamer_err 'Computing checksum with sha1sum'
    command sha1sum "${FILE}" | command awk '{print $1}'
  elif beamer_has_non_aliased "sha1"; then
    beamer_err 'Computing checksum with sha1 -q'
    command sha1 -q "${FILE}"
  fi
}

beamer_compare_checksum() {
  local FILE
  FILE="${1-}"
  if [ -z "${FILE}" ]; then
    beamer_err 'Provided file to checksum is empty.'
    return 4
  elif ! [ -f "${FILE}" ]; then
    beamer_err 'Provided file to checksum does not exist.'
    return 3
  fi

  local COMPUTED_SUM
  COMPUTED_SUM="$(beamer_compute_checksum "${FILE}")"

  local CHECKSUM
  CHECKSUM="${2-}"
  if [ -z "${CHECKSUM}" ]; then
    beamer_err 'Provided checksum to compare to is empty.'
    return 2
  fi

  if [ -z "${COMPUTED_SUM}" ]; then
    beamer_err "Computed checksum of '${FILE}' is empty." # missing in raspberry pi binary
    beamer_err 'WARNING: Continuing *without checksum verification*'
    return
  elif [ "${COMPUTED_SUM}" != "${CHECKSUM}" ] && [ "${COMPUTED_SUM}" != "\\${CHECKSUM}" ]; then
    beamer_err "Checksums do not match: '${COMPUTED_SUM}' found, '${CHECKSUM}' expected."
    return 1
  fi
  beamer_err 'Checksums matched!'
}

# args: flavor, type, version, slug, compression
beamer_get_checksum() {
  local FLAVOR
  case "${1-}" in
    beam | iojs) FLAVOR="${1}" ;;
    *)
      beamer_err 'supported flavors: beam, iojs'
      return 2
    ;;
  esac

  local MIRROR
  MIRROR="$(beamer_get_mirror "${FLAVOR}" "${2-}")"
  if [ -z "${MIRROR}" ]; then
    return 1
  fi

  local SHASUMS_URL
  if [ "$(beamer_get_checksum_alg)" = 'sha-256' ]; then
    SHASUMS_URL="${MIRROR}/${3}/SHASUMS256.txt"
  else
    SHASUMS_URL="${MIRROR}/${3}/SHASUMS.txt"
  fi

  beamer_download -L -s "${SHASUMS_URL}" -o - | command awk "{ if (\"${4}.${5}\" == \$2) print \$1}"
}

beamer_print_versions() {
  local BEAMER_CURRENT
  BEAMER_CURRENT=$(beamer_ls_current)

  local INSTALLED_COLOR
  local SYSTEM_COLOR
  local CURRENT_COLOR
  local NOT_INSTALLED_COLOR
  local DEFAULT_COLOR
  local LTS_COLOR
  local BEAMER_HAS_COLORS
  BEAMER_HAS_COLORS=0

  INSTALLED_COLOR=$(beamer_get_colors 1)
  SYSTEM_COLOR=$(beamer_get_colors 2)
  CURRENT_COLOR=$(beamer_get_colors 3)
  NOT_INSTALLED_COLOR=$(beamer_get_colors 4)
  DEFAULT_COLOR=$(beamer_get_colors 5)
  LTS_COLOR=$(beamer_get_colors 6)

  if beamer_has_colors; then
    BEAMER_HAS_COLORS=1
  fi

  command awk \
    -v remote_versions="$(printf '%s' "${1-}" | tr '\n' '|')" \
    -v installed_versions="$(beamer_ls | tr '\n' '|')" -v current="$BEAMER_CURRENT" \
    -v installed_color="$INSTALLED_COLOR" -v system_color="$SYSTEM_COLOR" \
    -v current_color="$CURRENT_COLOR" -v default_color="$DEFAULT_COLOR" \
    -v old_lts_color="$DEFAULT_COLOR" -v has_colors="$BEAMER_HAS_COLORS" '
function alen(arr, i, len) { len=0; for(i in arr) len++; return len; }
BEGIN {
  fmt_installed = has_colors ? (installed_color ? "\033[" installed_color "%15s\033[0m" : "%15s") : "%15s *";
  fmt_system = has_colors ? (system_color ? "\033[" system_color "%15s\033[0m" : "%15s") : "%15s *";
  fmt_current = has_colors ? (current_color ? "\033[" current_color "->%13s\033[0m" : "%15s") : "->%13s *";

  latest_lts_color = current_color;
  sub(/0;/, "1;", latest_lts_color);

  fmt_latest_lts = has_colors && latest_lts_color ? ("\033[" latest_lts_color " (Latest LTS: %s)\033[0m") : " (Latest LTS: %s)";
  fmt_old_lts = has_colors && old_lts_color ? ("\033[" old_lts_color " (LTS: %s)\033[0m") : " (LTS: %s)";

  split(remote_versions, lines, "|");
  split(installed_versions, installed, "|");
  rows = alen(lines);

  for (n = 1; n <= rows; n++) {
    split(lines[n], fields, "[[:blank:]]+");
    cols = alen(fields);
    version = fields[1];
    is_installed = 0;

    for (i in installed) {
      if (version == installed[i]) {
        is_installed = 1;
        break;
      }
    }

    fmt_version = "%15s";
    if (version == current) {
      fmt_version = fmt_current;
    } else if (version == "system") {
      fmt_version = fmt_system;
    } else if (is_installed) {
      fmt_version = fmt_installed;
    }

    padding = (!has_colors && is_installed) ? "" : "  ";

    if (cols == 1) {
      formatted = sprintf(fmt_version, version);
    } else if (cols == 2) {
      formatted = sprintf((fmt_version padding fmt_old_lts), version, fields[2]);
    } else if (cols == 3 && fields[3] == "*") {
      formatted = sprintf((fmt_version padding fmt_latest_lts), version, fields[2]);
    }

    output[n] = formatted;
  }

  for (n = 1; n <= rows; n++) {
    print output[n]
  }

  exit
}'
}

beamer_validate_implicit_alias() {
  local BEAMER_IOJS_PREFIX
  BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
  local BEAMER_BEAM_PREFIX
  BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"

  case "$1" in
    "stable" | "unstable" | "${BEAMER_IOJS_PREFIX}" | "${BEAMER_BEAM_PREFIX}")
      return
    ;;
    *)
      beamer_err "Only implicit aliases 'stable', 'unstable', '${BEAMER_IOJS_PREFIX}', and '${BEAMER_BEAM_PREFIX}' are supported."
      return 1
    ;;
  esac
}

beamer_print_implicit_alias() {
  if [ "_$1" != "_local" ] && [ "_$1" != "_remote" ]; then
    beamer_err "beamer_print_implicit_alias must be specified with local or remote as the first argument."
    return 1
  fi

  local BEAMER_IMPLICIT
  BEAMER_IMPLICIT="$2"
  if ! beamer_validate_implicit_alias "${BEAMER_IMPLICIT}"; then
    return 2
  fi

  local BEAMER_IOJS_PREFIX
  BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
  local BEAMER_BEAM_PREFIX
  BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"
  local BEAMER_COMMAND
  local BEAMER_ADD_PREFIX_COMMAND
  local LAST_TWO
  case "${BEAMER_IMPLICIT}" in
    "${BEAMER_IOJS_PREFIX}")
      BEAMER_COMMAND="beamer_ls_remote_iojs"
      BEAMER_ADD_PREFIX_COMMAND="beamer_add_iojs_prefix"
      if [ "_$1" = "_local" ]; then
        BEAMER_COMMAND="beamer_ls ${BEAMER_IMPLICIT}"
      fi

      beamer_is_zsh && setopt local_options shwordsplit

      local BEAMER_IOJS_VERSION
      local EXIT_CODE
      BEAMER_IOJS_VERSION="$(${BEAMER_COMMAND})" &&:
      EXIT_CODE="$?"
      if [ "_${EXIT_CODE}" = "_0" ]; then
        BEAMER_IOJS_VERSION="$(beamer_echo "${BEAMER_IOJS_VERSION}" | command sed "s/^${BEAMER_IMPLICIT}-//" | beamer_grep -e '^v' | command cut -c2- | command cut -d . -f 1,2 | uniq | command tail -1)"
      fi

      if [ "_$BEAMER_IOJS_VERSION" = "_N/A" ]; then
        beamer_echo 'N/A'
      else
        ${BEAMER_ADD_PREFIX_COMMAND} "${BEAMER_IOJS_VERSION}"
      fi
      return $EXIT_CODE
    ;;
    "${BEAMER_BEAM_PREFIX}")
      beamer_echo 'stable'
      return
    ;;
    *)
      BEAMER_COMMAND="beamer_ls_remote"
      if [ "_$1" = "_local" ]; then
        BEAMER_COMMAND="beamer_ls beam"
      fi

      beamer_is_zsh && setopt local_options shwordsplit

      LAST_TWO=$($BEAMER_COMMAND | beamer_grep -e '^v' | command cut -c2- | command cut -d . -f 1,2 | uniq)
    ;;
  esac
  local MINOR
  local STABLE
  local UNSTABLE
  local MOD
  local NORMALIZED_VERSION

  beamer_is_zsh && setopt local_options shwordsplit
  for MINOR in $LAST_TWO; do
    NORMALIZED_VERSION="$(beamer_normalize_version "$MINOR")"
    if [ "_0${NORMALIZED_VERSION#?}" != "_$NORMALIZED_VERSION" ]; then
      STABLE="$MINOR"
    else
      MOD="$(awk 'BEGIN { print int(ARGV[1] / 1000000) % 2 ; exit(0) }' "${NORMALIZED_VERSION}")"
      if [ "${MOD}" -eq 0 ]; then
        STABLE="${MINOR}"
      elif [ "${MOD}" -eq 1 ]; then
        UNSTABLE="${MINOR}"
      fi
    fi
  done

  if [ "_$2" = '_stable' ]; then
    beamer_echo "${STABLE}"
  elif [ "_$2" = '_unstable' ]; then
    beamer_echo "${UNSTABLE:-"N/A"}"
  fi
}

beamer_get_os() {
  local BEAMER_UNAME
  BEAMER_UNAME="$(command uname -a)"
  local BEAMER_OS
  case "${BEAMER_UNAME}" in
    Linux\ *) BEAMER_OS=linux ;;
    Darwin\ *) BEAMER_OS=darwin ;;
    SunOS\ *) BEAMER_OS=sunos ;;
    FreeBSD\ *) BEAMER_OS=freebsd ;;
    OpenBSD\ *) BEAMER_OS=openbsd ;;
    AIX\ *) BEAMER_OS=aix ;;
    CYGWIN* | MSYS* | MINGW*) BEAMER_OS=win ;;
  esac
  beamer_echo "${BEAMER_OS-}"
}

beamer_get_arch() {
  local HOST_ARCH
  local BEAMER_OS
  local EXIT_CODE
  local LONG_BIT

  BEAMER_OS="$(beamer_get_os)"
  # If the OS is SunOS, first try to use pkgsrc to guess
  # the most appropriate arch. If it's not available, use
  # isainfo to get the instruction set supported by the
  # kernel.
  if [ "_${BEAMER_OS}" = "_sunos" ]; then
    if HOST_ARCH=$(pkg_info -Q MACHINE_ARCH pkg_install); then
      HOST_ARCH=$(beamer_echo "${HOST_ARCH}" | command tail -1)
    else
      HOST_ARCH=$(isainfo -n)
    fi
  elif [ "_${BEAMER_OS}" = "_aix" ]; then
    HOST_ARCH=ppc64
  else
    HOST_ARCH="$(command uname -m)"
    LONG_BIT="$(getconf LONG_BIT 2>/dev/null)"
  fi

  local BEAMER_ARCH
  case "${HOST_ARCH}" in
    x86_64 | amd64) BEAMER_ARCH="x64" ;;
    i*86) BEAMER_ARCH="x86" ;;
    aarch64 | armv8l) BEAMER_ARCH="arm64" ;;
    *) BEAMER_ARCH="${HOST_ARCH}" ;;
  esac

  # If running inside a 32Bit docker container the kernel still is 64bit
  # change ARCH to 32bit if LONG_BIT is 32
  if [ "_${LONG_BIT}" = "_32" ] && [ "${BEAMER_ARCH}" = "x64" ]; then
    BEAMER_ARCH="x86"
  fi

  # If running a 64bit ARM kernel but a 32bit ARM userland,
  # change ARCH to 32bit ARM (armv7l) if /sbin/init is 32bit executable
  if [ "$(uname)" = "Linux" ] \
    && [ "${BEAMER_ARCH}" = arm64 ] \
    && [ "$(command od -An -t x1 -j 4 -N 1 "/sbin/init" 2>/dev/null)" = ' 01' ]\
  ; then
    BEAMER_ARCH=armv7l
    HOST_ARCH=armv7l
  fi

  if [ -f "/etc/alpine-release" ]; then
    BEAMER_ARCH=x64-musl
  fi

  beamer_echo "${BEAMER_ARCH}"
}

beamer_get_minor_version() {
  local VERSION
  VERSION="$1"

  if [ -z "${VERSION}" ]; then
    beamer_err 'a version is required'
    return 1
  fi

  case "${VERSION}" in
    v | .* | *..* | v*[!.0123456789]* | [!v]*[!.0123456789]* | [!v0123456789]* | v[!0123456789]*)
      beamer_err 'invalid version number'
      return 2
    ;;
  esac

  local PREFIXED_VERSION
  PREFIXED_VERSION="$(beamer_format_version "${VERSION}")"

  local MINOR
  MINOR="$(beamer_echo "${PREFIXED_VERSION}" | beamer_grep -e '^v' | command cut -c2- | command cut -d . -f 1,2)"
  if [ -z "${MINOR}" ]; then
    beamer_err 'invalid version number! (please report this)'
    return 3
  fi
  beamer_echo "${MINOR}"
}

beamer_ensure_default_set() {
  local VERSION
  VERSION="$1"
  if [ -z "${VERSION}" ]; then
    beamer_err 'beamer_ensure_default_set: a version is required'
    return 1
  elif beamer_alias default >/dev/null 2>&1; then
    # default already set
    return 0
  fi
  local OUTPUT
  OUTPUT="$(beamer alias default "${VERSION}")"
  local EXIT_CODE
  EXIT_CODE="$?"
  beamer_echo "Creating default alias: ${OUTPUT}"
  return $EXIT_CODE
}

beamer_is_merged_beam_version() {
  beamer_version_greater_than_or_equal_to "$1" v4.0.0
}

beamer_get_mirror() {
  local BEAMER_MIRROR
  BEAMER_MIRROR=''
  case "${1}-${2}" in
    beam-std) BEAMER_MIRROR="${BEAMER_BEAMJS_ORG_MIRROR:-https://beamjs.org/dist}" ;;
    iojs-std) BEAMER_MIRROR="${BEAMER_IOJS_ORG_MIRROR:-https://iojs.org/dist}" ;;
    *)
      beamer_err 'unknown type of beam.js or io.js release'
      return 1
    ;;
  esac

  case "${BEAMER_MIRROR}" in
    *\`* | *\\* | *\'* | *\(* | *' '* )
      beamer_err '$BEAMER_BEAMJS_ORG_MIRROR and $BEAMER_IOJS_ORG_MIRROR may only contain a URL'
      return 2
    ;;
  esac


  if ! beamer_echo "${BEAMER_MIRROR}" | command awk '{ $0 ~ "^https?://[a-zA-Z0-9./_-]+$" }'; then
      beamer_err '$BEAMER_BEAMJS_ORG_MIRROR and $BEAMER_IOJS_ORG_MIRROR may only contain a URL'
      return 2
  fi

  beamer_echo "${BEAMER_MIRROR}"
}

# args: os, prefixed version, version, tarball, extract directory
beamer_install_binary_extract() {
  if [ "$#" -ne 5 ]; then
    beamer_err 'beamer_install_binary_extract needs 5 parameters'
    return 1
  fi

  local BEAMER_OS
  local PREFIXED_VERSION
  local VERSION
  local TARBALL
  local TMPDIR
  BEAMER_OS="${1}"
  PREFIXED_VERSION="${2}"
  VERSION="${3}"
  TARBALL="${4}"
  TMPDIR="${5}"

  local VERSION_PATH

  [ -n "${TMPDIR-}" ] && \
  command mkdir -p "${TMPDIR}" && \
  VERSION_PATH="$(beamer_version_path "${PREFIXED_VERSION}")" || return 1

  # For Windows system (GitBash with MSYS, Cygwin)
  if [ "${BEAMER_OS}" = 'win' ]; then
    VERSION_PATH="${VERSION_PATH}/bin"
    command unzip -q "${TARBALL}" -d "${TMPDIR}" || return 1
  # For non Windows system (including WSL running on Windows)
  else
    beamer_extract_tarball "${BEAMER_OS}" "${VERSION}" "${TARBALL}" "${TMPDIR}"
  fi

  command mkdir -p "${VERSION_PATH}" || return 1

  if [ "${BEAMER_OS}" = 'win' ]; then
    command mv "${TMPDIR}/"*/* "${VERSION_PATH}/" || return 1
    command chmod +x "${VERSION_PATH}"/beam.exe || return 1
    command chmod +x "${VERSION_PATH}"/beamy || return 1
    command chmod +x "${VERSION_PATH}"/npx 2>/dev/null
  else
    command mv "${TMPDIR}/"* "${VERSION_PATH}" || return 1
  fi

  command rm -rf "${TMPDIR}"

  return 0
}

# args: flavor, type, version, reinstall
beamer_install_binary() {
  local FLAVOR
  case "${1-}" in
    beam | iojs) FLAVOR="${1}" ;;
    *)
      beamer_err 'supported flavors: beam, iojs'
      return 4
    ;;
  esac

  local TYPE
  TYPE="${2-}"

  local PREFIXED_VERSION
  PREFIXED_VERSION="${3-}"
  if [ -z "${PREFIXED_VERSION}" ]; then
    beamer_err 'A version number is required.'
    return 3
  fi

  local nosource
  nosource="${4-}"

  local VERSION
  VERSION="$(beamer_strip_iojs_prefix "${PREFIXED_VERSION}")"

  local BEAMER_OS
  BEAMER_OS="$(beamer_get_os)"

  if [ -z "${BEAMER_OS}" ]; then
    return 2
  fi

  local TARBALL
  local TMPDIR

  local PROGRESS_BAR
  local BEAM_OR_IOJS
  if [ "${FLAVOR}" = 'beam' ]; then
    BEAM_OR_IOJS="${FLAVOR}"
  elif [ "${FLAVOR}" = 'iojs' ]; then
    BEAM_OR_IOJS="io.js"
  fi
  if [ "${BEAMER_NO_PROGRESS-}" = "1" ]; then
    # --silent, --show-error, use short option as @samrocketman mentions the compatibility issue.
    PROGRESS_BAR="-sS"
  else
    PROGRESS_BAR="--progress-bar"
  fi
  beamer_echo "Downloading and installing ${BEAM_OR_IOJS-} ${VERSION}..."
  TARBALL="$(PROGRESS_BAR="${PROGRESS_BAR}" beamer_download_artifact "${FLAVOR}" binary "${TYPE-}" "${VERSION}" | command tail -1)"
  if [ -f "${TARBALL}" ]; then
    TMPDIR="$(dirname "${TARBALL}")/files"
  fi

  if beamer_install_binary_extract "${BEAMER_OS}" "${PREFIXED_VERSION}" "${VERSION}" "${TARBALL}" "${TMPDIR}"; then
    if [ -n "${ALIAS-}" ]; then
      beamer alias "${ALIAS}" "${provided_version}"
    fi
    return 0
  fi


  # Read nosource from arguments
  if [ "${nosource-}" = '1' ]; then
    beamer_err 'Binary download failed. Download from source aborted.'
    return 0
  fi

  beamer_err 'Binary download failed, trying source.'
  if [ -n "${TMPDIR-}" ]; then
    command rm -rf "${TMPDIR}"
  fi
  return 1
}

# args: flavor, kind, version
beamer_get_download_slug() {
  local FLAVOR
  case "${1-}" in
    beam | iojs) FLAVOR="${1}" ;;
    *)
      beamer_err 'supported flavors: beam, iojs'
      return 1
    ;;
  esac

  local KIND
  case "${2-}" in
    binary | source) KIND="${2}" ;;
    *)
      beamer_err 'supported kinds: binary, source'
      return 2
    ;;
  esac

  local VERSION
  VERSION="${3-}"

  local BEAMER_OS
  BEAMER_OS="$(beamer_get_os)"

  local BEAMER_ARCH
  BEAMER_ARCH="$(beamer_get_arch)"
  if ! beamer_is_merged_beam_version "${VERSION}"; then
    if [ "${BEAMER_ARCH}" = 'armv6l' ] || [ "${BEAMER_ARCH}" = 'armv7l' ]; then
      BEAMER_ARCH="arm-pi"
    fi
  fi

  # If running MAC M1 :: Node v14.17.0 was the first version to offer official experimental support:
  # https://github.com/beamjs/beam/issues/40126 (although binary distributions aren't available until v16)
  if \
    beamer_version_greater '14.17.0' "${VERSION}" \
    || (beamer_version_greater_than_or_equal_to "${VERSION}" '15.0.0' && beamer_version_greater '16.0.0' "${VERSION}") \
  ; then
    if [ "_${BEAMER_OS}" = '_darwin' ] && [ "${BEAMER_ARCH}" = 'arm64' ]; then
      BEAMER_ARCH=x64
    fi
  fi

  if [ "${KIND}" = 'binary' ]; then
    beamer_echo "${FLAVOR}-${VERSION}-${BEAMER_OS}-${BEAMER_ARCH}"
  elif [ "${KIND}" = 'source' ]; then
    beamer_echo "${FLAVOR}-${VERSION}"
  fi
}

beamer_get_artifact_compression() {
  local VERSION
  VERSION="${1-}"

  local BEAMER_OS
  BEAMER_OS="$(beamer_get_os)"

  local COMPRESSION
  COMPRESSION='tar.gz'
  if [ "_${BEAMER_OS}" = '_win' ]; then
    COMPRESSION='zip'
  elif beamer_supports_xz "${VERSION}"; then
    COMPRESSION='tar.xz'
  fi

  beamer_echo "${COMPRESSION}"
}

# args: flavor, kind, type, version
beamer_download_artifact() {
  local FLAVOR
  case "${1-}" in
    beam | iojs) FLAVOR="${1}" ;;
    *)
      beamer_err 'supported flavors: beam, iojs'
      return 1
    ;;
  esac

  local KIND
  case "${2-}" in
    binary | source) KIND="${2}" ;;
    *)
      beamer_err 'supported kinds: binary, source'
      return 1
    ;;
  esac

  local TYPE
  TYPE="${3-}"

  local MIRROR
  MIRROR="$(beamer_get_mirror "${FLAVOR}" "${TYPE}")"
  if [ -z "${MIRROR}" ]; then
    return 2
  fi

  local VERSION
  VERSION="${4}"

  if [ -z "${VERSION}" ]; then
    beamer_err 'A version number is required.'
    return 3
  fi

  if [ "${KIND}" = 'binary' ] && ! beamer_binary_available "${VERSION}"; then
    beamer_err "No precompiled binary available for ${VERSION}."
    return
  fi

  local SLUG
  SLUG="$(beamer_get_download_slug "${FLAVOR}" "${KIND}" "${VERSION}")"

  local COMPRESSION
  COMPRESSION="$(beamer_get_artifact_compression "${VERSION}")"

  local CHECKSUM
  CHECKSUM="$(beamer_get_checksum "${FLAVOR}" "${TYPE}" "${VERSION}" "${SLUG}" "${COMPRESSION}")"

  local tmpdir
  if [ "${KIND}" = 'binary' ]; then
    tmpdir="$(beamer_cache_dir)/bin/${SLUG}"
  else
    tmpdir="$(beamer_cache_dir)/src/${SLUG}"
  fi
  command mkdir -p "${tmpdir}/files" || (
    beamer_err "creating directory ${tmpdir}/files failed"
    return 3
  )

  local TARBALL
  TARBALL="${tmpdir}/${SLUG}.${COMPRESSION}"
  local TARBALL_URL
  if beamer_version_greater_than_or_equal_to "${VERSION}" 0.1.14; then
    TARBALL_URL="${MIRROR}/${VERSION}/${SLUG}.${COMPRESSION}"
  else
    # beam <= 0.1.13 does not have a directory
    TARBALL_URL="${MIRROR}/${SLUG}.${COMPRESSION}"
  fi

  if [ -r "${TARBALL}" ]; then
    beamer_err "Local cache found: $(beamer_sanitize_path "${TARBALL}")"
    if beamer_compare_checksum "${TARBALL}" "${CHECKSUM}" >/dev/null 2>&1; then
      beamer_err "Checksums match! Using existing downloaded archive $(beamer_sanitize_path "${TARBALL}")"
      beamer_echo "${TARBALL}"
      return 0
    fi
    beamer_compare_checksum "${TARBALL}" "${CHECKSUM}"
    beamer_err "Checksum check failed!"
    beamer_err "Removing the broken local cache..."
    command rm -rf "${TARBALL}"
  fi
  beamer_err "Downloading ${TARBALL_URL}..."
  beamer_download -L -C - "${PROGRESS_BAR}" "${TARBALL_URL}" -o "${TARBALL}" || (
    command rm -rf "${TARBALL}" "${tmpdir}"
    beamer_err "download from ${TARBALL_URL} failed"
    return 4
  )

  if beamer_grep '404 Not Found' "${TARBALL}" >/dev/null; then
    command rm -rf "${TARBALL}" "${tmpdir}"
    beamer_err "HTTP 404 at URL ${TARBALL_URL}"
    return 5
  fi

  beamer_compare_checksum "${TARBALL}" "${CHECKSUM}" || (
    command rm -rf "${tmpdir}/files"
    return 6
  )

  beamer_echo "${TARBALL}"
}

# args: beamer_os, version, tarball, tmpdir
beamer_extract_tarball() {
  if [ "$#" -ne 4 ]; then
    beamer_err 'beamer_extract_tarball requires exactly 4 arguments'
    return 5
  fi

  local BEAMER_OS
  BEAMER_OS="${1-}"

  local VERSION
  VERSION="${2-}"

  local TARBALL
  TARBALL="${3-}"

  local TMPDIR
  TMPDIR="${4-}"

  local tar_compression_flag
  tar_compression_flag='z'
  if beamer_supports_xz "${VERSION}"; then
    tar_compression_flag='J'
  fi

  local tar
  tar='tar'
  if [ "${BEAMER_OS}" = 'aix' ]; then
    tar='gtar'
  fi

  if [ "${BEAMER_OS}" = 'openbsd' ]; then
    if [ "${tar_compression_flag}" = 'J' ]; then
      command xzcat "${TARBALL}" | "${tar}" -xf - -C "${TMPDIR}" -s '/[^\/]*\///' || return 1
    else
      command "${tar}" -x${tar_compression_flag}f "${TARBALL}" -C "${TMPDIR}" -s '/[^\/]*\///' || return 1
    fi
  else
    command "${tar}" -x${tar_compression_flag}f "${TARBALL}" -C "${TMPDIR}" --strip-components 1 || return 1
  fi
}

beamer_get_make_jobs() {
  if beamer_is_natural_num "${1-}"; then
    BEAMER_MAKE_JOBS="$1"
    beamer_echo "number of \`make\` jobs: ${BEAMER_MAKE_JOBS}"
    return
  elif [ -n "${1-}" ]; then
    unset BEAMER_MAKE_JOBS
    beamer_err "$1 is invalid for number of \`make\` jobs, must be a natural number"
  fi
  local BEAMER_OS
  BEAMER_OS="$(beamer_get_os)"
  local BEAMER_CPU_CORES
  case "_${BEAMER_OS}" in
    "_linux")
      BEAMER_CPU_CORES="$(beamer_grep -c -E '^processor.+: [0-9]+' /proc/cpuinfo)"
    ;;
    "_freebsd" | "_darwin" | "_openbsd")
      BEAMER_CPU_CORES="$(sysctl -n hw.ncpu)"
    ;;
    "_sunos")
      BEAMER_CPU_CORES="$(psrinfo | wc -l)"
    ;;
    "_aix")
      BEAMER_CPU_CORES="$(pmcycles -m | wc -l)"
    ;;
  esac
  if ! beamer_is_natural_num "${BEAMER_CPU_CORES}"; then
    beamer_err 'Can not determine how many core(s) are available, running in single-threaded mode.'
    beamer_err 'Please report an issue on GitHub to help us make beamer run faster on your computer!'
    BEAMER_MAKE_JOBS=1
  else
    beamer_echo "Detected that you have ${BEAMER_CPU_CORES} CPU core(s)"
    if [ "${BEAMER_CPU_CORES}" -gt 2 ]; then
      BEAMER_MAKE_JOBS=$((BEAMER_CPU_CORES - 1))
      beamer_echo "Running with ${BEAMER_MAKE_JOBS} threads to speed up the build"
    else
      BEAMER_MAKE_JOBS=1
      beamer_echo 'Number of CPU core(s) less than or equal to 2, running in single-threaded mode'
    fi
  fi
}

# args: flavor, type, version, make jobs, additional
beamer_install_source() {
  local FLAVOR
  case "${1-}" in
    beam | iojs) FLAVOR="${1}" ;;
    *)
      beamer_err 'supported flavors: beam, iojs'
      return 4
    ;;
  esac

  local TYPE
  TYPE="${2-}"

  local PREFIXED_VERSION
  PREFIXED_VERSION="${3-}"
  if [ -z "${PREFIXED_VERSION}" ]; then
    beamer_err 'A version number is required.'
    return 3
  fi

  local VERSION
  VERSION="$(beamer_strip_iojs_prefix "${PREFIXED_VERSION}")"

  local BEAMER_MAKE_JOBS
  BEAMER_MAKE_JOBS="${4-}"

  local ADDITIONAL_PARAMETERS
  ADDITIONAL_PARAMETERS="${5-}"

  local BEAMER_ARCH
  BEAMER_ARCH="$(beamer_get_arch)"
  if [ "${BEAMER_ARCH}" = 'armv6l' ] || [ "${BEAMER_ARCH}" = 'armv7l' ]; then
    if [ -n "${ADDITIONAL_PARAMETERS}" ]; then
      ADDITIONAL_PARAMETERS="--without-snapshot ${ADDITIONAL_PARAMETERS}"
    else
      ADDITIONAL_PARAMETERS='--without-snapshot'
    fi
  fi

  if [ -n "${ADDITIONAL_PARAMETERS}" ]; then
    beamer_echo "Additional options while compiling: ${ADDITIONAL_PARAMETERS}"
  fi

  local BEAMER_OS
  BEAMER_OS="$(beamer_get_os)"

  local make
  make='make'
  local MAKE_CXX
  case "${BEAMER_OS}" in
    'freebsd' | 'openbsd')
      make='gmake'
      MAKE_CXX="CC=${CC:-cc} CXX=${CXX:-c++}"
    ;;
    'darwin')
      MAKE_CXX="CC=${CC:-cc} CXX=${CXX:-c++}"
    ;;
    'aix')
      make='gmake'
    ;;
  esac
  if beamer_has "clang++" && beamer_has "clang" && beamer_version_greater_than_or_equal_to "$(beamer_clang_version)" 3.5; then
    if [ -z "${CC-}" ] || [ -z "${CXX-}" ]; then
      beamer_echo "Clang v3.5+ detected! CC or CXX not specified, will use Clang as C/C++ compiler!"
      MAKE_CXX="CC=${CC:-cc} CXX=${CXX:-c++}"
    fi
  fi

  local TARBALL
  local TMPDIR
  local VERSION_PATH

  if [ "${BEAMER_NO_PROGRESS-}" = "1" ]; then
    # --silent, --show-error, use short option as @samrocketman mentions the compatibility issue.
    PROGRESS_BAR="-sS"
  else
    PROGRESS_BAR="--progress-bar"
  fi

  beamer_is_zsh && setopt local_options shwordsplit

  TARBALL="$(PROGRESS_BAR="${PROGRESS_BAR}" beamer_download_artifact "${FLAVOR}" source "${TYPE}" "${VERSION}" | command tail -1)" && \
  [ -f "${TARBALL}" ] && \
  TMPDIR="$(dirname "${TARBALL}")/files" && \
  if ! (
    # shellcheck disable=SC2086
    command mkdir -p "${TMPDIR}" && \
    beamer_extract_tarball "${BEAMER_OS}" "${VERSION}" "${TARBALL}" "${TMPDIR}" && \
    VERSION_PATH="$(beamer_version_path "${PREFIXED_VERSION}")" && \
    beamer_cd "${TMPDIR}" && \
    beamer_echo '$>'./configure --prefix="${VERSION_PATH}" $ADDITIONAL_PARAMETERS'<' && \
    ./configure --prefix="${VERSION_PATH}" $ADDITIONAL_PARAMETERS && \
    $make -j "${BEAMER_MAKE_JOBS}" ${MAKE_CXX-} && \
    command rm -f "${VERSION_PATH}" 2>/dev/null && \
    $make -j "${BEAMER_MAKE_JOBS}" ${MAKE_CXX-} install
  ); then
    beamer_err "beamer: install ${VERSION} failed!"
    command rm -rf "${TMPDIR-}"
    return 1
  fi
}

beamer_use_if_needed() {
  if [ "_${1-}" = "_$(beamer_ls_current)" ]; then
    return
  fi
  beamer use "$@"
}

beamer_install_beamy_if_needed() {
  local VERSION
  VERSION="$(beamer_ls_current)"
  if ! beamer_has "beamy"; then
    beamer_echo 'Installing beamy...'
    if beamer_version_greater 0.2.0 "${VERSION}"; then
      beamer_err 'beamy requires beam v0.2.3 or higher'
    elif beamer_version_greater_than_or_equal_to "${VERSION}" 0.2.0; then
      if beamer_version_greater 0.2.3 "${VERSION}"; then
        beamer_err 'beamy requires beam v0.2.3 or higher'
      else
        beamer_download -L https://beamyjs.org/install.sh -o - | clean=yes beamy_install=0.2.19 sh
      fi
    else
      beamer_download -L https://beamyjs.org/install.sh -o - | clean=yes sh
    fi
  fi
  return $?
}

beamer_match_version() {
  local BEAMER_IOJS_PREFIX
  BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
  local PROVIDED_VERSION
  PROVIDED_VERSION="$1"
  case "_${PROVIDED_VERSION}" in
    "_${BEAMER_IOJS_PREFIX}" | '_io.js')
      beamer_version "${BEAMER_IOJS_PREFIX}"
    ;;
    '_system')
      beamer_echo 'system'
    ;;
    *)
      beamer_version "${PROVIDED_VERSION}"
    ;;
  esac
}

beamer_beamy_global_modules() {
  local BEAMYLIST
  local VERSION
  VERSION="$1"
  BEAMYLIST=$(beamer use "${VERSION}" >/dev/null && beamy list -g --depth=0 2>/dev/null | command sed 1,1d | beamer_grep -v 'UNMET PEER DEPENDENCY')

  local INSTALLS
  INSTALLS=$(beamer_echo "${BEAMYLIST}" | command sed -e '/ -> / d' -e '/\(empty\)/ d' -e 's/^.* \(.*@[^ ]*\).*/\1/' -e '/^beamy@[^ ]*.*$/ d' | command xargs)

  local LINKS
  LINKS="$(beamer_echo "${BEAMYLIST}" | command sed -n 's/.* -> \(.*\)/\1/ p')"

  beamer_echo "${INSTALLS} //// ${LINKS}"
}

beamer_beamyrc_bad_news_bears() {
  local BEAMER_BEAMYRC
  BEAMER_BEAMYRC="${1-}"
  if [ -n "${BEAMER_BEAMYRC}" ] && [ -f "${BEAMER_BEAMYRC}" ] && beamer_grep -Ee '^(prefix|globalconfig) *=' <"${BEAMER_BEAMYRC}" >/dev/null; then
    return 0
  fi
  return 1
}

beamer_die_on_prefix() {
  local BEAMER_DELETE_PREFIX
  BEAMER_DELETE_PREFIX="${1-}"
  case "${BEAMER_DELETE_PREFIX}" in
    0 | 1) ;;
    *)
      beamer_err 'First argument "delete the prefix" must be zero or one'
      return 1
    ;;
  esac
  local BEAMER_COMMAND
  BEAMER_COMMAND="${2-}"
  local BEAMER_VERSION_DIR
  BEAMER_VERSION_DIR="${3-}"
  if [ -z "${BEAMER_COMMAND}" ] || [ -z "${BEAMER_VERSION_DIR}" ]; then
    beamer_err 'Second argument "beamer command", and third argument "beamer version dir", must both be nonempty'
    return 2
  fi

  # beamy first looks at $PREFIX (case-sensitive)
  # we do not bother to test the value here; if this env var is set, unset it to continue.
  # however, `beamy exec` in beamy v7.2+ sets $PREFIX; if set, inherit it
  if [ -n "${PREFIX-}" ] && [ "$(beamer_version_path "$(beam -v)")" != "${PREFIX}" ]; then
    beamer deactivate >/dev/null 2>&1
    beamer_err "beamer is not compatible with the \"PREFIX\" environment variable: currently set to \"${PREFIX}\""
    beamer_err 'Run `unset PREFIX` to unset it.'
    return 3
  fi

  local BEAMER_OS
  BEAMER_OS="$(beamer_get_os)"

  # beamy normalizes BEAMY_CONFIG_-prefixed env vars
  # https://github.com/beamy/beamyconf/blob/22827e4038d6eebaafeb5c13ed2b92cf97b8fb82/beamyconf.js#L331-L348
  # https://github.com/beamy/beamy/blob/5e426a78ca02d0044f8dd26e0c5f881217081cbd/lib/config/core.js#L343-L359
  #
  # here, we avoid trying to replicate "which one wins" or testing the value; if any are defined, it errors
  # until none are left.
  local BEAMER_BEAMY_CONFIG_x_PREFIX_ENV
  BEAMER_BEAMY_CONFIG_x_PREFIX_ENV="$(command awk 'BEGIN { for (name in ENVIRON) if (toupper(name) == "BEAMY_CONFIG_PREFIX") { print name; break } }')"
  if [ -n "${BEAMER_BEAMY_CONFIG_x_PREFIX_ENV-}" ]; then
    local BEAMER_CONFIG_VALUE
    eval "BEAMER_CONFIG_VALUE=\"\$${BEAMER_BEAMY_CONFIG_x_PREFIX_ENV}\""
    if [ -n "${BEAMER_CONFIG_VALUE-}" ] && [ "_${BEAMER_OS}" = "_win" ]; then
      BEAMER_CONFIG_VALUE="$(cd "$BEAMER_CONFIG_VALUE" 2>/dev/null && pwd)"
    fi
    if [ -n "${BEAMER_CONFIG_VALUE-}" ] && ! beamer_tree_contains_path "${BEAMER_DIR}" "${BEAMER_CONFIG_VALUE}"; then
      beamer deactivate >/dev/null 2>&1
      beamer_err "beamer is not compatible with the \"${BEAMER_BEAMY_CONFIG_x_PREFIX_ENV}\" environment variable: currently set to \"${BEAMER_CONFIG_VALUE}\""
      beamer_err "Run \`unset ${BEAMER_BEAMY_CONFIG_x_PREFIX_ENV}\` to unset it."
      return 4
    fi
  fi

  # here, beamy config checks beamyrc files.
  # the stack is: cli, env, project, user, global, builtin, defaults
  # cli does not apply; env is covered above, defaults don't exist for prefix
  # there are 4 beamyrc locations to check: project, global, user, and builtin
  # project: find the closest beam_modules or package.json-containing dir, `.beamyrc`
  # global: default prefix + `/etc/beamyrc`
  # user: $HOME/.beamyrc
  # builtin: beamy install location, `beamyrc`
  #
  # if any of them have a `prefix`, fail.
  # if any have `globalconfig`, fail also, just in case, to avoid spidering configs.

  local BEAMER_BEAMY_BUILTIN_BEAMYRC
  BEAMER_BEAMY_BUILTIN_BEAMYRC="${BEAMER_VERSION_DIR}/lib/beam_modules/beamy/beamyrc"
  if beamer_beamyrc_bad_news_bears "${BEAMER_BEAMY_BUILTIN_BEAMYRC}"; then
    if [ "_${BEAMER_DELETE_PREFIX}" = "_1" ]; then
      beamy config --loglevel=warn delete prefix --userconfig="${BEAMER_BEAMY_BUILTIN_BEAMYRC}"
      beamy config --loglevel=warn delete globalconfig --userconfig="${BEAMER_BEAMY_BUILTIN_BEAMYRC}"
    else
      beamer_err "Your builtin beamyrc file ($(beamer_sanitize_path "${BEAMER_BEAMY_BUILTIN_BEAMYRC}"))"
      beamer_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with beamer.'
      beamer_err "Run \`${BEAMER_COMMAND}\` to unset it."
      return 10
    fi
  fi

  local BEAMER_BEAMY_GLOBAL_BEAMYRC
  BEAMER_BEAMY_GLOBAL_BEAMYRC="${BEAMER_VERSION_DIR}/etc/beamyrc"
  if beamer_beamyrc_bad_news_bears "${BEAMER_BEAMY_GLOBAL_BEAMYRC}"; then
    if [ "_${BEAMER_DELETE_PREFIX}" = "_1" ]; then
      beamy config --global --loglevel=warn delete prefix
      beamy config --global --loglevel=warn delete globalconfig
    else
      beamer_err "Your global beamyrc file ($(beamer_sanitize_path "${BEAMER_BEAMY_GLOBAL_BEAMYRC}"))"
      beamer_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with beamer.'
      beamer_err "Run \`${BEAMER_COMMAND}\` to unset it."
      return 10
    fi
  fi

  local BEAMER_BEAMY_USER_BEAMYRC
  BEAMER_BEAMY_USER_BEAMYRC="${HOME}/.beamyrc"
  if beamer_beamyrc_bad_news_bears "${BEAMER_BEAMY_USER_BEAMYRC}"; then
    if [ "_${BEAMER_DELETE_PREFIX}" = "_1" ]; then
      beamy config --loglevel=warn delete prefix --userconfig="${BEAMER_BEAMY_USER_BEAMYRC}"
      beamy config --loglevel=warn delete globalconfig --userconfig="${BEAMER_BEAMY_USER_BEAMYRC}"
    else
      beamer_err "Your user’s .beamyrc file ($(beamer_sanitize_path "${BEAMER_BEAMY_USER_BEAMYRC}"))"
      beamer_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with beamer.'
      beamer_err "Run \`${BEAMER_COMMAND}\` to unset it."
      return 10
    fi
  fi

  local BEAMER_BEAMY_PROJECT_BEAMYRC
  BEAMER_BEAMY_PROJECT_BEAMYRC="$(beamer_find_project_dir)/.beamyrc"
  if beamer_beamyrc_bad_news_bears "${BEAMER_BEAMY_PROJECT_BEAMYRC}"; then
    if [ "_${BEAMER_DELETE_PREFIX}" = "_1" ]; then
      beamy config --loglevel=warn delete prefix
      beamy config --loglevel=warn delete globalconfig
    else
      beamer_err "Your project beamyrc file ($(beamer_sanitize_path "${BEAMER_BEAMY_PROJECT_BEAMYRC}"))"
      beamer_err 'has a `globalconfig` and/or a `prefix` setting, which are incompatible with beamer.'
      beamer_err "Run \`${BEAMER_COMMAND}\` to unset it."
      return 10
    fi
  fi
}

# Succeeds if $IOJS_VERSION represents an io.js version that has a
# Solaris binary, fails otherwise.
# Currently, only io.js 3.3.1 has a Solaris binary available, and it's the
# latest io.js version available. The expectation is that any potential io.js
# version later than v3.3.1 will also have Solaris binaries.
beamer_iojs_version_has_solaris_binary() {
  local IOJS_VERSION
  IOJS_VERSION="$1"
  local STRIPPED_IOJS_VERSION
  STRIPPED_IOJS_VERSION="$(beamer_strip_iojs_prefix "${IOJS_VERSION}")"
  if [ "_${STRIPPED_IOJS_VERSION}" = "${IOJS_VERSION}" ]; then
    return 1
  fi

  # io.js started shipping Solaris binaries with io.js v3.3.1
  beamer_version_greater_than_or_equal_to "${STRIPPED_IOJS_VERSION}" v3.3.1
}

# Succeeds if $BEAM_VERSION represents a beam version that has a
# Solaris binary, fails otherwise.
# Currently, beam versions starting from v0.8.6 have a Solaris binary
# available.
beamer_beam_version_has_solaris_binary() {
  local BEAM_VERSION
  BEAM_VERSION="$1"
  # Error out if $BEAM_VERSION is actually an io.js version
  local STRIPPED_IOJS_VERSION
  STRIPPED_IOJS_VERSION="$(beamer_strip_iojs_prefix "${BEAM_VERSION}")"
  if [ "_${STRIPPED_IOJS_VERSION}" != "_${BEAM_VERSION}" ]; then
    return 1
  fi

  # beam (unmerged) started shipping Solaris binaries with v0.8.6 and
  # beam versions v1.0.0 or greater are not considered valid "unmerged" beam
  # versions.
  beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" v0.8.6 \
  && ! beamer_version_greater_than_or_equal_to "${BEAM_VERSION}" v1.0.0
}

# Succeeds if $VERSION represents a version (beam, io.js or merged) that has a
# Solaris binary, fails otherwise.
beamer_has_solaris_binary() {
  local VERSION="${1-}"
  if beamer_is_merged_beam_version "${VERSION}"; then
    return 0 # All merged beam versions have a Solaris binary
  elif beamer_is_iojs_version "${VERSION}"; then
    beamer_iojs_version_has_solaris_binary "${VERSION}"
  else
    beamer_beam_version_has_solaris_binary "${VERSION}"
  fi
}

beamer_sanitize_path() {
  local SANITIZED_PATH
  SANITIZED_PATH="${1-}"
  if [ "_${SANITIZED_PATH}" != "_${BEAMER_DIR}" ]; then
    SANITIZED_PATH="$(beamer_echo "${SANITIZED_PATH}" | command sed -e "s#${BEAMER_DIR}#\${BEAMER_DIR}#g")"
  fi
  if [ "_${SANITIZED_PATH}" != "_${HOME}" ]; then
    SANITIZED_PATH="$(beamer_echo "${SANITIZED_PATH}" | command sed -e "s#${HOME}#\${HOME}#g")"
  fi
  beamer_echo "${SANITIZED_PATH}"
}

beamer_is_natural_num() {
  if [ -z "$1" ]; then
    return 4
  fi
  case "$1" in
    0) return 1 ;;
    -*) return 3 ;; # some BSDs return false positives for double-negated args
    *)
      [ "$1" -eq "$1" ] 2>/dev/null # returns 2 if it doesn't match
    ;;
  esac
}

beamer_write_beamerrc() {
  local VERSION_STRING
  VERSION_STRING=$(beamer_version "${1-}")
  if [ "${VERSION_STRING}" = '∞' ] || [ "${VERSION_STRING}" = 'N/A' ]; then
    return 1
  fi
  echo "${VERSION_STRING}" | tee "$PWD"/.beamerrc > /dev/null || {
    if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
      beamer_err "Warning: Unable to write version number ($VERSION_STRING) to .beamerrc"
    fi
    return 3
  }
  if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
    beamer_echo "Wrote version number ($VERSION_STRING) to .beamerrc"
  fi
}

# Check version dir permissions
beamer_check_file_permissions() {
  beamer_is_zsh && setopt local_options nonomatch
  for FILE in "$1"/* "$1"/.[!.]* "$1"/..?* ; do
    if [ -d "$FILE" ]; then
      if [ -n "${BEAMER_DEBUG-}" ]; then
        beamer_err "${FILE}"
      fi
      if [ ! -L "${FILE}" ] && ! beamer_check_file_permissions "${FILE}"; then
        return 2
      fi
    elif [ -e "$FILE" ] && [ ! -w "$FILE" ] && [ ! -O "$FILE" ]; then
      beamer_err "file is not writable or self-owned: $(beamer_sanitize_path "$FILE")"
      return 1
    fi
  done
  return 0
}

beamer_cache_dir() {
  beamer_echo "${BEAMER_DIR}/.cache"
}

beamer() {
  if [ "$#" -lt 1 ]; then
    beamer --help
    return
  fi

  local DEFAULT_IFS
  DEFAULT_IFS=" $(beamer_echo t | command tr t \\t)
"
  if [ "${-#*e}" != "$-" ]; then
    set +e
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" beamer "$@"
    EXIT_CODE="$?"
    set -e
    return "$EXIT_CODE"
  elif [ "${-#*a}" != "$-" ]; then
    set +a
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" beamer "$@"
    EXIT_CODE="$?"
    set -a
    return "$EXIT_CODE"
  elif [ -n "${BASH-}" ] && [ "${-#*E}" != "$-" ]; then
    # shellcheck disable=SC3041
    set +E
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" beamer "$@"
    EXIT_CODE="$?"
    # shellcheck disable=SC3041
    set -E
    return "$EXIT_CODE"
  elif [ "${IFS}" != "${DEFAULT_IFS}" ]; then
    IFS="${DEFAULT_IFS}" beamer "$@"
    return "$?"
  fi

  local i
  for i in "$@"
  do
    case $i in
      --) break ;;
      '-h'|'help'|'--help')
        BEAMER_NO_COLORS=""
        for j in "$@"; do
          if [ "${j}" = '--no-colors' ]; then
            BEAMER_NO_COLORS="${j}"
            break
          fi
        done

        local BEAMER_IOJS_PREFIX
        BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
        local BEAMER_BEAM_PREFIX
        BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"
        BEAMER_VERSION="$(beamer --version)"
        beamer_echo
        beamer_echo "Node Version Manager (v${BEAMER_VERSION})"
        beamer_echo
        beamer_echo 'Note: <version> refers to any version-like string beamer understands. This includes:'
        beamer_echo '  - full or partial version numbers, starting with an optional "v" (0.10, v0.1.2, v1)'
        beamer_echo "  - default (built-in) aliases: ${BEAMER_BEAM_PREFIX}, stable, unstable, ${BEAMER_IOJS_PREFIX}, system"
        beamer_echo '  - custom aliases you define with `beamer alias foo`'
        beamer_echo
        beamer_echo ' Any options that produce colorized output should respect the `--no-colors` option.'
        beamer_echo
        beamer_echo 'Usage:'
        beamer_echo '  beamer --help                                  Show this message'
        beamer_echo '    --no-colors                               Suppress colored output'
        beamer_echo '  beamer --version                               Print out the installed version of beamer'
        beamer_echo '  beamer install [<version>]                     Download and install a <version>. Uses .beamerrc if available and version is omitted.'
        beamer_echo '   The following optional arguments, if provided, must appear directly after `beamer install`:'
        beamer_echo '    -s                                        Skip binary download, install from source only.'
        beamer_echo '    -b                                        Skip source download, install from binary only.'
        beamer_echo '    --reinstall-packages-from=<version>       When installing, reinstall packages installed in <beam|iojs|beam version number>'
        beamer_echo '    --lts                                     When installing, only select from LTS (long-term support) versions'
        beamer_echo '    --lts=<LTS name>                          When installing, only select from versions for a specific LTS line'
        beamer_echo '    --skip-default-packages                   When installing, skip the default-packages file if it exists'
        beamer_echo '    --latest-beamy                              After installing, attempt to upgrade to the latest working beamy on the given beam version'
        beamer_echo '    --no-progress                             Disable the progress bar on any downloads'
        beamer_echo '    --alias=<name>                            After installing, set the alias specified to the version specified. (same as: beamer alias <name> <version>)'
        beamer_echo '    --default                                 After installing, set default alias to the version specified. (same as: beamer alias default <version>)'
        beamer_echo '    --save                                    After installing, write the specified version to .beamerrc'
        beamer_echo '  beamer uninstall <version>                     Uninstall a version'
        beamer_echo '  beamer uninstall --lts                         Uninstall using automatic LTS (long-term support) alias `lts/*`, if available.'
        beamer_echo '  beamer uninstall --lts=<LTS name>              Uninstall using automatic alias for provided LTS line, if available.'
        beamer_echo '  beamer use [<version>]                         Modify PATH to use <version>. Uses .beamerrc if available and version is omitted.'
        beamer_echo '   The following optional arguments, if provided, must appear directly after `beamer use`:'
        beamer_echo '    --silent                                  Silences stdout/stderr output'
        beamer_echo '    --lts                                     Uses automatic LTS (long-term support) alias `lts/*`, if available.'
        beamer_echo '    --lts=<LTS name>                          Uses automatic alias for provided LTS line, if available.'
        beamer_echo '    --save                                    Writes the specified version to .beamerrc.'
        beamer_echo '  beamer exec [<version>] [<command>]            Run <command> on <version>. Uses .beamerrc if available and version is omitted.'
        beamer_echo '   The following optional arguments, if provided, must appear directly after `beamer exec`:'
        beamer_echo '    --silent                                  Silences stdout/stderr output'
        beamer_echo '    --lts                                     Uses automatic LTS (long-term support) alias `lts/*`, if available.'
        beamer_echo '    --lts=<LTS name>                          Uses automatic alias for provided LTS line, if available.'
        beamer_echo '  beamer run [<version>] [<args>]                Run `beam` on <version> with <args> as arguments. Uses .beamerrc if available and version is omitted.'
        beamer_echo '   The following optional arguments, if provided, must appear directly after `beamer run`:'
        beamer_echo '    --silent                                  Silences stdout/stderr output'
        beamer_echo '    --lts                                     Uses automatic LTS (long-term support) alias `lts/*`, if available.'
        beamer_echo '    --lts=<LTS name>                          Uses automatic alias for provided LTS line, if available.'
        beamer_echo '  beamer current                                 Display currently activated version of Node'
        beamer_echo '  beamer ls [<version>]                          List installed versions, matching a given <version> if provided'
        beamer_echo '    --no-colors                               Suppress colored output'
        beamer_echo '    --no-alias                                Suppress `beamer alias` output'
        beamer_echo '  beamer ls-remote [<version>]                   List remote versions available for install, matching a given <version> if provided'
        beamer_echo '    --lts                                     When listing, only show LTS (long-term support) versions'
        beamer_echo '    --lts=<LTS name>                          When listing, only show versions for a specific LTS line'
        beamer_echo '    --no-colors                               Suppress colored output'
        beamer_echo '  beamer version <version>                       Resolve the given description to a single local version'
        beamer_echo '  beamer version-remote <version>                Resolve the given description to a single remote version'
        beamer_echo '    --lts                                     When listing, only select from LTS (long-term support) versions'
        beamer_echo '    --lts=<LTS name>                          When listing, only select from versions for a specific LTS line'
        beamer_echo '  beamer deactivate                              Undo effects of `beamer` on current shell'
        beamer_echo '    --silent                                  Silences stdout/stderr output'
        beamer_echo '  beamer alias [<pattern>]                       Show all aliases beginning with <pattern>'
        beamer_echo '    --no-colors                               Suppress colored output'
        beamer_echo '  beamer alias <name> <version>                  Set an alias named <name> pointing to <version>'
        beamer_echo '  beamer unalias <name>                          Deletes the alias named <name>'
        beamer_echo '  beamer install-latest-beamy                      Attempt to upgrade to the latest working `beamy` on the current beam version'
        beamer_echo '  beamer reinstall-packages <version>            Reinstall global `beamy` packages contained in <version> to current version'
        beamer_echo '  beamer unload                                  Unload `beamer` from shell'
        beamer_echo '  beamer which [current | <version>]             Display path to installed beam version. Uses .beamerrc if available and version is omitted.'
        beamer_echo '    --silent                                  Silences stdout/stderr output when a version is omitted'
        beamer_echo '  beamer cache dir                               Display path to the cache directory for beamer'
        beamer_echo '  beamer cache clear                             Empty cache directory for beamer'
        beamer_echo '  beamer set-colors [<color codes>]              Set five text colors using format "yMeBg". Available when supported.'
        beamer_echo '                                               Initial colors are:'
        beamer_echo_with_colors "                                                  $(beamer_wrap_with_color_code 'b' 'b')$(beamer_wrap_with_color_code 'y' 'y')$(beamer_wrap_with_color_code 'g' 'g')$(beamer_wrap_with_color_code 'r' 'r')$(beamer_wrap_with_color_code 'e' 'e')"
        beamer_echo '                                               Color codes:'
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'r' 'r')/$(beamer_wrap_with_color_code 'R' 'R') = $(beamer_wrap_with_color_code 'r' 'red') / $(beamer_wrap_with_color_code 'R' 'bold red')"
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'g' 'g')/$(beamer_wrap_with_color_code 'G' 'G') = $(beamer_wrap_with_color_code 'g' 'green') / $(beamer_wrap_with_color_code 'G' 'bold green')"
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'b' 'b')/$(beamer_wrap_with_color_code 'B' 'B') = $(beamer_wrap_with_color_code 'b' 'blue') / $(beamer_wrap_with_color_code 'B' 'bold blue')"
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'c' 'c')/$(beamer_wrap_with_color_code 'C' 'C') = $(beamer_wrap_with_color_code 'c' 'cyan') / $(beamer_wrap_with_color_code 'C' 'bold cyan')"
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'm' 'm')/$(beamer_wrap_with_color_code 'M' 'M') = $(beamer_wrap_with_color_code 'm' 'magenta') / $(beamer_wrap_with_color_code 'M' 'bold magenta')"
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'y' 'y')/$(beamer_wrap_with_color_code 'Y' 'Y') = $(beamer_wrap_with_color_code 'y' 'yellow') / $(beamer_wrap_with_color_code 'Y' 'bold yellow')"
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'k' 'k')/$(beamer_wrap_with_color_code 'K' 'K') = $(beamer_wrap_with_color_code 'k' 'black') / $(beamer_wrap_with_color_code 'K' 'bold black')"
        beamer_echo_with_colors "                                                $(beamer_wrap_with_color_code 'e' 'e')/$(beamer_wrap_with_color_code 'W' 'W') = $(beamer_wrap_with_color_code 'e' 'light grey') / $(beamer_wrap_with_color_code 'W' 'white')"
        beamer_echo 'Example:'
        beamer_echo '  beamer install 8.0.0                     Install a specific version number'
        beamer_echo '  beamer use 8.0                           Use the latest available 8.0.x release'
        beamer_echo '  beamer run 6.10.3 app.js                 Run app.js using beam 6.10.3'
        beamer_echo '  beamer exec 4.8.3 beam app.js            Run `beam app.js` with the PATH pointing to beam 4.8.3'
        beamer_echo '  beamer alias default 8.1.0               Set default beam version on a shell'
        beamer_echo '  beamer alias default beam                Always default to the latest available beam version on a shell'
        beamer_echo
        beamer_echo '  beamer install beam                      Install the latest available version'
        beamer_echo '  beamer use beam                          Use the latest version'
        beamer_echo '  beamer install --lts                     Install the latest LTS version'
        beamer_echo '  beamer use --lts                         Use the latest LTS version'
        beamer_echo
        beamer_echo '  beamer set-colors cgYmW                  Set text colors to cyan, green, bold yellow, magenta, and white'
        beamer_echo
        beamer_echo 'Note:'
        beamer_echo '  to remove, delete, or uninstall beamer - just remove the `$BEAMER_DIR` folder (usually `~/.beamer`)'
        beamer_echo
        return 0;
      ;;
    esac
  done

  local COMMAND
  COMMAND="${1-}"
  shift

  # initialize local variables
  local VERSION
  local ADDITIONAL_PARAMETERS

  case $COMMAND in
    "cache")
      case "${1-}" in
        dir) beamer_cache_dir ;;
        clear)
          local DIR
          DIR="$(beamer_cache_dir)"
          if command rm -rf "${DIR}" && command mkdir -p "${DIR}"; then
            beamer_echo 'beamer cache cleared.'
          else
            beamer_err "Unable to clear beamer cache: ${DIR}"
            return 1
          fi
        ;;
        *)
          >&2 beamer --help
          return 127
        ;;
      esac
    ;;

    "debug")
      local OS_VERSION
      beamer_is_zsh && setopt local_options shwordsplit
      beamer_err "beamer --version: v$(beamer --version)"
      if [ -n "${TERM_PROGRAM-}" ]; then
        beamer_err "\$TERM_PROGRAM: ${TERM_PROGRAM}"
      fi
      beamer_err "\$SHELL: ${SHELL}"
      # shellcheck disable=SC2169,SC3028
      beamer_err "\$SHLVL: ${SHLVL-}"
      beamer_err "whoami: '$(whoami)'"
      beamer_err "\${HOME}: ${HOME}"
      beamer_err "\${BEAMER_DIR}: '$(beamer_sanitize_path "${BEAMER_DIR}")'"
      beamer_err "\${PATH}: $(beamer_sanitize_path "${PATH}")"
      beamer_err "\$PREFIX: '$(beamer_sanitize_path "${PREFIX}")'"
      beamer_err "\${BEAMY_CONFIG_PREFIX}: '$(beamer_sanitize_path "${BEAMY_CONFIG_PREFIX}")'"
      beamer_err "\$BEAMER_BEAMJS_ORG_MIRROR: '${BEAMER_BEAMJS_ORG_MIRROR}'"
      beamer_err "\$BEAMER_IOJS_ORG_MIRROR: '${BEAMER_IOJS_ORG_MIRROR}'"
      beamer_err "shell version: '$(${SHELL} --version | command head -n 1)'"
      beamer_err "uname -a: '$(command uname -a | command awk '{$2=""; print}' | command xargs)'"
      beamer_err "checksum binary: '$(beamer_get_checksum_binary 2>/dev/null)'"
      if [ "$(beamer_get_os)" = "darwin" ] && beamer_has sw_vers; then
        OS_VERSION="$(sw_vers | command awk '{print $2}' | command xargs)"
      elif [ -r "/etc/issue" ]; then
        OS_VERSION="$(command head -n 1 /etc/issue | command sed 's/\\.//g')"
        if [ -z "${OS_VERSION}" ] && [ -r "/etc/os-release" ]; then
          # shellcheck disable=SC1091
          OS_VERSION="$(. /etc/os-release && echo "${NAME}" "${VERSION}")"
        fi
      fi
      if [ -n "${OS_VERSION}" ]; then
        beamer_err "OS version: ${OS_VERSION}"
      fi
      if beamer_has "awk"; then
        beamer_err "awk: $(beamer_command_info awk), $({ command awk --version 2>/dev/null || command awk -W version; } \
          | command head -n 1)"
      else
        beamer_err "awk: not found"
      fi
      if beamer_has "curl"; then
        beamer_err "curl: $(beamer_command_info curl), $(command curl -V | command head -n 1)"
      else
        beamer_err "curl: not found"
      fi
      if beamer_has "wget"; then
        beamer_err "wget: $(beamer_command_info wget), $(command wget -V | command head -n 1)"
      else
        beamer_err "wget: not found"
      fi

      local TEST_TOOLS ADD_TEST_TOOLS
      TEST_TOOLS="git grep"
      ADD_TEST_TOOLS="sed cut basename rm mkdir xargs"
      if [ "darwin" != "$(beamer_get_os)" ] && [ "freebsd" != "$(beamer_get_os)" ]; then
        TEST_TOOLS="${TEST_TOOLS} ${ADD_TEST_TOOLS}"
      else
        for tool in ${ADD_TEST_TOOLS} ; do
          if beamer_has "${tool}"; then
            beamer_err "${tool}: $(beamer_command_info "${tool}")"
          else
            beamer_err "${tool}: not found"
          fi
        done
      fi
      for tool in ${TEST_TOOLS} ; do
        local BEAMER_TOOL_VERSION
        if beamer_has "${tool}"; then
          if command ls -l "$(beamer_command_info "${tool}" | command awk '{print $1}')" | command grep -q busybox; then
            BEAMER_TOOL_VERSION="$(command "${tool}" --help 2>&1 | command head -n 1)"
          else
            BEAMER_TOOL_VERSION="$(command "${tool}" --version 2>&1 | command head -n 1)"
          fi
          beamer_err "${tool}: $(beamer_command_info "${tool}"), ${BEAMER_TOOL_VERSION}"
        else
          beamer_err "${tool}: not found"
        fi
        unset BEAMER_TOOL_VERSION
      done
      unset TEST_TOOLS ADD_TEST_TOOLS

      local BEAMER_DEBUG_OUTPUT
      for BEAMER_DEBUG_COMMAND in 'beamer current' 'which beam' 'which iojs' 'which beamy' 'beamy config get prefix' 'beamy root -g'; do
        BEAMER_DEBUG_OUTPUT="$(${BEAMER_DEBUG_COMMAND} 2>&1)"
        beamer_err "${BEAMER_DEBUG_COMMAND}: $(beamer_sanitize_path "${BEAMER_DEBUG_OUTPUT}")"
      done
      return 42
    ;;

    "install" | "i")
      local version_not_provided
      version_not_provided=0
      local BEAMER_OS
      BEAMER_OS="$(beamer_get_os)"

      if ! beamer_has "curl" && ! beamer_has "wget"; then
        beamer_err 'beamer needs curl or wget to proceed.'
        return 1
      fi

      if [ $# -lt 1 ]; then
        version_not_provided=1
      fi

      local nobinary
      local nosource
      local noprogress
      nobinary=0
      noprogress=0
      nosource=0
      local LTS
      local ALIAS
      local BEAMER_UPGRADE_BEAMY
      BEAMER_UPGRADE_BEAMY=0
      local BEAMER_WRITE_TO_BEAMERRC
      BEAMER_WRITE_TO_BEAMERRC=0

      local PROVIDED_REINSTALL_PACKAGES_FROM
      local REINSTALL_PACKAGES_FROM
      local SKIP_DEFAULT_PACKAGES

      while [ $# -ne 0 ]; do
        case "$1" in
          ---*)
            beamer_err 'arguments with `---` are not supported - this is likely a typo'
            return 55;
          ;;
          -s)
            shift # consume "-s"
            nobinary=1
            if [ $nosource -eq 1 ]; then
                beamer err '-s and -b cannot be set together since they would skip install from both binary and source'
                return 6
            fi
          ;;
          -b)
            shift # consume "-b"
            nosource=1
            if [ $nobinary -eq 1 ]; then
                beamer err '-s and -b cannot be set together since they would skip install from both binary and source'
                return 6
            fi
          ;;
          -j)
            shift # consume "-j"
            beamer_get_make_jobs "$1"
            shift # consume job count
          ;;
          --no-progress)
            noprogress=1
            shift
          ;;
          --lts)
            LTS='*'
            shift
          ;;
          --lts=*)
            LTS="${1##--lts=}"
            shift
          ;;
          --latest-beamy)
            BEAMER_UPGRADE_BEAMY=1
            shift
          ;;
          --default)
            if [ -n "${ALIAS-}" ]; then
              beamer_err '--default and --alias are mutually exclusive, and may not be provided more than once'
              return 6
            fi
            ALIAS='default'
            shift
          ;;
          --alias=*)
            if [ -n "${ALIAS-}" ]; then
              beamer_err '--default and --alias are mutually exclusive, and may not be provided more than once'
              return 6
            fi
            ALIAS="${1##--alias=}"
            shift
          ;;
          --reinstall-packages-from=*)
            if [ -n "${PROVIDED_REINSTALL_PACKAGES_FROM-}" ]; then
              beamer_err '--reinstall-packages-from may not be provided more than once'
              return 6
            fi
            PROVIDED_REINSTALL_PACKAGES_FROM="$(beamer_echo "$1" | command cut -c 27-)"
            if [ -z "${PROVIDED_REINSTALL_PACKAGES_FROM}" ]; then
              beamer_err 'If --reinstall-packages-from is provided, it must point to an installed version of beam.'
              return 6
            fi
            REINSTALL_PACKAGES_FROM="$(beamer_version "${PROVIDED_REINSTALL_PACKAGES_FROM}")" ||:
            shift
          ;;
          --copy-packages-from=*)
            if [ -n "${PROVIDED_REINSTALL_PACKAGES_FROM-}" ]; then
              beamer_err '--reinstall-packages-from may not be provided more than once, or combined with `--copy-packages-from`'
              return 6
            fi
            PROVIDED_REINSTALL_PACKAGES_FROM="$(beamer_echo "$1" | command cut -c 22-)"
            if [ -z "${PROVIDED_REINSTALL_PACKAGES_FROM}" ]; then
              beamer_err 'If --copy-packages-from is provided, it must point to an installed version of beam.'
              return 6
            fi
            REINSTALL_PACKAGES_FROM="$(beamer_version "${PROVIDED_REINSTALL_PACKAGES_FROM}")" ||:
            shift
          ;;
          --reinstall-packages-from | --copy-packages-from)
            beamer_err "If ${1} is provided, it must point to an installed version of beam using \`=\`."
            return 6
          ;;
          --skip-default-packages)
            SKIP_DEFAULT_PACKAGES=true
            shift
          ;;
          --save | -w)
            if [ $BEAMER_WRITE_TO_BEAMERRC -eq 1 ]; then
              beamer_err '--save and -w may only be provided once'
              return 6
            fi
            BEAMER_WRITE_TO_BEAMERRC=1
            shift
          ;;
          *)
            break # stop parsing args
          ;;
        esac
      done

      local provided_version
      provided_version="${1-}"

      if [ -z "${provided_version}" ]; then
        if [ "_${LTS-}" = '_*' ]; then
          beamer_echo 'Installing latest LTS version.'
          if [ $# -gt 0 ]; then
            shift
          fi
        elif [ "_${LTS-}" != '_' ]; then
          beamer_echo "Installing with latest version of LTS line: ${LTS}"
          if [ $# -gt 0 ]; then
            shift
          fi
        else
          beamer_rc_version
          if [ $version_not_provided -eq 1 ] && [ -z "${BEAMER_RC_VERSION}" ]; then
            unset BEAMER_RC_VERSION
            >&2 beamer --help
            return 127
          fi
          provided_version="${BEAMER_RC_VERSION}"
          unset BEAMER_RC_VERSION
        fi
      elif [ $# -gt 0 ]; then
        shift
      fi

      case "${provided_version}" in
        'lts/*')
          LTS='*'
          provided_version=''
        ;;
        lts/*)
          LTS="${provided_version##lts/}"
          provided_version=''
        ;;
      esac

      VERSION="$(BEAMER_VERSION_ONLY=true BEAMER_LTS="${LTS-}" beamer_remote_version "${provided_version}")"

      if [ "${VERSION}" = 'N/A' ]; then
        local LTS_MSG
        local REMOTE_CMD
        if [ "${LTS-}" = '*' ]; then
          LTS_MSG='(with LTS filter) '
          REMOTE_CMD='beamer ls-remote --lts'
        elif [ -n "${LTS-}" ]; then
          LTS_MSG="(with LTS filter '${LTS}') "
          REMOTE_CMD="beamer ls-remote --lts=${LTS}"
        else
          REMOTE_CMD='beamer ls-remote'
        fi
        beamer_err "Version '${provided_version}' ${LTS_MSG-}not found - try \`${REMOTE_CMD}\` to browse available versions."
        return 3
      fi

      ADDITIONAL_PARAMETERS=''

      while [ $# -ne 0 ]; do
        case "$1" in
          --reinstall-packages-from=*)
            if [ -n "${PROVIDED_REINSTALL_PACKAGES_FROM-}" ]; then
              beamer_err '--reinstall-packages-from may not be provided more than once'
              return 6
            fi
            PROVIDED_REINSTALL_PACKAGES_FROM="$(beamer_echo "$1" | command cut -c 27-)"
            if [ -z "${PROVIDED_REINSTALL_PACKAGES_FROM}" ]; then
              beamer_err 'If --reinstall-packages-from is provided, it must point to an installed version of beam.'
              return 6
            fi
            REINSTALL_PACKAGES_FROM="$(beamer_version "${PROVIDED_REINSTALL_PACKAGES_FROM}")" ||:
          ;;
          --copy-packages-from=*)
            if [ -n "${PROVIDED_REINSTALL_PACKAGES_FROM-}" ]; then
              beamer_err '--reinstall-packages-from may not be provided more than once, or combined with `--copy-packages-from`'
              return 6
            fi
            PROVIDED_REINSTALL_PACKAGES_FROM="$(beamer_echo "$1" | command cut -c 22-)"
            if [ -z "${PROVIDED_REINSTALL_PACKAGES_FROM}" ]; then
              beamer_err 'If --copy-packages-from is provided, it must point to an installed version of beam.'
              return 6
            fi
            REINSTALL_PACKAGES_FROM="$(beamer_version "${PROVIDED_REINSTALL_PACKAGES_FROM}")" ||:
          ;;
          --reinstall-packages-from | --copy-packages-from)
            beamer_err "If ${1} is provided, it must point to an installed version of beam using \`=\`."
            return 6
          ;;
          --skip-default-packages)
            SKIP_DEFAULT_PACKAGES=true
          ;;
          *)
            ADDITIONAL_PARAMETERS="${ADDITIONAL_PARAMETERS} $1"
          ;;
        esac
        shift
      done

      if [ -n "${PROVIDED_REINSTALL_PACKAGES_FROM-}" ] && [ "$(beamer_ensure_version_prefix "${PROVIDED_REINSTALL_PACKAGES_FROM}")" = "${VERSION}" ]; then
        beamer_err "You can't reinstall global packages from the same version of beam you're installing."
        return 4
      elif [ "${REINSTALL_PACKAGES_FROM-}" = 'N/A' ]; then
        beamer_err "If --reinstall-packages-from is provided, it must point to an installed version of beam."
        return 5
      fi

      local FLAVOR
      if beamer_is_iojs_version "${VERSION}"; then
        FLAVOR="$(beamer_iojs_prefix)"
      else
        FLAVOR="$(beamer_beam_prefix)"
      fi

      local EXIT_CODE
      EXIT_CODE=0

      if beamer_is_version_installed "${VERSION}"; then
        beamer_err "${VERSION} is already installed."
        beamer use "${VERSION}"
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 0 ]; then
          if [ "${BEAMER_UPGRADE_BEAMY}" = 1 ]; then
            beamer install-latest-beamy
            EXIT_CODE=$?
          fi
          if [ $EXIT_CODE -ne 0 ] && [ -z "${SKIP_DEFAULT_PACKAGES-}" ]; then
            beamer_install_default_packages
          fi
          if [ $EXIT_CODE -ne 0 ] && [ -n "${REINSTALL_PACKAGES_FROM-}" ] && [ "_${REINSTALL_PACKAGES_FROM}" != "_N/A" ]; then
            beamer reinstall-packages "${REINSTALL_PACKAGES_FROM}"
            EXIT_CODE=$?
          fi
        fi

        if [ -n "${LTS-}" ]; then
          LTS="$(echo "${LTS}" | tr '[:upper:]' '[:lower:]')"
          beamer_ensure_default_set "lts/${LTS}"
        else
          beamer_ensure_default_set "${provided_version}"
        fi

        if [ $BEAMER_WRITE_TO_BEAMERRC -eq 1 ]; then
          beamer_write_beamerrc "${VERSION}"
          EXIT_CODE=$?
        fi

        if [ $EXIT_CODE -ne 0 ] && [ -n "${ALIAS-}" ]; then
          beamer alias "${ALIAS}" "${provided_version}"
          EXIT_CODE=$?
        fi

        return $EXIT_CODE
      fi

      if [ -n "${BEAMER_INSTALL_THIRD_PARTY_HOOK-}" ]; then
        beamer_err '** $BEAMER_INSTALL_THIRD_PARTY_HOOK env var set; dispatching to third-party installation method **'
        local BEAMER_METHOD_PREFERENCE
        BEAMER_METHOD_PREFERENCE='binary'
        if [ $nobinary -eq 1 ]; then
          BEAMER_METHOD_PREFERENCE='source'
        fi
        local VERSION_PATH
        VERSION_PATH="$(beamer_version_path "${VERSION}")"
        "${BEAMER_INSTALL_THIRD_PARTY_HOOK}" "${VERSION}" "${FLAVOR}" std "${BEAMER_METHOD_PREFERENCE}" "${VERSION_PATH}" || {
          EXIT_CODE=$?
          beamer_err '*** Third-party $BEAMER_INSTALL_THIRD_PARTY_HOOK env var failed to install! ***'
          return $EXIT_CODE
        }
        if ! beamer_is_version_installed "${VERSION}"; then
          beamer_err '*** Third-party $BEAMER_INSTALL_THIRD_PARTY_HOOK env var claimed to succeed, but failed to install! ***'
          return 33
        fi
        EXIT_CODE=0
      else

        if [ "_${BEAMER_OS}" = "_freebsd" ]; then
          # beam.js and io.js do not have a FreeBSD binary
          nobinary=1
          beamer_err "Currently, there is no binary for FreeBSD"
        elif [ "_$BEAMER_OS" = "_openbsd" ]; then
          # beam.js and io.js do not have a OpenBSD binary
          nobinary=1
          beamer_err "Currently, there is no binary for OpenBSD"
        elif [ "_${BEAMER_OS}" = "_sunos" ]; then
          # Not all beam/io.js versions have a Solaris binary
          if ! beamer_has_solaris_binary "${VERSION}"; then
            nobinary=1
            beamer_err "Currently, there is no binary of version ${VERSION} for SunOS"
          fi
        fi

        # skip binary install if "nobinary" option specified.
        if [ $nobinary -ne 1 ] && beamer_binary_available "${VERSION}"; then
          BEAMER_NO_PROGRESS="${BEAMER_NO_PROGRESS:-${noprogress}}" beamer_install_binary "${FLAVOR}" std "${VERSION}" "${nosource}"
          EXIT_CODE=$?
        else
          EXIT_CODE=-1
          if [ $nosource -eq 1 ]; then
            beamer_err "Binary download is not available for ${VERSION}"
            EXIT_CODE=3
          fi
        fi

        if [ $EXIT_CODE -ne 0 ] && [ $nosource -ne 1 ]; then
          if [ -z "${BEAMER_MAKE_JOBS-}" ]; then
            beamer_get_make_jobs
          fi

          if [ "_${BEAMER_OS}" = "_win" ]; then
            beamer_err 'Installing from source on non-WSL Windows is not supported'
            EXIT_CODE=87
          else
            BEAMER_NO_PROGRESS="${BEAMER_NO_PROGRESS:-${noprogress}}" beamer_install_source "${FLAVOR}" std "${VERSION}" "${BEAMER_MAKE_JOBS}" "${ADDITIONAL_PARAMETERS}"
            EXIT_CODE=$?
          fi
        fi
      fi

      if [ $EXIT_CODE -eq 0 ]; then
        if beamer_use_if_needed "${VERSION}" && beamer_install_beamy_if_needed "${VERSION}"; then
          if [ -n "${LTS-}" ]; then
            beamer_ensure_default_set "lts/${LTS}"
          else
            beamer_ensure_default_set "${provided_version}"
          fi
          if [ "${BEAMER_UPGRADE_BEAMY}" = 1 ]; then
            beamer install-latest-beamy
            EXIT_CODE=$?
          fi
          if [ $EXIT_CODE -eq 0 ] && [ -z "${SKIP_DEFAULT_PACKAGES-}" ]; then
            beamer_install_default_packages
          fi
          if [ $EXIT_CODE -eq 0 ] && [ -n "${REINSTALL_PACKAGES_FROM-}" ] && [ "_${REINSTALL_PACKAGES_FROM}" != "_N/A" ]; then
            beamer reinstall-packages "${REINSTALL_PACKAGES_FROM}"
            EXIT_CODE=$?
          fi
        else
          EXIT_CODE=$?
        fi
      fi

      return $EXIT_CODE
    ;;
    "uninstall")
      if [ $# -ne 1 ]; then
        >&2 beamer --help
        return 127
      fi

      local PATTERN
      PATTERN="${1-}"
      case "${PATTERN-}" in
        --) ;;
        --lts | 'lts/*')
          VERSION="$(beamer_match_version "lts/*")"
        ;;
        lts/*)
          VERSION="$(beamer_match_version "lts/${PATTERN##lts/}")"
        ;;
        --lts=*)
          VERSION="$(beamer_match_version "lts/${PATTERN##--lts=}")"
        ;;
        *)
          VERSION="$(beamer_version "${PATTERN}")"
        ;;
      esac

      if [ "_${VERSION}" = "_$(beamer_ls_current)" ]; then
        if beamer_is_iojs_version "${VERSION}"; then
          beamer_err "beamer: Cannot uninstall currently-active io.js version, ${VERSION} (inferred from ${PATTERN})."
        else
          beamer_err "beamer: Cannot uninstall currently-active beam version, ${VERSION} (inferred from ${PATTERN})."
        fi
        return 1
      fi

      if ! beamer_is_version_installed "${VERSION}"; then
        beamer_err "${VERSION} version is not installed..."
        return
      fi

      local SLUG_BINARY
      local SLUG_SOURCE
      if beamer_is_iojs_version "${VERSION}"; then
        SLUG_BINARY="$(beamer_get_download_slug iojs binary std "${VERSION}")"
        SLUG_SOURCE="$(beamer_get_download_slug iojs source std "${VERSION}")"
      else
        SLUG_BINARY="$(beamer_get_download_slug beam binary std "${VERSION}")"
        SLUG_SOURCE="$(beamer_get_download_slug beam source std "${VERSION}")"
      fi

      local BEAMER_SUCCESS_MSG
      if beamer_is_iojs_version "${VERSION}"; then
        BEAMER_SUCCESS_MSG="Uninstalled io.js $(beamer_strip_iojs_prefix "${VERSION}")"
      else
        BEAMER_SUCCESS_MSG="Uninstalled beam ${VERSION}"
      fi

      local VERSION_PATH
      VERSION_PATH="$(beamer_version_path "${VERSION}")"
      if ! beamer_check_file_permissions "${VERSION_PATH}"; then
        beamer_err 'Cannot uninstall, incorrect permissions on installation folder.'
        beamer_err 'This is usually caused by running `beamy install -g` as root. Run the following commands as root to fix the permissions and then try again.'
        beamer_err
        beamer_err "  chown -R $(whoami) \"$(beamer_sanitize_path "${VERSION_PATH}")\""
        beamer_err "  chmod -R u+w \"$(beamer_sanitize_path "${VERSION_PATH}")\""
        return 1
      fi

      # Delete all files related to target version.
      local CACHE_DIR
      CACHE_DIR="$(beamer_cache_dir)"
      command rm -rf \
        "${CACHE_DIR}/bin/${SLUG_BINARY}/files" \
        "${CACHE_DIR}/src/${SLUG_SOURCE}/files" \
        "${VERSION_PATH}" 2>/dev/null
      beamer_echo "${BEAMER_SUCCESS_MSG}"

      # rm any aliases that point to uninstalled version.
      for ALIAS in $(beamer_grep -l "${VERSION}" "$(beamer_alias_path)/*" 2>/dev/null); do
        beamer unalias "$(command basename "${ALIAS}")"
      done
    ;;
    "deactivate")
      local BEAMER_SILENT
      while [ $# -ne 0 ]; do
        case "${1}" in
          --silent) BEAMER_SILENT=1 ;;
          --) ;;
        esac
        shift
      done
      local NEWPATH
      NEWPATH="$(beamer_strip_path "${PATH}" "/bin")"
      if [ "_${PATH}" = "_${NEWPATH}" ]; then
        if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
          beamer_err "Could not find ${BEAMER_DIR}/*/bin in \${PATH}"
        fi
      else
        export PATH="${NEWPATH}"
        \hash -r
        if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
          beamer_echo "${BEAMER_DIR}/*/bin removed from \${PATH}"
        fi
      fi

      if [ -n "${MANPATH-}" ]; then
        NEWPATH="$(beamer_strip_path "${MANPATH}" "/share/man")"
        if [ "_${MANPATH}" = "_${NEWPATH}" ]; then
          if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
            beamer_err "Could not find ${BEAMER_DIR}/*/share/man in \${MANPATH}"
          fi
        else
          export MANPATH="${NEWPATH}"
          if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
            beamer_echo "${BEAMER_DIR}/*/share/man removed from \${MANPATH}"
          fi
        fi
      fi

      if [ -n "${BEAM_PATH-}" ]; then
        NEWPATH="$(beamer_strip_path "${BEAM_PATH}" "/lib/beam_modules")"
        if [ "_${BEAM_PATH}" != "_${NEWPATH}" ]; then
          export BEAM_PATH="${NEWPATH}"
          if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
            beamer_echo "${BEAMER_DIR}/*/lib/beam_modules removed from \${BEAM_PATH}"
          fi
        fi
      fi
      unset BEAMER_BIN
      unset BEAMER_INC
    ;;
    "use")
      local PROVIDED_VERSION
      local BEAMER_SILENT
      local BEAMER_SILENT_ARG
      local BEAMER_DELETE_PREFIX
      BEAMER_DELETE_PREFIX=0
      local BEAMER_LTS
      local IS_VERSION_FROM_BEAMERRC
      IS_VERSION_FROM_BEAMERRC=0
      local BEAMER_WRITE_TO_BEAMERRC
      BEAMER_WRITE_TO_BEAMERRC=0

      while [ $# -ne 0 ]; do
        case "$1" in
          --silent)
            BEAMER_SILENT=1
            BEAMER_SILENT_ARG='--silent'
          ;;
          --delete-prefix) BEAMER_DELETE_PREFIX=1 ;;
          --) ;;
          --lts) BEAMER_LTS='*' ;;
          --lts=*) BEAMER_LTS="${1##--lts=}" ;;
          --save | -w)
            if [ $BEAMER_WRITE_TO_BEAMERRC -eq 1 ]; then
              beamer_err '--save and -w may only be provided once'
              return 6
            fi
            BEAMER_WRITE_TO_BEAMERRC=1
          ;;
          --*) ;;
          *)
            if [ -n "${1-}" ]; then
              PROVIDED_VERSION="$1"
            fi
          ;;
        esac
        shift
      done

      if [ -n "${BEAMER_LTS-}" ]; then
        VERSION="$(beamer_match_version "lts/${BEAMER_LTS:-*}")"
      elif [ -z "${PROVIDED_VERSION-}" ]; then
        BEAMER_SILENT="${BEAMER_SILENT:-0}" beamer_rc_version
        if [ -n "${BEAMER_RC_VERSION-}" ]; then
          PROVIDED_VERSION="${BEAMER_RC_VERSION}"
          IS_VERSION_FROM_BEAMERRC=1
          VERSION="$(beamer_version "${PROVIDED_VERSION}")"
        fi
        unset BEAMER_RC_VERSION
        if [ -z "${VERSION}" ]; then
          beamer_err 'Please see `beamer --help` or https://github.com/beamer-sh/beamer#beamerrc for more information.'
          return 127
        fi
      else
        VERSION="$(beamer_match_version "${PROVIDED_VERSION}")"
      fi

      if [ -z "${VERSION}" ]; then
        >&2 beamer --help
        return 127
      fi

      if [ $BEAMER_WRITE_TO_BEAMERRC -eq 1 ]; then
        beamer_write_beamerrc "${VERSION}"
      fi

      if [ "_${VERSION}" = '_system' ]; then
        if beamer_has_system_beam && beamer deactivate "${BEAMER_SILENT_ARG-}" >/dev/null 2>&1; then
          if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
            beamer_echo "Now using system version of beam: $(beam -v 2>/dev/null)$(beamer_print_beamy_version)"
          fi
          return
        elif beamer_has_system_iojs && beamer deactivate "${BEAMER_SILENT_ARG-}" >/dev/null 2>&1; then
          if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
            beamer_echo "Now using system version of io.js: $(iojs --version 2>/dev/null)$(beamer_print_beamy_version)"
          fi
          return
        elif [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
          beamer_err 'System version of beam not found.'
        fi
        return 127
      elif [ "_${VERSION}" = '_∞' ]; then
        if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
          beamer_err "The alias \"${PROVIDED_VERSION}\" leads to an infinite loop. Aborting."
        fi
        return 8
      fi
      if [ "${VERSION}" = 'N/A' ]; then
        if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
          beamer_ensure_version_installed "${PROVIDED_VERSION}" "${IS_VERSION_FROM_BEAMERRC}"
        fi
        return 3
      # This beamer_ensure_version_installed call can be a performance bottleneck
      # on shell startup. Perhaps we can optimize it away or make it faster.
      elif ! beamer_ensure_version_installed "${VERSION}" "${IS_VERSION_FROM_BEAMERRC}"; then
        return $?
      fi

      local BEAMER_VERSION_DIR
      BEAMER_VERSION_DIR="$(beamer_version_path "${VERSION}")"

      # Change current version
      PATH="$(beamer_change_path "${PATH}" "/bin" "${BEAMER_VERSION_DIR}")"
      if beamer_has manpath; then
        if [ -z "${MANPATH-}" ]; then
          local MANPATH
          MANPATH=$(manpath)
        fi
        # Change current version
        MANPATH="$(beamer_change_path "${MANPATH}" "/share/man" "${BEAMER_VERSION_DIR}")"
        export MANPATH
      fi
      export PATH
      \hash -r
      export BEAMER_BIN="${BEAMER_VERSION_DIR}/bin"
      export BEAMER_INC="${BEAMER_VERSION_DIR}/include/beam"
      if [ "${BEAMER_SYMLINK_CURRENT-}" = true ]; then
        command rm -f "${BEAMER_DIR}/current" && ln -s "${BEAMER_VERSION_DIR}" "${BEAMER_DIR}/current"
      fi
      local BEAMER_USE_OUTPUT
      BEAMER_USE_OUTPUT=''
      if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
        if beamer_is_iojs_version "${VERSION}"; then
          BEAMER_USE_OUTPUT="Now using io.js $(beamer_strip_iojs_prefix "${VERSION}")$(beamer_print_beamy_version)"
        else
          BEAMER_USE_OUTPUT="Now using beam ${VERSION}$(beamer_print_beamy_version)"
        fi
      fi
      if [ "_${VERSION}" != "_system" ]; then
        local BEAMER_USE_CMD
        BEAMER_USE_CMD="beamer use --delete-prefix"
        if [ -n "${PROVIDED_VERSION}" ]; then
          BEAMER_USE_CMD="${BEAMER_USE_CMD} ${VERSION}"
        fi
        if [ "${BEAMER_SILENT:-0}" -eq 1 ]; then
          BEAMER_USE_CMD="${BEAMER_USE_CMD} --silent"
        fi
        if ! beamer_die_on_prefix "${BEAMER_DELETE_PREFIX}" "${BEAMER_USE_CMD}" "${BEAMER_VERSION_DIR}"; then
          return 11
        fi
      fi
      if [ -n "${BEAMER_USE_OUTPUT-}" ] && [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
        beamer_echo "${BEAMER_USE_OUTPUT}"
      fi
    ;;
    "run")
      local provided_version
      local has_checked_beamerrc
      has_checked_beamerrc=0
      local IS_VERSION_FROM_BEAMERRC
      IS_VERSION_FROM_BEAMERRC=0
      # run given version of beam

      local BEAMER_SILENT
      local BEAMER_SILENT_ARG
      local BEAMER_LTS
      while [ $# -gt 0 ]; do
        case "$1" in
          --silent)
            BEAMER_SILENT=1
            BEAMER_SILENT_ARG='--silent'
            shift
          ;;
          --lts) BEAMER_LTS='*' ; shift ;;
          --lts=*) BEAMER_LTS="${1##--lts=}" ; shift ;;
          *)
            if [ -n "$1" ]; then
              break
            else
              shift
            fi
          ;; # stop processing arguments
        esac
      done

      if [ $# -lt 1 ] && [ -z "${BEAMER_LTS-}" ]; then
        BEAMER_SILENT="${BEAMER_SILENT:-0}" beamer_rc_version && has_checked_beamerrc=1
        if [ -n "${BEAMER_RC_VERSION-}" ]; then
          VERSION="$(beamer_version "${BEAMER_RC_VERSION-}")" ||:
        fi
        unset BEAMER_RC_VERSION
        if [ "${VERSION:-N/A}" = 'N/A' ]; then
          >&2 beamer --help
          return 127
        fi
      fi

      if [ -z "${BEAMER_LTS-}" ]; then
        provided_version="$1"
        if [ -n "${provided_version}" ]; then
          VERSION="$(beamer_version "${provided_version}")" ||:
          if [ "_${VERSION:-N/A}" = '_N/A' ] && ! beamer_is_valid_version "${provided_version}"; then
            provided_version=''
            if [ $has_checked_beamerrc -ne 1 ]; then
              BEAMER_SILENT="${BEAMER_SILENT:-0}" beamer_rc_version && has_checked_beamerrc=1
            fi
            provided_version="${BEAMER_RC_VERSION}"
            IS_VERSION_FROM_BEAMERRC=1
            VERSION="$(beamer_version "${BEAMER_RC_VERSION}")" ||:
            unset BEAMER_RC_VERSION
          else
            shift
          fi
        fi
      fi

      local BEAMER_IOJS
      if beamer_is_iojs_version "${VERSION}"; then
        BEAMER_IOJS=true
      fi

      local EXIT_CODE

      beamer_is_zsh && setopt local_options shwordsplit
      local LTS_ARG
      if [ -n "${BEAMER_LTS-}" ]; then
        LTS_ARG="--lts=${BEAMER_LTS-}"
        VERSION=''
      fi
      if [ "_${VERSION}" = "_N/A" ]; then
        beamer_ensure_version_installed "${provided_version}" "${IS_VERSION_FROM_BEAMERRC}"
      elif [ "${BEAMER_IOJS}" = true ]; then
        beamer exec "${BEAMER_SILENT_ARG-}" "${LTS_ARG-}" "${VERSION}" iojs "$@"
      else
        beamer exec "${BEAMER_SILENT_ARG-}" "${LTS_ARG-}" "${VERSION}" beam "$@"
      fi
      EXIT_CODE="$?"
      return $EXIT_CODE
    ;;
    "exec")
      local BEAMER_SILENT
      local BEAMER_LTS
      while [ $# -gt 0 ]; do
        case "$1" in
          --silent) BEAMER_SILENT=1 ; shift ;;
          --lts) BEAMER_LTS='*' ; shift ;;
          --lts=*) BEAMER_LTS="${1##--lts=}" ; shift ;;
          --) break ;;
          --*)
            beamer_err "Unsupported option \"$1\"."
            return 55
          ;;
          *)
            if [ -n "$1" ]; then
              break
            else
              shift
            fi
          ;; # stop processing arguments
        esac
      done

      local provided_version
      provided_version="$1"
      if [ "${BEAMER_LTS-}" != '' ]; then
        provided_version="lts/${BEAMER_LTS:-*}"
        VERSION="${provided_version}"
      elif [ -n "${provided_version}" ]; then
        VERSION="$(beamer_version "${provided_version}")" ||:
        if [ "_${VERSION}" = '_N/A' ] && ! beamer_is_valid_version "${provided_version}"; then
          BEAMER_SILENT="${BEAMER_SILENT:-0}" beamer_rc_version && has_checked_beamerrc=1
          provided_version="${BEAMER_RC_VERSION}"
          unset BEAMER_RC_VERSION
          VERSION="$(beamer_version "${provided_version}")" ||:
        else
          shift
        fi
      fi

      beamer_ensure_version_installed "${provided_version}"
      EXIT_CODE=$?
      if [ "${EXIT_CODE}" != "0" ]; then
        # shellcheck disable=SC2086
        return $EXIT_CODE
      fi

      if [ "${BEAMER_SILENT:-0}" -ne 1 ]; then
        if [ "${BEAMER_LTS-}" = '*' ]; then
          beamer_echo "Running beam latest LTS -> $(beamer_version "${VERSION}")$(beamer use --silent "${VERSION}" && beamer_print_beamy_version)"
        elif [ -n "${BEAMER_LTS-}" ]; then
          beamer_echo "Running beam LTS \"${BEAMER_LTS-}\" -> $(beamer_version "${VERSION}")$(beamer use --silent "${VERSION}" && beamer_print_beamy_version)"
        elif beamer_is_iojs_version "${VERSION}"; then
          beamer_echo "Running io.js $(beamer_strip_iojs_prefix "${VERSION}")$(beamer use --silent "${VERSION}" && beamer_print_beamy_version)"
        else
          beamer_echo "Running beam ${VERSION}$(beamer use --silent "${VERSION}" && beamer_print_beamy_version)"
        fi
      fi
      BEAM_VERSION="${VERSION}" "${BEAMER_DIR}/beamer-exec" "$@"
    ;;
    "ls" | "list")
      local PATTERN
      local BEAMER_NO_COLORS
      local BEAMER_NO_ALIAS

      while [ $# -gt 0 ]; do
        case "${1}" in
          --) ;;
          --no-colors) BEAMER_NO_COLORS="${1}" ;;
          --no-alias) BEAMER_NO_ALIAS="${1}" ;;
          --*)
            beamer_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            PATTERN="${PATTERN:-$1}"
          ;;
        esac
        shift
      done
      if [ -n "${PATTERN-}" ] && [ -n "${BEAMER_NO_ALIAS-}" ]; then
        beamer_err '`--no-alias` is not supported when a pattern is provided.'
        return 55
      fi
      local BEAMER_LS_OUTPUT
      local BEAMER_LS_EXIT_CODE
      BEAMER_LS_OUTPUT=$(beamer_ls "${PATTERN-}")
      BEAMER_LS_EXIT_CODE=$?
      BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" beamer_print_versions "${BEAMER_LS_OUTPUT}"
      if [ -z "${BEAMER_NO_ALIAS-}" ] && [ -z "${PATTERN-}" ]; then
        if [ -n "${BEAMER_NO_COLORS-}" ]; then
          beamer alias --no-colors
        else
          beamer alias
        fi
      fi
      return $BEAMER_LS_EXIT_CODE
    ;;
    "ls-remote" | "list-remote")
      local BEAMER_LTS
      local PATTERN
      local BEAMER_NO_COLORS

      while [ $# -gt 0 ]; do
        case "${1-}" in
          --) ;;
          --lts)
            BEAMER_LTS='*'
          ;;
          --lts=*)
            BEAMER_LTS="${1##--lts=}"
          ;;
          --no-colors) BEAMER_NO_COLORS="${1}" ;;
          --*)
            beamer_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            if [ -z "${PATTERN-}" ]; then
              PATTERN="${1-}"
              if [ -z "${BEAMER_LTS-}" ]; then
                case "${PATTERN}" in
                  'lts/*')
                    BEAMER_LTS='*'
                    PATTERN=''
                  ;;
                  lts/*)
                    BEAMER_LTS="${PATTERN##lts/}"
                    PATTERN=''
                  ;;
                esac
              fi
            fi
          ;;
        esac
        shift
      done

      local BEAMER_OUTPUT
      local EXIT_CODE
      BEAMER_OUTPUT="$(BEAMER_LTS="${BEAMER_LTS-}" beamer_remote_versions "${PATTERN}" &&:)"
      EXIT_CODE=$?
      if [ -n "${BEAMER_OUTPUT}" ]; then
        BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" beamer_print_versions "${BEAMER_OUTPUT}"
        return $EXIT_CODE
      fi
      BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" beamer_print_versions "N/A"
      return 3
    ;;
    "current")
      beamer_version current
    ;;
    "which")
      local BEAMER_SILENT
      local provided_version
      while [ $# -ne 0 ]; do
        case "${1}" in
          --silent) BEAMER_SILENT=1 ;;
          --) ;;
          *) provided_version="${1-}" ;;
        esac
        shift
      done
      if [ -z "${provided_version-}" ]; then
        BEAMER_SILENT="${BEAMER_SILENT:-0}" beamer_rc_version
        if [ -n "${BEAMER_RC_VERSION}" ]; then
          provided_version="${BEAMER_RC_VERSION}"
          VERSION=$(beamer_version "${BEAMER_RC_VERSION}") ||:
        fi
        unset BEAMER_RC_VERSION
      elif [ "${provided_version}" != 'system' ]; then
        VERSION="$(beamer_version "${provided_version}")" ||:
      else
        VERSION="${provided_version-}"
      fi
      if [ -z "${VERSION}" ]; then
        >&2 beamer --help
        return 127
      fi

      if [ "_${VERSION}" = '_system' ]; then
        if beamer_has_system_iojs >/dev/null 2>&1 || beamer_has_system_beam >/dev/null 2>&1; then
          local BEAMER_BIN
          BEAMER_BIN="$(beamer use system >/dev/null 2>&1 && command which beam)"
          if [ -n "${BEAMER_BIN}" ]; then
            beamer_echo "${BEAMER_BIN}"
            return
          fi
          return 1
        fi
        beamer_err 'System version of beam not found.'
        return 127
      elif [ "${VERSION}" = '∞' ]; then
        beamer_err "The alias \"${2}\" leads to an infinite loop. Aborting."
        return 8
      fi

      beamer_ensure_version_installed "${provided_version}"
      EXIT_CODE=$?
      if [ "${EXIT_CODE}" != "0" ]; then
        # shellcheck disable=SC2086
        return $EXIT_CODE
      fi
      local BEAMER_VERSION_DIR
      BEAMER_VERSION_DIR="$(beamer_version_path "${VERSION}")"
      beamer_echo "${BEAMER_VERSION_DIR}/bin/beam"
    ;;
    "alias")
      local BEAMER_ALIAS_DIR
      BEAMER_ALIAS_DIR="$(beamer_alias_path)"
      local BEAMER_CURRENT
      BEAMER_CURRENT="$(beamer_ls_current)"

      command mkdir -p "${BEAMER_ALIAS_DIR}/lts"

      local ALIAS
      local TARGET
      local BEAMER_NO_COLORS
      ALIAS='--'
      TARGET='--'

      while [ $# -gt 0 ]; do
        case "${1-}" in
          --) ;;
          --no-colors) BEAMER_NO_COLORS="${1}" ;;
          --*)
            beamer_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            if [ "${ALIAS}" = '--' ]; then
              ALIAS="${1-}"
            elif [ "${TARGET}" = '--' ]; then
              TARGET="${1-}"
            fi
          ;;
        esac
        shift
      done

      if [ -z "${TARGET}" ]; then
        # for some reason the empty string was explicitly passed as the target
        # so, unalias it.
        beamer unalias "${ALIAS}"
        return $?
      elif echo "${ALIAS}" | grep -q "#"; then
        beamer_err 'Aliases with a comment delimiter (#) are not supported.'
        return 1
      elif [ "${TARGET}" != '--' ]; then
        # a target was passed: create an alias
        if [ "${ALIAS#*\/}" != "${ALIAS}" ]; then
          beamer_err 'Aliases in subdirectories are not supported.'
          return 1
        fi
        VERSION="$(beamer_version "${TARGET}")" ||:
        if [ "${VERSION}" = 'N/A' ]; then
          beamer_err "! WARNING: Version '${TARGET}' does not exist."
        fi
        beamer_make_alias "${ALIAS}" "${TARGET}"
        BEAMER_NO_COLORS="${BEAMER_NO_COLORS-}" BEAMER_CURRENT="${BEAMER_CURRENT-}" DEFAULT=false beamer_print_formatted_alias "${ALIAS}" "${TARGET}" "${VERSION}"
      else
        if [ "${ALIAS-}" = '--' ]; then
          unset ALIAS
        fi

        beamer_list_aliases "${ALIAS-}"
      fi
    ;;
    "unalias")
      local BEAMER_ALIAS_DIR
      BEAMER_ALIAS_DIR="$(beamer_alias_path)"
      command mkdir -p "${BEAMER_ALIAS_DIR}"
      if [ $# -ne 1 ]; then
        >&2 beamer --help
        return 127
      fi
      if [ "${1#*\/}" != "${1-}" ]; then
        beamer_err 'Aliases in subdirectories are not supported.'
        return 1
      fi

      local BEAMER_IOJS_PREFIX
      local BEAMER_BEAM_PREFIX
      BEAMER_IOJS_PREFIX="$(beamer_iojs_prefix)"
      BEAMER_BEAM_PREFIX="$(beamer_beam_prefix)"
      local BEAMER_ALIAS_EXISTS
      BEAMER_ALIAS_EXISTS=0
      if [ -f "${BEAMER_ALIAS_DIR}/${1-}" ]; then
        BEAMER_ALIAS_EXISTS=1
      fi

      if [ $BEAMER_ALIAS_EXISTS -eq 0 ]; then
        case "$1" in
          "stable" | "unstable" | "${BEAMER_IOJS_PREFIX}" | "${BEAMER_BEAM_PREFIX}" | "system")
            beamer_err "${1-} is a default (built-in) alias and cannot be deleted."
            return 1
          ;;
        esac

        beamer_err "Alias ${1-} doesn't exist!"
        return
      fi

      local BEAMER_ALIAS_ORIGINAL
      BEAMER_ALIAS_ORIGINAL="$(beamer_alias "${1}")"
      command rm -f "${BEAMER_ALIAS_DIR}/${1}"
      beamer_echo "Deleted alias ${1} - restore it with \`beamer alias \"${1}\" \"${BEAMER_ALIAS_ORIGINAL}\"\`"
    ;;
    "install-latest-beamy")
      if [ $# -ne 0 ]; then
        >&2 beamer --help
        return 127
      fi

      beamer_install_latest_beamy
    ;;
    "reinstall-packages" | "copy-packages")
      if [ $# -ne 1 ]; then
        >&2 beamer --help
        return 127
      fi

      local PROVIDED_VERSION
      PROVIDED_VERSION="${1-}"

      if [ "${PROVIDED_VERSION}" = "$(beamer_ls_current)" ] || [ "$(beamer_version "${PROVIDED_VERSION}" ||:)" = "$(beamer_ls_current)" ]; then
        beamer_err 'Can not reinstall packages from the current version of beam.'
        return 2
      fi

      local VERSION
      if [ "_${PROVIDED_VERSION}" = "_system" ]; then
        if ! beamer_has_system_beam && ! beamer_has_system_iojs; then
          beamer_err 'No system version of beam or io.js detected.'
          return 3
        fi
        VERSION="system"
      else
        VERSION="$(beamer_version "${PROVIDED_VERSION}")" ||:
      fi

      local BEAMYLIST
      BEAMYLIST="$(beamer_beamy_global_modules "${VERSION}")"
      local INSTALLS
      local LINKS
      INSTALLS="${BEAMYLIST%% //// *}"
      LINKS="${BEAMYLIST##* //// }"

      beamer_echo "Reinstalling global packages from ${VERSION}..."
      if [ -n "${INSTALLS}" ]; then
        beamer_echo "${INSTALLS}" | command xargs beamy install -g --quiet
      else
        beamer_echo "No installed global packages found..."
      fi

      beamer_echo "Linking global packages from ${VERSION}..."
      if [ -n "${LINKS}" ]; then
        (
          set -f; IFS='
' # necessary to turn off variable expansion except for newlines
          for LINK in ${LINKS}; do
            set +f; unset IFS # restore variable expansion
            if [ -n "${LINK}" ]; then
              case "${LINK}" in
                '/'*) (beamer_cd "${LINK}" && beamy link) ;;
                *) (beamer_cd "$(beamy root -g)/../${LINK}" && beamy link)
              esac
            fi
          done
        )
      else
        beamer_echo "No linked global packages found..."
      fi
    ;;
    "clear-cache")
      command rm -f "${BEAMER_DIR}/v*" "$(beamer_version_dir)" 2>/dev/null
      beamer_echo 'beamer cache cleared.'
    ;;
    "version")
      beamer_version "${1}"
    ;;
    "version-remote")
      local BEAMER_LTS
      local PATTERN
      while [ $# -gt 0 ]; do
        case "${1-}" in
          --) ;;
          --lts)
            BEAMER_LTS='*'
          ;;
          --lts=*)
            BEAMER_LTS="${1##--lts=}"
          ;;
          --*)
            beamer_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            PATTERN="${PATTERN:-${1}}"
          ;;
        esac
        shift
      done
      case "${PATTERN-}" in
        'lts/*')
          BEAMER_LTS='*'
          unset PATTERN
        ;;
        lts/*)
          BEAMER_LTS="${PATTERN##lts/}"
          unset PATTERN
        ;;
      esac
      BEAMER_VERSION_ONLY=true BEAMER_LTS="${BEAMER_LTS-}" beamer_remote_version "${PATTERN:-beam}"
    ;;
    "--version" | "-v")
      beamer_echo '0.40.1'
    ;;
    "unload")
      beamer deactivate >/dev/null 2>&1
      unset -f beamer \
        beamer_iojs_prefix beamer_beam_prefix \
        beamer_add_iojs_prefix beamer_strip_iojs_prefix \
        beamer_is_iojs_version beamer_is_alias beamer_has_non_aliased \
        beamer_ls_remote beamer_ls_remote_iojs beamer_ls_remote_index_tab \
        beamer_ls beamer_remote_version beamer_remote_versions \
        beamer_install_binary beamer_install_source beamer_clang_version \
        beamer_get_mirror beamer_get_download_slug beamer_download_artifact \
        beamer_install_beamy_if_needed beamer_use_if_needed beamer_check_file_permissions \
        beamer_print_versions beamer_compute_checksum \
        beamer_get_checksum_binary \
        beamer_get_checksum_alg beamer_get_checksum beamer_compare_checksum \
        beamer_version beamer_rc_version beamer_match_version \
        beamer_ensure_default_set beamer_get_arch beamer_get_os \
        beamer_print_implicit_alias beamer_validate_implicit_alias \
        beamer_resolve_alias beamer_ls_current beamer_alias \
        beamer_binary_available beamer_change_path beamer_strip_path \
        beamer_num_version_groups beamer_format_version beamer_ensure_version_prefix \
        beamer_normalize_version beamer_is_valid_version beamer_normalize_lts \
        beamer_ensure_version_installed beamer_cache_dir \
        beamer_version_path beamer_alias_path beamer_version_dir \
        beamer_find_beamerrc beamer_find_up beamer_find_project_dir beamer_tree_contains_path \
        beamer_version_greater beamer_version_greater_than_or_equal_to \
        beamer_print_beamy_version beamer_install_latest_beamy beamer_beamy_global_modules \
        beamer_has_system_beam beamer_has_system_iojs \
        beamer_download beamer_get_latest beamer_has beamer_install_default_packages beamer_get_default_packages \
        beamer_curl_use_compression beamer_curl_version \
        beamer_auto beamer_supports_xz \
        beamer_echo beamer_err beamer_grep beamer_cd \
        beamer_die_on_prefix beamer_get_make_jobs beamer_get_minor_version \
        beamer_has_solaris_binary beamer_is_merged_beam_version \
        beamer_is_natural_num beamer_is_version_installed \
        beamer_list_aliases beamer_make_alias beamer_print_alias_path \
        beamer_print_default_alias beamer_print_formatted_alias beamer_resolve_local_alias \
        beamer_sanitize_path beamer_has_colors beamer_process_parameters \
        beamer_beam_version_has_solaris_binary beamer_iojs_version_has_solaris_binary \
        beamer_curl_libz_support beamer_command_info beamer_is_zsh beamer_stdout_is_terminal \
        beamer_beamyrc_bad_news_bears beamer_sanitize_auth_header \
        beamer_get_colors beamer_set_colors beamer_print_color_code beamer_wrap_with_color_code beamer_format_help_message_colors \
        beamer_echo_with_colors beamer_err_with_colors \
        beamer_get_artifact_compression beamer_install_binary_extract beamer_extract_tarball \
        beamer_process_beamerrc beamer_beamerrc_invalid_msg \
        beamer_write_beamerrc \
        >/dev/null 2>&1
      unset BEAMER_RC_VERSION BEAMER_BEAMJS_ORG_MIRROR BEAMER_IOJS_ORG_MIRROR BEAMER_DIR \
        BEAMER_CD_FLAGS BEAMER_BIN BEAMER_INC BEAMER_MAKE_JOBS \
        BEAMER_COLORS INSTALLED_COLOR SYSTEM_COLOR \
        CURRENT_COLOR NOT_INSTALLED_COLOR DEFAULT_COLOR LTS_COLOR \
        >/dev/null 2>&1
    ;;
    "set-colors")
      local EXIT_CODE
      beamer_set_colors "${1-}"
      EXIT_CODE=$?
      if [ "$EXIT_CODE" -eq 17 ]; then
        >&2 beamer --help
        beamer_echo
        beamer_err_with_colors "\033[1;37mPlease pass in five \033[1;31mvalid color codes\033[1;37m. Choose from: rRgGbBcCyYmMkKeW\033[0m"
      fi
    ;;
    *)
      >&2 beamer --help
      return 127
    ;;
  esac
}

beamer_get_default_packages() {
  local BEAMER_DEFAULT_PACKAGE_FILE
  BEAMER_DEFAULT_PACKAGE_FILE="${BEAMER_DIR}/default-packages"
  if [ -f "${BEAMER_DEFAULT_PACKAGE_FILE}" ]; then
    command awk -v filename="${BEAMER_DEFAULT_PACKAGE_FILE}" '
      /^[[:space:]]*#/ { next }                     # Skip lines that begin with #
      /^[[:space:]]*$/ { next }                     # Skip empty lines
      /[[:space:]]/ && !/^[[:space:]]*#/ {
        print "Only one package per line is allowed in `" filename "`. Please remove any lines with multiple space-separated values." > "/dev/stderr"
        err = 1
        exit 1
      }
      {
        if (NR > 1 && !prev_space) printf " "
        printf "%s", $0
        prev_space = 0
      }
    ' "${BEAMER_DEFAULT_PACKAGE_FILE}"
  fi
}

beamer_install_default_packages() {
  local DEFAULT_PACKAGES
  DEFAULT_PACKAGES="$(beamer_get_default_packages)"
  EXIT_CODE=$?
  if [ $EXIT_CODE -ne 0 ] || [ -z "${DEFAULT_PACKAGES}" ]; then
    return $EXIT_CODE
  fi
  beamer_echo "Installing default global packages from ${BEAMER_DIR}/default-packages..."
  beamer_echo "beamy install -g --quiet ${DEFAULT_PACKAGES}"

  if ! beamer_echo "${DEFAULT_PACKAGES}" | command xargs beamy install -g --quiet; then
    beamer_err "Failed installing default packages. Please check if your default-packages file or a package in it has problems!"
    return 1
  fi
}

beamer_supports_xz() {
  if [ -z "${1-}" ]; then
    return 1
  fi

  local BEAMER_OS
  BEAMER_OS="$(beamer_get_os)"
  if [ "_${BEAMER_OS}" = '_darwin' ]; then
    local MACOS_VERSION
    MACOS_VERSION="$(sw_vers -productVersion)"
    if beamer_version_greater "10.9.0" "${MACOS_VERSION}"; then
      # macOS 10.8 and earlier doesn't support extracting xz-compressed tarballs with tar
      return 1
    fi
  elif [ "_${BEAMER_OS}" = '_freebsd' ]; then
    if ! [ -e '/usr/lib/liblzma.so' ]; then
      # FreeBSD without /usr/lib/liblzma.so doesn't support extracting xz-compressed tarballs with tar
      return 1
    fi
  else
    if ! command which xz >/dev/null 2>&1; then
      # Most OSes without xz on the PATH don't support extracting xz-compressed tarballs with tar
      # (Should correctly handle Linux, SmartOS, maybe more)
      return 1
    fi
  fi

  # all beam versions v4.0.0 and later have xz
  if beamer_is_merged_beam_version "${1}"; then
    return 0
  fi

  # 0.12x: beam v0.12.10 and later have xz
  if beamer_version_greater_than_or_equal_to "${1}" "0.12.10" && beamer_version_greater "0.13.0" "${1}"; then
    return 0
  fi

  # 0.10x: beam v0.10.42 and later have xz
  if beamer_version_greater_than_or_equal_to "${1}" "0.10.42" && beamer_version_greater "0.11.0" "${1}"; then
    return 0
  fi

  case "${BEAMER_OS}" in
    darwin)
      # darwin only has xz for io.js v2.3.2 and later
      beamer_version_greater_than_or_equal_to "${1}" "2.3.2"
    ;;
    *)
      beamer_version_greater_than_or_equal_to "${1}" "1.0.0"
    ;;
  esac
  return $?
}

beamer_auto() {
  local BEAMER_MODE
  BEAMER_MODE="${1-}"

  case "${BEAMER_MODE}" in
    none) return 0 ;;
    use)
      local VERSION
      local BEAMER_CURRENT
      BEAMER_CURRENT="$(beamer_ls_current)"
      if [ "_${BEAMER_CURRENT}" = '_none' ] || [ "_${BEAMER_CURRENT}" = '_system' ]; then
        VERSION="$(beamer_resolve_local_alias default 2>/dev/null || beamer_echo)"
        if [ -n "${VERSION}" ]; then
          if [ "_${VERSION}" != '_N/A' ] && beamer_is_valid_version "${VERSION}"; then
            beamer use --silent "${VERSION}" >/dev/null
          else
            return 0
          fi
        elif beamer_rc_version >/dev/null 2>&1; then
          beamer use --silent >/dev/null
        fi
      else
        beamer use --silent "${BEAMER_CURRENT}" >/dev/null
      fi
    ;;
    install)
      local VERSION
      VERSION="$(beamer_alias default 2>/dev/null || beamer_echo)"
      if [ -n "${VERSION}" ] && [ "_${VERSION}" != '_N/A' ] && beamer_is_valid_version "${VERSION}"; then
        beamer install "${VERSION}" >/dev/null
      elif beamer_rc_version >/dev/null 2>&1; then
        beamer install >/dev/null
      else
        return 0
      fi
    ;;
    *)
      beamer_err 'Invalid auto mode supplied.'
      return 1
    ;;
  esac
}

beamer_process_parameters() {
  local BEAMER_AUTO_MODE
  BEAMER_AUTO_MODE='use'
  while [ "$#" -ne 0 ]; do
    case "$1" in
      --install) BEAMER_AUTO_MODE='install' ;;
      --no-use) BEAMER_AUTO_MODE='none' ;;
    esac
    shift
  done
  beamer_auto "${BEAMER_AUTO_MODE}"
}

beamer_process_parameters "$@"

} # this ensures the entire script is downloaded #
