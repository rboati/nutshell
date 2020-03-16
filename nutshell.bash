#!/bin/bash
#
# version 1.1.0
#


readonly __nutsh_rcfile=".nutsh"
readonly __nutsh_conf_dir="$HOME/.config/nutshell"


__nutsh_log_info() {
	printf -- "nutshell: %s\n" "$1" >&2
}


__nutsh_log_error() {
	printf -- "nutshell: Error! %s\n" "$1" >&2
}


__nutsh_log_warn() {
	printf -- "nutshell: Warning! %s\n" "$1" >&2
}


__nutsh_trust() {
	# shellcheck disable=SC2155
	local nutsh_dir="$(cd "${1:-.}" &> /dev/null && pwd -P)"
	if [[ -z $nutsh_dir  || ! -f "$nutsh_dir/${__nutsh_rcfile}" ]]; then
		__nutsh_log_error "'${__nutsh_rcfile}' file not found"
		return 1
	fi

	chmod u+rw,go-w,a-x "$nutsh_dir/${__nutsh_rcfile}"

	local tilde='~'
	printf -- "nutshell: Trusting \"%s\"\n" "${nutsh_dir/#$HOME/$tilde}"
	declare -i found=0
	# shellcheck disable=SC2155
	local mtime="$(__nutsh_get_mtime "$nutsh_dir/${__nutsh_rcfile}")"
	{
		while IFS=":" read -r -d '' val key; do
			if [[ $key == "$nutsh_dir" ]]; then
				val="$mtime"
				found=1
			fi
			printf "%s:%s\0" "$val" "$key"
		done < "${__nutsh_conf_dir}/trustdb"
		if (( found == 0 )); then
			printf "%s:%s\0" "$mtime" "$nutsh_dir"
		fi
	} | ( umask 0077 && cat >| "${__nutsh_conf_dir}/trustdb.tmp")

	mv -f "${__nutsh_conf_dir}/trustdb.tmp" "${__nutsh_conf_dir}/trustdb"
}


__nutsh_untrust() {
	local nutsh_dir="${1:-.}"
	if [[ -d $nutsh_dir ]]; then
		nutsh_dir="$(cd "$nutsh_dir" && pwd -P)"
	fi

	local tilde='~'
	printf -- "nutshell: Untrusting \"%s\"\n" "${nutsh_dir/#$HOME/$tilde}"
	while IFS=":" read -r -d '' val key; do
		if [[ $key == "$nutsh_dir" ]]; then
			continue
		fi
		printf "%s:%s\0" "$val" "$key"
	done < "${__nutsh_conf_dir}/trustdb" | ( umask 0077 && cat >| "${__nutsh_conf_dir}/trustdb.tmp")

	mv -f "${__nutsh_conf_dir}/trustdb.tmp" "${__nutsh_conf_dir}/trustdb"
}


__nutsh_search() {
	local cwd="$1"
	while : ; do
		if [[ -f "$cwd/${__nutsh_rcfile}" ]]; then
			echo "$cwd"
			break
		fi
		[[ $cwd  == "/" ]] && break
		cwd="$(cd "$cwd/.." && pwd)"
	done
}


__nutsh_search_env_to_load() {
	local cwd="$1"
	local prev_nutsh_dir=""
	while : ; do
		if [[ -f "$cwd/${__nutsh_rcfile}" ]]; then
			if [[ $cwd == "$NUTSHELL_DIR" ]]; then
				if [[ -z $prev_nutsh_dir ]]; then
					prev_nutsh_dir="$cwd"
				fi
				break
			fi
			prev_nutsh_dir="$cwd"
		fi

		[[ $cwd == "/" ]] && break
		cwd="$(cd "$cwd/.." && pwd)"
	done
	echo "$prev_nutsh_dir"
}


__nutsh_fancy_prompt_hook() {
	local previous_exit_status=$?
	local fmt="\e[0;36m\e[7m %15s \e[27m %s\e[0m\n"
	local tilde='~'
	local full="${NUTSHELL_DIR/#$HOME/$tilde}"

	if [[ -n $full ]]; then
		# shellcheck disable=2059
		printf -- "$fmt" NUTSHELL_DIR "$full"
	fi

	printf -- "\e[0m"
	return $previous_exit_status
}


