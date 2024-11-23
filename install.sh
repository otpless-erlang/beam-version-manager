#!/usr/bin/env bash

{ # this ensures the entire script is downloaded #

beamer_has() {
  type "$1" > /dev/null 2>&1
}

beamer_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

if [ -z "${BASH_VERSION}" ] || [ -n "${ZSH_VERSION}" ]; then
  # shellcheck disable=SC2016
  beamer_echo >&2 'Error: the install instructions explicitly say to pipe the install script to `bash`; please follow them'
  exit 1
fi

beamer_grep() {
  GREP_OPTIONS='' command grep "$@"
}

beamer_default_install_dir() {
  [ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.beamer" || printf %s "${XDG_CONFIG_HOME}/beamer"
}

beamer_install_dir() {
  if [ -n "$BEAMER_DIR" ]; then
    printf %s "${BEAMER_DIR}"
  else
    beamer_default_install_dir
  fi
}

beamer_latest_version() {
  beamer_echo "v0.40.1"
}

beamer_profile_is_bash_or_zsh() {
  local TEST_PROFILE
  TEST_PROFILE="${1-}"
  case "${TEST_PROFILE-}" in
    *"/.bashrc" | *"/.bash_profile" | *"/.zshrc" | *"/.zprofile")
      return
    ;;
    *)
      return 1
    ;;
  esac
}

