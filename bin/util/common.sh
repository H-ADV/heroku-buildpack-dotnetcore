print() {
	echo "-----> $*"
}

indent() {
	c='s/^/       /'
	case $(uname) in
	Darwin) sed -l "$c";;
	*)      sed -u "$c";;
	esac
}

get_os() {
	uname | tr '[:upper:]' '[:lower:]'
}

get_cpu() {
	if [[ "$(uname -p)" = "i686" ]]; then
	echo "x86"
	else
	echo "x64"
	fi
}

get_platform() {
	os=$(get_os)
	cpu=$(get_cpu)
	echo "$os-$cpu"
}

get_linux_platform_version() {
	if [ -e /etc/os-release ]; then
	    . /etc/os-release
	    echo ${VERSION_ID//[a-z]/}
	    return 0
	fi

	print "Linux specific platform version could not be detected: UName = $uname"
	return 1
}

error() {
	local c="2,999 s/^/ !     /"
	# send all of our output to stderr
	exec 1>&2

	echo -e "\033[1;31m" # bold; red
	echo -n " !     ERROR: "
	# this will be fed from stdin
	case $(uname) in
		Darwin) sed -l "$c";; # mac/bsd sed: -l buffers on line boundaries
		*)      sed -u "$c";; # unix/gnu sed: -u unbuffered (arbitrary) chunks of data
	esac
	echo -e "\033[0m" # reset style
	exit 1
}

export_env_dir() {
	local env_dir=$1
	if [ -d "$env_dir" ]; then
		local whitelist_regex=${2:-''}
		local blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH|LANG|BUILD_DIR)$'}
		# shellcheck disable=SC2164
		pushd "$env_dir" >/dev/null
		for e in *; do
			[ -e "$e" ] || continue
			echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
			export "$e=$(cat "$e")"
			:
		done
		# shellcheck disable=SC2164
		popd >/dev/null
	fi
}

# args:
# input - $1,$2
string_replace() {
    #DOC: "${string/match/replace}"
    string=$1
    echo "${string/$2/$3}"
}

# args:
# input - $1
remove_trailing_slash() {
    local input="${1:-}"
    echo "${input%/}"
    return 0
}

# args:
# input - $1
remove_beginning_slash() {
    local input="${1:-}"
    echo "${input#/}"
    return 0
}

# args:
# input - $1
get_project_sln_file() {
	local solutionfile=$(x=$(dirname $(find $1 -maxdepth 1 -type f | head -1)); while [[ "$x" =~ $1 ]] ; do find "$x" -maxdepth 1 -name *.sln; x=`dirname "$x"`; done)
	echo $solutionfile
}

# args:
# input - $1
get_project_sln_name() {
	local solution_name=""
	local solutionfile="$(get_project_sln_file $1)"
	if [[ $solutionfile ]]; then
		solution_name=$(basename ${solutionfile%.*})
	fi
	echo $solution_name
}

# args:
# input - $1
get_project_file() {
	local projectfile=""
	local all_projects=$(x=$(dirname $(find $1 -maxdepth 2 -type f | head -1)); while [[ "$x" =~ $1 ]] ; do find "$x" -maxdepth 1 -name *.csproj; x=`dirname "$x"`; done)
	
	# Filter out WorkerApp projects and get the first non-WorkerApp project
	for project in $all_projects; do
		if [[ "$(is_worker_app_project "$project")" == "no" ]]; then
			projectfile="$project"
			break
		fi
	done
	
	echo $projectfile
}

# args:
# input - $1
get_project_name() {
	local project_name=""
	local project_file="$(get_project_file $1)"
	if [[ $project_file ]]; then
		project_name=$(basename ${project_file%.*})
	fi
	echo $project_name
}

# args:
# input - $1
get_start_project_name() {
	local project_name=""
	local launchSettingsFile=$(x=$(dirname $(find $1 -maxdepth 1 -type f | head -1)); while [[ "$x" =~ $1 ]] ; do find "$x" -maxdepth 3 -name launchSettings.json; x=`dirname "$x"`; done)
	if [[ $launchSettingsFile ]]; then
		project_name=$(basename $(dirname $(dirname ${launchSettingsFile%.*})))
	fi
	echo $project_name
}

# args:
# input - $1
get_specific_version() {
	local sVersion=""
	local productVersion=$(x=$(dirname $(find $1 -maxdepth 1 -type f | head -1)); while [[ "$x" =~ $1 ]] ; do find "$x" -maxdepth 3 -name productVersion.txt; x=`dirname "$x"`; done)
	if [[ $productVersion ]]; then
		sVersion=`cat $productVersion`
	fi
	echo $sVersion
}