__nutsh_exit() {
	echo "$PWD" >| "/tmp/$NUTSHELL_SESSION"
	exit 0
}


__nutsh_open_shell() {
	local nutsh_dir="$1"
	local tilde='~'
	__nutsh_log_info "Opening shell \"${nutsh_dir/#$HOME/$tilde}\""
	history -w
	(
		NUTSHELL_TARGET="$nutsh_dir" \
			exec -a "nutshell" /bin/bash
			#exec -a "nutshell(${nutsh_dir/#$HOME/$tilde})" /bin/bash
	)
	history -c; history -r
	__nutsh_log_info "Closed shell \"${nutsh_dir/#$HOME/$tilde}\""
	cd "$nutsh_dir/.." || return 1
}


__nutsh_check_trustdb() {
	if [[ ! -f "${__nutsh_conf_dir}/trustdb" ]]; then
		return 1
	fi
	# shellcheck disable=SC2155
	local mode=$(__nutsh_get_mode "${__nutsh_conf_dir}/trustdb")
	# file rw only by owner
	if (( mode != 0100600 )); then
		return 1
	fi
	return 0
}


__nutsh_find_in_trustdb() {
	if ! __nutsh_check_trustdb; then
		__nutsh_log_error "Invalid storage of trusted directories"
		return 2
	fi
	local nutsh_dir="$1"
	while IFS=":" read -r -d '' val key; do
		if [[ $key  == "$nutsh_dir" ]]; then
			printf "%s" "$val"
			return 0
		fi
	done < "${__nutsh_conf_dir}/trustdb"
	return 1
}


__nutsh_print_trustdb() {
	printf -- "%s\n" "TRUSTED DIRECTORIES"
	while IFS=":" read -r -d '' val key; do
		printf -- "- %s\n" "$key"
	done < "${__nutsh_conf_dir}/trustdb"
}


__nutsh_check() {
	local nutsh_dir="${1:-"$(pwd -P)"}"
	if [[ ! -f "$nutsh_dir/${__nutsh_rcfile}" && -O "$nutsh_dir/${__nutsh_rcfile}" ]]; then
		return 1
	fi
	# shellcheck disable=SC2155
	local trusted_mtime="$(__nutsh_find_in_trustdb "$nutsh_dir")"
	if [[ -z $trusted_mtime ]]; then
		return 1
	fi
	# shellcheck disable=SC2155
	local mtime=$(__nutsh_get_mtime "$nutsh_dir/${__nutsh_rcfile}")
	if [[ $mtime != "$trusted_mtime" ]]; then
		return 1
	fi
	# shellcheck disable=SC2155
	local mode=$(__nutsh_get_mode "$nutsh_dir/${__nutsh_rcfile}")
	# file at least readable by owner and at most readable by group and others
	if (( ( mode & 0777433 ) != 33024 )); then
		return 1
	fi

	return 0
}


__nutsh_reload() {
	if [[ -z $NUTSHELL_DIR ]]; then
		__nutsh_log_error "Not inside a nutshell!"
		return 1
	fi

	__nutsh_trust "$NUTSHELL_DIR"
	__nutsh_exit
}