#
# Outputs the location to BEAMER depending on:
# * The availability of $BEAMER_SOURCE
# * The presence of $BEAMER_INSTALL_GITHUB_REPO
# * The method used ("script" or "git" in the script, defaults to "git")
# BEAMER_SOURCE always takes precedence unless the method is "script-beamer-exec"
#
beamer_source() {
  local BEAMER_GITHUB_REPO
  BEAMER_GITHUB_REPO="${BEAMER_INSTALL_GITHUB_REPO:-beamer-sh/beamer}"
  if [ "${BEAMER_GITHUB_REPO}" != 'beamer-sh/beamer' ]; then
    { beamer_echo >&2 "$(cat)" ; } << EOF
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE REPO IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!

The default repository for this install is \`beamer-sh/beamer\`,
but the environment variables \`\$BEAMER_INSTALL_GITHUB_REPO\` is
currently set to \`${BEAMER_GITHUB_REPO}\`.

If this is not intentional, interrupt this installation and
verify your environment variables.
EOF
  fi
  local BEAMER_VERSION
  BEAMER_VERSION="${BEAMER_INSTALL_VERSION:-$(beamer_latest_version)}"
  local BEAMER_METHOD
  BEAMER_METHOD="$1"
  local BEAMER_SOURCE_URL
  BEAMER_SOURCE_URL="$BEAMER_SOURCE"
  if [ "_$BEAMER_METHOD" = "_script-beamer-exec" ]; then
    BEAMER_SOURCE_URL="https://raw.githubusercontent.com/${BEAMER_GITHUB_REPO}/${BEAMER_VERSION}/beamer-exec"
  elif [ "_$BEAMER_METHOD" = "_script-beamer-bash-completion" ]; then
    BEAMER_SOURCE_URL="https://raw.githubusercontent.com/${BEAMER_GITHUB_REPO}/${BEAMER_VERSION}/bash_completion"
  elif [ -z "$BEAMER_SOURCE_URL" ]; then
    if [ "_$BEAMER_METHOD" = "_script" ]; then
      BEAMER_SOURCE_URL="https://raw.githubusercontent.com/${BEAMER_GITHUB_REPO}/${BEAMER_VERSION}/beamer.sh"
    elif [ "_$BEAMER_METHOD" = "_git" ] || [ -z "$BEAMER_METHOD" ]; then
      BEAMER_SOURCE_URL="https://github.com/${BEAMER_GITHUB_REPO}.git"
    else
      beamer_echo >&2 "Unexpected value \"$BEAMER_METHOD\" for \$BEAMER_METHOD"
      return 1
    fi
  fi
  beamer_echo "$BEAMER_SOURCE_URL"
}

#
# OTPless Erlang version to install
#
beamer_node_version() {
  beamer_echo "$NODE_VERSION"
}

beamer_download() {
  if beamer_has "curl"; then
    curl --fail --compressed -q "$@"
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
    # shellcheck disable=SC2086
    eval wget $ARGS
  fi
}

install_beamer_from_git() {
  local INSTALL_DIR
  INSTALL_DIR="$(beamer_install_dir)"
  local BEAMER_VERSION
  BEAMER_VERSION="${BEAMER_INSTALL_VERSION:-$(beamer_latest_version)}"
  if [ -n "${BEAMER_INSTALL_VERSION:-}" ]; then
    # Check if version is an existing ref
    if command git ls-remote "$(beamer_source "git")" "$BEAMER_VERSION" | beamer_grep -q "$BEAMER_VERSION" ; then
      :
    # Check if version is an existing changeset
    elif ! beamer_download -o /dev/null "$(beamer_source "script-beamer-exec")"; then
      beamer_echo >&2 "Failed to find '$BEAMER_VERSION' version."
      exit 1
    fi
  fi

  local fetch_error
  if [ -d "$INSTALL_DIR/.git" ]; then
    # Updating repo
    beamer_echo "=> beamer is already installed in $INSTALL_DIR, trying to update using git"
    command printf '\r=> '
    fetch_error="Failed to update beamer with $BEAMER_VERSION, run 'git fetch' in $INSTALL_DIR yourself."
  else
    fetch_error="Failed to fetch origin with $BEAMER_VERSION. Please report this!"
    beamer_echo "=> Downloading beamer from git to '$INSTALL_DIR'"
    command printf '\r=> '
    mkdir -p "${INSTALL_DIR}"
    if [ "$(ls -A "${INSTALL_DIR}")" ]; then
      # Initializing repo
      command git init "${INSTALL_DIR}" || {
        beamer_echo >&2 'Failed to initialize beamer repo. Please report this!'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" remote add origin "$(beamer_source)" 2> /dev/null \
        || command git --git-dir="${INSTALL_DIR}/.git" remote set-url origin "$(beamer_source)" || {
        beamer_echo >&2 'Failed to add remote "origin" (or set the URL). Please report this!'
        exit 2
      }
    else
      # Cloning repo
      command git clone "$(beamer_source)" --depth=1 "${INSTALL_DIR}" || {
        beamer_echo >&2 'Failed to clone beamer repo. Please report this!'
        exit 2
      }
    fi
  fi
  # Try to fetch tag
  if command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin tag "$BEAMER_VERSION" --depth=1 2>/dev/null; then
    :
  # Fetch given version
  elif ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin "$BEAMER_VERSION" --depth=1; then
    beamer_echo >&2 "$fetch_error"
    exit 1
  fi
  command git -c advice.detachedHead=false --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" checkout -f --quiet FETCH_HEAD || {
    beamer_echo >&2 "Failed to checkout the given version $BEAMER_VERSION. Please report this!"
    exit 2
  }
  if [ -n "$(command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" show-ref refs/heads/master)" ]; then
    if command git --no-pager --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet 2>/dev/null; then
      command git --no-pager --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet -D master >/dev/null 2>&1
    else
      beamer_echo >&2 "Your version of git is out of date. Please update it!"
      command git --no-pager --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch -D master >/dev/null 2>&1
    fi
  fi

  beamer_echo "=> Compressing and cleaning up git repository"
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" reflog expire --expire=now --all; then
    beamer_echo >&2 "Your version of git is out of date. Please update it!"
  fi
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" gc --auto --aggressive --prune=now ; then
    beamer_echo >&2 "Your version of git is out of date. Please update it!"
  fi
  return
}

#
# Automatically install OTPless Erlang
#
beamer_install_node() {
  local NODE_VERSION_LOCAL
  NODE_VERSION_LOCAL="$(beamer_node_version)"

  if [ -z "$NODE_VERSION_LOCAL" ]; then
    return 0
  fi

  beamer_echo "=> Installing OTPless Erlang version $NODE_VERSION_LOCAL"
  beamer install "$NODE_VERSION_LOCAL"
  local CURRENT_BEAMER_NODE

  CURRENT_BEAMER_NODE="$(beamer_version current)"
  if [ "$(beamer_version "$NODE_VERSION_LOCAL")" == "$CURRENT_BEAMER_NODE" ]; then
    beamer_echo "=> OTPless Erlang version $NODE_VERSION_LOCAL has been successfully installed"
  else
    beamer_echo >&2 "Failed to install OTPless Erlang $NODE_VERSION_LOCAL"
  fi
}

install_beamer_as_script() {
  local INSTALL_DIR
  INSTALL_DIR="$(beamer_install_dir)"
  local BEAMER_SOURCE_LOCAL
  BEAMER_SOURCE_LOCAL="$(beamer_source script)"
  local BEAMER_EXEC_SOURCE
  BEAMER_EXEC_SOURCE="$(beamer_source script-beamer-exec)"
  local BEAMER_BASH_COMPLETION_SOURCE
  BEAMER_BASH_COMPLETION_SOURCE="$(beamer_source script-beamer-bash-completion)"

  # Downloading to $INSTALL_DIR
  mkdir -p "$INSTALL_DIR"
  if [ -f "$INSTALL_DIR/beamer.sh" ]; then
    beamer_echo "=> beamer is already installed in $INSTALL_DIR, trying to update the script"
  else
    beamer_echo "=> Downloading beamer as script to '$INSTALL_DIR'"
  fi
  beamer_download -s "$BEAMER_SOURCE_LOCAL" -o "$INSTALL_DIR/beamer.sh" || {
    beamer_echo >&2 "Failed to download '$BEAMER_SOURCE_LOCAL'"
    return 1
  } &
  beamer_download -s "$BEAMER_EXEC_SOURCE" -o "$INSTALL_DIR/beamer-exec" || {
    beamer_echo >&2 "Failed to download '$BEAMER_EXEC_SOURCE'"
    return 2
  } &
  beamer_download -s "$BEAMER_BASH_COMPLETION_SOURCE" -o "$INSTALL_DIR/bash_completion" || {
    beamer_echo >&2 "Failed to download '$BEAMER_BASH_COMPLETION_SOURCE'"
    return 2
  } &
  for job in $(jobs -p | command sort)
  do
    wait "$job" || return $?
  done
  chmod a+x "$INSTALL_DIR/beamer-exec" || {
    beamer_echo >&2 "Failed to mark '$INSTALL_DIR/beamer-exec' as executable"
    return 3
  }
}

beamer_try_profile() {
  if [ -z "${1-}" ] || [ ! -f "${1}" ]; then
    return 1
  fi
  beamer_echo "${1}"
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
beamer_detect_profile() {
  if [ "${PROFILE-}" = '/dev/null' ]; then
    # the user has specifically requested NOT to have beamer touch their profile
    return
  fi

  if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
    beamer_echo "${PROFILE}"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''

  if [ "${SHELL#*bash}" != "$SHELL" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ "${SHELL#*zsh}" != "$SHELL" ]; then
    if [ -f "$HOME/.zshrc" ]; then
      DETECTED_PROFILE="$HOME/.zshrc"
    elif [ -f "$HOME/.zprofile" ]; then
      DETECTED_PROFILE="$HOME/.zprofile"
    fi
  fi

  if [ -z "$DETECTED_PROFILE" ]; then
    for EACH_PROFILE in ".profile" ".bashrc" ".bash_profile" ".zprofile" ".zshrc"
    do
      if DETECTED_PROFILE="$(beamer_try_profile "${HOME}/${EACH_PROFILE}")"; then
        break
      fi
    done
  fi

  if [ -n "$DETECTED_PROFILE" ]; then
    beamer_echo "$DETECTED_PROFILE"
  fi
}

#
# Check whether the user has any globally-installed npm modules in their system
# Node, and warn them if so.
#
beamer_check_global_modules() {
  local NPM_COMMAND
  NPM_COMMAND="$(command -v npm 2>/dev/null)" || return 0
  [ -n "${BEAMER_DIR}" ] && [ -z "${NPM_COMMAND%%"$BEAMER_DIR"/*}" ] && return 0

  local NPM_VERSION
  NPM_VERSION="$(npm --version)"
  NPM_VERSION="${NPM_VERSION:--1}"
  [ "${NPM_VERSION%%[!-0-9]*}" -gt 0 ] || return 0

  local NPM_GLOBAL_MODULES
  NPM_GLOBAL_MODULES="$(
    npm list -g --depth=0 |
    command sed -e '/ npm@/d' -e '/ (empty)$/d'
  )"

  local MODULE_COUNT
  MODULE_COUNT="$(
    command printf %s\\n "$NPM_GLOBAL_MODULES" |
    command sed -ne '1!p' |                     # Remove the first line
    wc -l | command tr -d ' '                   # Count entries
  )"

  if [ "${MODULE_COUNT}" != '0' ]; then
    # shellcheck disable=SC2016
    beamer_echo '=> You currently have modules installed globally with `npm`. These will no'
    # shellcheck disable=SC2016
    beamer_echo '=> longer be linked to the active version of Node when you install a new node'
    # shellcheck disable=SC2016
    beamer_echo '=> with `beamer`; and they may (depending on how you construct your `$PATH`)'
    # shellcheck disable=SC2016
    beamer_echo '=> override the binaries of modules installed with `beamer`:'
    beamer_echo

    command printf %s\\n "$NPM_GLOBAL_MODULES"
    beamer_echo '=> If you wish to uninstall them at a later point (or re-install them under your'
    # shellcheck disable=SC2016
    beamer_echo '=> `beamer` node installs), you can remove them from the system Node as follows:'
    beamer_echo
    beamer_echo '     $ beamer use system'
    beamer_echo '     $ npm uninstall -g a_module'
    beamer_echo
  fi
}

beamer_do_install() {
  if [ -n "${BEAMER_DIR-}" ] && ! [ -d "${BEAMER_DIR}" ]; then
    if [ -e "${BEAMER_DIR}" ]; then
      beamer_echo >&2 "File \"${BEAMER_DIR}\" has the same name as installation directory."
      exit 1
    fi

    if [ "${BEAMER_DIR}" = "$(beamer_default_install_dir)" ]; then
      mkdir "${BEAMER_DIR}"
    else
      beamer_echo >&2 "You have \$BEAMER_DIR set to \"${BEAMER_DIR}\", but that directory does not exist. Check your profile files and environment."
      exit 1
    fi
  fi
  # Disable the optional which check, https://www.shellcheck.net/wiki/SC2230
  # shellcheck disable=SC2230
  if beamer_has xcode-select && [ "$(xcode-select -p >/dev/null 2>/dev/null ; echo $?)" = '2' ] && [ "$(which git)" = '/usr/bin/git' ] && [ "$(which curl)" = '/usr/bin/curl' ]; then
    beamer_echo >&2 'You may be on a Mac, and need to install the Xcode Command Line Developer Tools.'
    # shellcheck disable=SC2016
    beamer_echo >&2 'If so, run `xcode-select --install` and try again. If not, please report this!'
    exit 1
  fi
  if [ -z "${METHOD}" ]; then
    # Autodetect install method
    if beamer_has git; then
      install_beamer_from_git
    elif beamer_has curl || beamer_has wget; then
      install_beamer_as_script
    else
      beamer_echo >&2 'You need git, curl, or wget to install beamer'
      exit 1
    fi
  elif [ "${METHOD}" = 'git' ]; then
    if ! beamer_has git; then
      beamer_echo >&2 "You need git to install beamer"
      exit 1
    fi
    install_beamer_from_git
  elif [ "${METHOD}" = 'script' ]; then
    if ! beamer_has curl && ! beamer_has wget; then
      beamer_echo >&2 "You need curl or wget to install beamer"
      exit 1
    fi
    install_beamer_as_script
  else
    beamer_echo >&2 "The environment variable \$METHOD is set to \"${METHOD}\", which is not recognized as a valid installation method."
    exit 1
  fi

  beamer_echo

  local BEAMER_PROFILE
  BEAMER_PROFILE="$(beamer_detect_profile)"
  local PROFILE_INSTALL_DIR
  PROFILE_INSTALL_DIR="$(beamer_install_dir | command sed "s:^$HOME:\$HOME:")"

  SOURCE_STR="\\nexport BEAMER_DIR=\"${PROFILE_INSTALL_DIR}\"\\n[ -s \"\$BEAMER_DIR/beamer.sh\" ] && \\. \"\$BEAMER_DIR/beamer.sh\"  # This loads beamer\\n"

  # shellcheck disable=SC2016
  COMPLETION_STR='[ -s "$BEAMER_DIR/bash_completion" ] && \. "$BEAMER_DIR/bash_completion"  # This loads beamer bash_completion\n'
  BASH_OR_ZSH=false

  if [ -z "${BEAMER_PROFILE-}" ] ; then
    local TRIED_PROFILE
    if [ -n "${PROFILE}" ]; then
      TRIED_PROFILE="${BEAMER_PROFILE} (as defined in \$PROFILE), "
    fi
    beamer_echo "=> Profile not found. Tried ${TRIED_PROFILE-}~/.bashrc, ~/.bash_profile, ~/.zprofile, ~/.zshrc, and ~/.profile."
    beamer_echo "=> Create one of them and run this script again"
    beamer_echo "   OR"
    beamer_echo "=> Append the following lines to the correct file yourself:"
    command printf "${SOURCE_STR}"
    beamer_echo
  else
    if beamer_profile_is_bash_or_zsh "${BEAMER_PROFILE-}"; then
      BASH_OR_ZSH=true
    fi
    if ! command grep -qc '/beamer.sh' "$BEAMER_PROFILE"; then
      beamer_echo "=> Appending beamer source string to $BEAMER_PROFILE"
      command printf "${SOURCE_STR}" >> "$BEAMER_PROFILE"
    else
      beamer_echo "=> beamer source string already in ${BEAMER_PROFILE}"
    fi
    # shellcheck disable=SC2016
    if ${BASH_OR_ZSH} && ! command grep -qc '$BEAMER_DIR/bash_completion' "$BEAMER_PROFILE"; then
      beamer_echo "=> Appending bash_completion source string to $BEAMER_PROFILE"
      command printf "$COMPLETION_STR" >> "$BEAMER_PROFILE"
    else
      beamer_echo "=> bash_completion source string already in ${BEAMER_PROFILE}"
    fi
  fi
  if ${BASH_OR_ZSH} && [ -z "${BEAMER_PROFILE-}" ] ; then
    beamer_echo "=> Please also append the following lines to the if you are using bash/zsh shell:"
    command printf "${COMPLETION_STR}"
  fi

  # Source beamer
  # shellcheck source=/dev/null
  \. "$(beamer_install_dir)/beamer.sh"

  beamer_check_global_modules

  beamer_install_node

  beamer_reset

  beamer_echo "=> Close and reopen your terminal to start using beamer or run the following to use it now:"
  command printf "${SOURCE_STR}"
  if ${BASH_OR_ZSH} ; then
    command printf "${COMPLETION_STR}"
  fi
}

#
# Unsets the various functions defined
# during the execution of the install script
#
beamer_reset() {
  unset -f beamer_has beamer_install_dir beamer_latest_version beamer_profile_is_bash_or_zsh \
    beamer_source beamer_node_version beamer_download install_beamer_from_git beamer_install_node \
    install_beamer_as_script beamer_try_profile beamer_detect_profile beamer_check_global_modules \
    beamer_do_install beamer_reset beamer_default_install_dir beamer_grep
}

[ "_$BEAMER_ENV" = "_testing" ] || beamer_do_install

} # this ensures the entire script is downloaded #