# args:
# input - $1
get_framework_version() {
	local target_framework=$(grep -oPm1 "(?<=<TargetFramework>)[^<]+" $1/*.csproj)
	if [[ $target_framework =~ ";" ]]; then
	 	echo $(cut -d ';' -f 1 <<< $target_framework)
	else
		echo ${target_framework//[a-z]/}
	fi
}

# args:
# input - $1
get_runtime_framework_version() {
	local runtime_framework_version=$(grep -oPm1 "(?<=<RuntimeFrameworkVersion>)[^<]+" $1/*.csproj)
	if [[ ${#runtime_framework_version} -eq 0 ]]; then
		echo "Latest"
	elif [[ $runtime_framework_version == *"rc"* ]] || [[ $runtime_framework_version == *"preview"* ]]; then
		echo "${runtime_framework_version}"
	else
		echo "${runtime_framework_version//[a-z]/}"
	fi
}

# args:
# input - $1
is_postgres_used() {
	echo "$(grep -q "Npgsql" $1/*.csproj && echo 'yes' || echo 'no')"
}

# args:
# input - $1
source_envfile() { export $(cat $1 | sed -e /^$/d -e /^#/d | xargs); }

# args:
# input - $1, $2
decimal_compare() {
   awk -v n1="$1" -v n2="$2" 'BEGIN {printf "%s " "$3" " %s\n", n1, n2}'
}

# args:
# input - $1
has_worker_app_project() {
	local build_dir=$1
	# Look for any folder that contains "WorkerApp" in its name
	local worker_folder=$(find "$build_dir" -maxdepth 1 -type d -name "*WorkerApp*" | head -1)
	if [[ -n "$worker_folder" ]] && [[ -f "$worker_folder/$(basename "$worker_folder").csproj" ]]; then
		echo "yes"
	else
		echo "no"
	fi
}

# args:
# input - $1
should_add_worker_dyno() {
	local build_dir=$1
	local has_worker_app=$(has_worker_app_project "$build_dir")
	
	if [[ "$has_worker_app" == "yes" ]]; then
		echo "yes"
	else
		echo "no"
	fi
}

# args:
# input - $1
get_worker_assembly_name() {
	local build_dir=$1
	local worker_assembly=""
	
	# Look for any folder that contains "WorkerApp" in its name
	local worker_folder=$(find "$build_dir" -maxdepth 1 -type d -name "*WorkerApp*" | head -1)
	if [[ -n "$worker_folder" ]] && [[ -f "$worker_folder/$(basename "$worker_folder").csproj" ]]; then
		worker_assembly=$(basename "$worker_folder")
	fi
	
	echo "$worker_assembly"
}

# args:
# input - $1
is_worker_app_project() {
	local project_path=$1
	local project_name=$(basename "$project_path" .csproj)
	
	# Check if the project name contains "WorkerApp"
	if [[ "$project_name" == *"WorkerApp"* ]]; then
		echo "yes"
	else
		echo "no"
	fi
}

# Make the dotnet CLI first-run experience safe inside the Heroku build container.
# The SDK runs NuGet's migration step on the first CLI invocation for a given SDK
# version, and that step takes a named mutex ("NuGet-Migrations"). Named mutexes are
# backed by files under /tmp/.dotnet, which this container cannot always create, so the
# command dies with:
#   System.IO.IOException: The system cannot open the device or file specified. : 'NuGet-Migrations'
# NuGet skips the mutex completely once the migration marker file exists, so create it
# up front, make the mutex directories usable, and drop the first-run sentinels for the
# installed SDK.
# args:
# input - $1
harden_dotnet_first_run() {
	local build_dir="${1:-}"
	local migrations_dir sentinel_dir sdk_version

	export DOTNET_NOLOGO="${DOTNET_NOLOGO:-1}"
	export DOTNET_GENERATE_ASPNET_CERTIFICATE="${DOTNET_GENERATE_ASPNET_CERTIFICATE:-false}"
	export DOTNET_ADD_GLOBAL_TOOLS_TO_PATH="${DOTNET_ADD_GLOBAL_TOOLS_TO_PATH:-false}"
	export DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK="${DOTNET_SKIP_WORKLOAD_INTEGRITY_CHECK:-1}"

	# NuGet.Common.Migrations.MigrationRunner only creates the mutex when this file is missing
	migrations_dir="${XDG_DATA_HOME:-$HOME/.local/share}/NuGet/Migrations"
	mkdir -p "$migrations_dir" 2>/dev/null || true
	[[ -f "$migrations_dir/1" ]] || ( : > "$migrations_dir/1" ) 2>/dev/null || true

	# Backing store for every named mutex the build may use (NuGet, Roslyn build server)
	mkdir -p /tmp/.dotnet/shm /tmp/.dotnet/lockfiles 2>/dev/null || true
	chmod -R 777 /tmp/.dotnet 2>/dev/null || true

	# Sentinels are version stamped, so a new SDK patch re-runs the first-run path
	sentinel_dir="${DOTNET_CLI_HOME:-$HOME}/.dotnet"
	mkdir -p "$sentinel_dir" 2>/dev/null || true
	if [[ -d "$build_dir/.dotnet/sdk" ]]; then
		for sdk_version in $(ls "$build_dir/.dotnet/sdk" 2>/dev/null); do
			touch "$sentinel_dir/${sdk_version}.dotnetFirstUseSentinel" 2>/dev/null || true
			touch "$sentinel_dir/${sdk_version}.aspNetCertificateSentinel" 2>/dev/null || true
			touch "$sentinel_dir/${sdk_version}.toolpath.sentinel" 2>/dev/null || true
		done
	fi
}