__nutsh_prompt_hook() {
	local previous_exit_status=$?

	if [[ -n $NUTSHELL_TARGET ]]; then
		local tilde='~'
		local cwd="$PWD"

		readonly NUTSHELL_DIR="$NUTSHELL_TARGET"
		export NUTSHELL_DIR
		unset NUTSHELL_TARGET

		cd "$NUTSHELL_DIR" || return 1
		if __nutsh_check "$NUTSHELL_DIR"; then
			__nutsh_log_info "Sourcing \"${NUTSHELL_DIR/#$HOME/$tilde}/${__nutsh_rcfile}\""
			# shellcheck disable=1090
			. "${__nutsh_rcfile}"
		else
			__nutsh_log_warn "Skipping untrusted \"${NUTSHELL_DIR/#$HOME/$tilde}\""
		fi
		cd "$cwd" || return 1
	fi

	while : ; do
		if [[ -f "/tmp/$NUTSHELL_SESSION" ]]; then
			cd "$(cat "/tmp/$NUTSHELL_SESSION")" || return 1
			rm -f "/tmp/$NUTSHELL_SESSION"
		fi

		local cwd
		cwd="$(pwd -P)"

		local nutsh_dir
		nutsh_dir="$(__nutsh_search_env_to_load "$cwd")"

		if [[ -z $nutsh_dir ]]; then
			if [[ -z ${NUTSHELL_DIR} ]]; then
				break
			else
				__nutsh_exit
			fi
		else
			# cwd is same of found env or is subdir of found env

			if [[ -z ${NUTSHELL_DIR} ]]; then
				__nutsh_open_shell "$nutsh_dir"

			elif [[ ${NUTSHELL_DIR} == "$nutsh_dir" ]]; then
				break

			elif [[ ${nutsh_dir##${NUTSHELL_DIR}/} != "$nutsh_dir" ]]; then
				# nutsh_dir is subdir of currently loaded env
				__nutsh_open_shell "$nutsh_dir"

			else
				# nutsh_dir is not related with currently loaded env
				__nutsh_exit
			fi
		fi
	done

	return $previous_exit_status
}


__nutsh_is_active() {
	local prompt=";${PROMPT_COMMAND};"
	if [[ "${prompt/;__nutsh_prompt_hook;/}" != "$prompt" ]]; then
		return 0
	else
		return 1
	fi
}


__nutsh_activate() {
	if __nutsh_is_active; then
		return 0
	fi
	PROMPT_COMMAND="__nutsh_prompt_hook;$PROMPT_COMMAND"
}


__nutsh_deactivate() {
	if ! __nutsh_is_active; then
		return 0
	fi
	local prompt=";${PROMPT_COMMAND};"
	prompt="${prompt//;__nutsh_prompt_hook;/;}"
	prompt="${prompt#;}"; prompt="${prompt%;}"
	PROMPT_COMMAND="$prompt"
}


__nutsh_status() {
	printf -- "  PID SHELL\n"
	printf -- "%s\n" "$NUTSHELL_STACK"
	if ! __nutsh_is_active; then
		printf -- "nutshell is inactive\n"
		return 1
	fi
	return 0
}


__nutsh_init() {
	local nutsh_dir="$PWD"

	if [[ -z $nutsh_dir ]]; then
		__nutsh_log_error "Invalid path!"
		return 1
	fi

	if [[ -f "$nutsh_dir/${__nutsh_rcfile}" ]]; then
		__nutsh_log_error "File '${__nutsh_rcfile}' already exists!"
		return 1
	fi

	local template="$1"

	 if [[ -z $template ]]; then
		template="default"
	 fi

	(
		umask 033
		if [[ ! -d "${__nutsh_conf_dir}/templates" ]]; then
			mkdir -p "${__nutsh_conf_dir}/templates"
		fi

		if [[ ! -f "${__nutsh_conf_dir}/templates/default" ]]; then
			printf -- "# nutshell: see https://github.com/rboati/nutshell\n"  >| "${__nutsh_conf_dir}/templates/default"
	 	fi
	)

	if [[ ! -f "${__nutsh_conf_dir}/templates/$template" ]]; then
		__nutsh_log_error "Template \"$template\" does not exist!"
		return 1
	fi

	cp -f "${__nutsh_conf_dir}/templates/$template" "$nutsh_dir/${__nutsh_rcfile}"
	__nutsh_trust "$nutsh_dir"
}


nutshell() {
	case "$1" in
		init)
			shift; __nutsh_init "$1" ;;
		status)
			__nutsh_status ;;
		trust)
			shift; __nutsh_trust "$1" ;;
		untrust)
			shift; __nutsh_untrust "$1" ;;
		show)
			__nutsh_print_trustdb ;;
		reload)
			__nutsh_reload ;;
		*)
			cat <<- EOF
				nutshell [command]
				Available commands:
				  init [template]  Initialize current directory with a default '${__nutsh_rcfile}' file
				                   or one specified by template name
				  status           Show nutshell nesting status
				  trust [dir]      Trust current directory or "dir" if specified
				  untrust [dir]    Untrust current directory or "dir" if specified
				  show             Print trusted directories
				  reload           Trust '\$NUTSHELL_DIR/${__nutsh_rcfile}' file and reload current nutshell

				EOF
			;;
	esac
}

