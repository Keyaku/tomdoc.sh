#!/bin/bash
#/ Usage: tomdoc.sh [options] [--] [<shell-script>...]
#/
#/     -h, --help               show help text
#/     --version                show version
#/     -t, --text               produce plain text (default format)
#/     -m, --markdown           produce markdown
#/     -a, --access <level>     filter by access level
#/
#/ Parse TomDoc'd shell scripts and generate pretty documentation from it.
#
# Written by Mathias Lafeldt <mathias.lafeldt@gmail.com>, later project was
# transfered to Tyler Akins <fidian@rumkin.com>.
# Forked by António Sarmento (a.k.a. Keyaku).

set -e
[[ -n "$TOMDOCSH_DEBUG" ]] && set -x

# Current version of tomdoc.sh.
TOMDOCSH_VERSION="0.2.0"

generate=generate_text
access=

# Regular expression matching at least one whitespace.
SPACE_RE='[[:space:]]+'

# Regular expression matching optional whitespace.
OPTIONAL_SPACE_RE='[[:space:]]*'

# The inverse of the above, must match at least one character
NOT_SPACE_RE='[^[:space:]]+'

# Regular expression for 0 or 1. Special case for Mac.
Z_1="$([ $(uname -s) = Darwin ] && echo '{0,1}' || echo '?')"

# Regular expression matching shell function or variable name.
FUNC_NAME_RE="[a-zA-Z_][a-zA-Z0-9_:]*"

# Regular expression matching variable names.  Similar to FUNC_NAME_RE.
# Variables are far more restrictive.
#
# Leading characters can be A-Z, _, a-z.
# Secondary characters can be 0-9, =, A-Z, _, a-z
VAR_NAME_RE='[A-Z_a-z][0-9=A-Z_a-z]*'

# Strip leading whitespace and '#' from TomDoc strings.
#
# Can not use ?, use {0,1} instead to preserve Mac support.
#
# Returns nothing.
uncomment() {
	sed -E "s/^$OPTIONAL_SPACE_RE#[[:space:]]$Z_1//"
}

# Joins an array into a character-delimited string.
#
# $1 - Delimiter
# $@ - Array
function str_join {
	local d=${1-} f=${2-}
	if shift 2; then
		printf %s "$f" "${*/#/$d}"
	fi
}

# Generate the documentation for a shell function or variable in plain text
# format and write it to stdout.
#
# $1 - Function or variable name
# $2 - TomDoc string
#
# Returns nothing.
generate_text() {
	cat <<EOF
--------------------------------------------------------------------------------
$1

$(printf "%s" "$2" | uncomment)

EOF
}

# Generate the documentation for a shell function or variable in markdown format
# and write it to stdout.
#
# $1 - Function or variable name
# $2 - TomDoc string
#
# Returns nothing.
generate_markdown() {
	printf "%s\n" '`'"$1"'`'
	printf "%s" " $1 " | tr -c - -
	printf "\n\n"

	local line last
	local did_newline=false
	local last_was_option=false

	printf "%s\n" "$2" | uncomment | sed -e "s/$SPACE_RE$//" | while IFS='' read -r line; do
		if printf "%s" "$line" | grep -q "^$OPTIONAL_SPACE_RE$NOT_SPACE_RE$SPACE_RE-$SPACE_RE"; then
			# This is for arguments
			if ! $did_newline; then
				printf "\n"
			fi

			if printf "%s" "$line" | grep -q "^$NOT_SPACE_RE"; then
				printf "%s" "* $line"
			else
				# Careful - BSD sed always adds a newline
				printf "    * "
				printf "%s" "$line" | sed "s/^$SPACE_RE//" | tr -d "\n"
			fi

			last_was_option=true

			# shellcheck disable=SC2030

			did_newline=false
		else
			case "$line" in
			"")
				# Check for end of paragraph / section
				if ! $did_newline; then
					printf "\n"
				fi

				printf "\n"
				did_newline=true
				last_was_option=false
				;;

			"  "*)
				# Examples and option continuation
				if $last_was_option; then
					# Careful - BSD sed always adds a newline
					printf "%s" "$line" | sed "s/^ */ /" | tr -d "\n"
					did_newline=false
				else
					printf "  %s\n" "$line"
					did_newline=true
				fi
				;;

			"* "* )
				# A list should not continue a previous paragraph.
				printf "%s\n" "$line"
				did_newline=true
				;;

			*)
				# Paragraph text (does not start with a space)
				case "$last" in
				"")
					# Start a new paragraph - no space at the beginning
					printf "%s" "$line"
					;;

				*)
					# Continue this line - include space at the beginning
					printf "\n%s" "$line"
					;;
				esac

				did_newline=false
				last_was_option=false
				;;
			esac
		fi

		last="$line"
	done
	set +x

	# shellcheck disable=SC2031

	if ! $did_newline; then
		printf "\n"
	fi
}