nutsh() {
	nutshell "$@"
}


__nutsh_complete() {
	local cur_word="${COMP_WORDS[COMP_CWORD]}"
	local prev_word="${COMP_WORDS[COMP_CWORD-1]}"
	local cmd_list="init status trust untrust show reload"
	if (( COMP_CWORD == 1 )); then
		IFS=" " read -r -a COMPREPLY <<< "$(compgen -W "${cmd_list}" -- "${cur_word}")"
		return 0
	fi

	if (( COMP_CWORD == 2 )); then
		case "$prev_word" in
		init)
			compopt -o nospace &> /dev/null
			for i in $(compgen -o nospace -f -- "${__nutsh_conf_dir}/templates/${cur_word}"); do
				COMPREPLY+=( "${i##*/}" )
			done
			return 0
			;;
		trust)
			compopt -o nospace &> /dev/null
			local IFS=$'\n'
			for i in $(compgen -o nospace -d -- "${cur_word}"); do
				COMPREPLY+=( "'${i%/}/'" )
			done
			return 0
			;;
		untrust)
			cur_word="$(cd "$cur_word" &> /dev/null && pwd -P || echo "$cur_word")"
			local word_list=""
			while IFS=":" read -r -d '' val key; do
				word_list+="$key"$'\n'
			done < "${__nutsh_conf_dir}/trustdb"
			local IFS=$'\n'
			for i in $(compgen -o nospace -W "$word_list" -- "${cur_word}"); do
				COMPREPLY+=( "'${i}'" )
			done
			return 0
			;;
		esac

	fi

	return 0
}


__nutsh_setup() {
	# Disabling for Midnight Commander
	if [[ -n $MC_SID ]]; then
		return 1
	fi

	if [[ -z $NUTSHELL_SESSION ]]; then
		readonly NUTSHELL_SESSION="nutsh-$$"
		export NUTSHELL_SESSION

		# first time setup
		if [[ ! -d "${__nutsh_conf_dir}" ]]; then
			mkdir -p "${__nutsh_conf_dir}"
		fi
		if [[ ! -f "${__nutsh_conf_dir}/trustdb" ]]; then
			( umask 0077 && : >| "${__nutsh_conf_dir}/trustdb")
		fi

	fi

	local -i err=0
	for arg in "$@"; do
		case "$arg" in
			prompt | quiet) ;;
			help)
				cat <<- EOF
					nutshell.bash [options...]
					Available options:
					  prompt           Add an informative prompt
					  quiet            Stop printing informations
					EOF
				return 0
				;;
			*)
				__nutsh_log_error "Invalid option '$arg'"
				err=1
				;;
		esac
	done

	if (( err == 1 )); then
		return 1
	fi

	for arg in "$@"; do
		case "$arg" in
			prompt) PROMPT_COMMAND="__nutsh_fancy_prompt_hook;$PROMPT_COMMAND" ;;
			quiet) __nutsh_log_info() { :; } ;;
		esac
	done
	PROMPT_COMMAND="__nutsh_prompt_hook;$PROMPT_COMMAND"
	complete -F __nutsh_complete nutsh nutshell

	if [[ -n $NUTSHELL_TARGET ]]; then
		local tilde="~"
		printf -v NUTSHELL_STACK -- "%s%5i nutshell (%s)\n" "$NUTSHELL_STACK" "$$" "${NUTSHELL_TARGET/#$HOME/$tilde}"
	else
		printf -v NUTSHELL_STACK -- "%s%5i %s\n" "$NUTSHELL_STACK" "$$" "$0"
	fi

	readonly NUTSHELL_STACK
	export NUTSHELL_STACK
}


case "$OSTYPE" in
*linux*|*hurd*|*msys*|*cygwin*|*sua*|*interix*)
	__nutsh_get_mtime() { stat -L -c "%Y" "$1"; }
	__nutsh_get_mode() { stat -L -c "0x%f" "$1"; }
	;;
*bsd*|*darwin*)
	__nutsh_get_mtime() { stat -L -f "%m" "$1"; }
	__nutsh_get_mode() { stat -L -f "0%p" "$1"; }
	;;
*)
	__nutsh_log_error "Unsupported OS"
	return 1
	;;
esac


__nutsh_setup "$@"