# Read lines from stdin, look for shell function or variable definition, and
# print function or variable name if found; otherwise, print nothing.
#
# Returns nothing.
parse_code() {
	local LIST_exprs=(
		## Functions
		"s/^${OPTIONAL_SPACE_RE}(${FUNC_NAME_RE})${OPTIONAL_SPACE_RE}\(\).*$/\1()/p"
		"s/^${OPTIONAL_SPACE_RE}function${SPACE_RE}(${FUNC_NAME_RE}).*$/\1()/p"
		## Variables
		"s/^${OPTIONAL_SPACE_RE}(export)${SPACE_RE}(${VAR_NAME_RE})=$Z_1.*$/\2/p"
		"s/^${OPTIONAL_SPACE_RE}(${VAR_NAME_RE})=.*$/\1/p"
		"s/^${OPTIONAL_SPACE_RE}(declare|typeset)${SPACE_RE}(-[a-zA-Z]*${SPACE_RE})$Z_1(${VAR_NAME_RE})=$Z_1.*$/\3/p"
		"s/^${OPTIONAL_SPACE_RE}(readonly)${SPACE_RE}(${VAR_NAME_RE})(=$Z_1.*)$/const \2\3/p"
		## Other
		"s/^${OPTIONAL_SPACE_RE}:${SPACE_RE}\$\{(${VAR_NAME_RE}):$Z_1=.*$/\1/p"
	)
	sed -n -E "$(str_join ';' "${LIST_exprs[@]}")"
}

# Read lines from stdin, look for TomDoc'd shell functions and variables, and
# pass them to a generator for formatting.
#
# Returns nothing.
parse_tomdoc() {
	local doc name line
	while read -r line; do
		case "$line" in
		'# shellcheck'*)
			continue
			;;

		'#' | '# '*)
			doc+="$line
"
			;;
		*)
			[[ -n "$line" ]] && [[ -n "$doc" ]] && {
				# Match access level if given.
				[[ -n "$access" ]] && {
					case "$doc" in
					"# $access:"*) ;;

					*)
						doc=
						continue
						;;
					esac
				}

				name="$(echo "$line" | parse_code)"
				[[ -n "$name" ]] && "$generate" "$name" "$doc"
			}
			doc=
			;;
		esac
	done
}

### SCRIPT STARTS HERE

if [[ $# -eq 0 ]] && [[ -t 0 ]]; then
	set -- --usage 1
fi

while [[ $# -ne 0 ]]; do
	case "$1" in
	-h | --help)
		grep '^#/' <"$0" | cut -c4-
		exit 0
		;;
	--usage )
		grep '^#/' <"$0" | head -n1 | cut -c4-
		if [[ $# -eq 2 ]] && [[ $2 =~ ^[0-9]+$ ]]; then
			retval=$2
		else
			retval=0
		fi
		exit $retval
		;;
	--version)
		printf "tomdoc.sh version %s\n" "$TOMDOCSH_VERSION"
		exit 0
		;;
	-t | --text)
		generate=generate_text
		shift
		;;
	-m | --mark | --markdown)
		generate=generate_markdown
		shift
		;;
	-a | --access)
		[[ $# -ge 2 ]] || {
			printf "error: %s requires an argument\n" "$1" >&2
			exit 1
		}
		access="$2"
		shift 2
		;;
	--)
		shift
		break
		;;
	- | [!-]*)
		break
		;;
	-*)
		printf "error: invalid option '%s'\n" "$1" >&2
		exit 1
		;;
	esac
done
cat -- "$@" | parse_tomdoc

:
