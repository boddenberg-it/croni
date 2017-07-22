#!/bin/bash
new_crontab=/tmp/croni

function log() {
	echo "$1" >> "$base/../croni.log"
}

function deploy_job() {
	echo "$base/  $1/  $2"
	croni="$(cat "$base/$1/$2" | grep "croni\=" | cut -d "\"" -f2)"
	echo "$croni $submodule_base/croni.sh run $1 $2" >> $new_crontab
	job_logs="$base/../logs/$1/$2"
	job_logs="${job_logs//.sh/}"
	mkdir -p "$job_logs"
}

function deploy() {
	echo "# $base #"

	rm "$new_crontab" || true
	echo "0 5,17 * * * $submodule_base/croni.sh deploy $1 $2" >> $new_crontab

	projects="$(ls "$base")"
	for project in $projects; do
		jobs="$(ls "$base/$project")"
		for job in $jobs; do
			deploy_job "$project" "$job"
		done
	done

	# TODO:
	#replace crontab file
}

################
function run() {
	project="$1"
	job="$2"

	job_dir="$base/../logs/$project/$job"
	job_dir="${job_dir//.sh/}"

	if [ ! -f "$job_dir/latest_build_number" ]; then
		echo "-1" > "$job_dir/latest_build_number"
	fi

	current_bn="$(cat $job_dir/latest_build_number)"
	next_bn="$((current_bn+1))"
	echo "$next_bn" > "$job_dir/latest_build_number"

	date="$(date +%y-%m-%w_%H:%m:%S)"
	log "Starting build: $project/$job number: $next_bn"
	job_log="$job_dir/${job}_${next_bn}_${date}"

	start=$(date +%s)
	/bin/bash -ex "$base/$project/$job" 2&>1 > "$job_log"
	exit_code=$?
	stop=$(date +%s)
	duration=$((stop-start))

	echo "" >> $job_log
	echo "[INFO] Build took: $duration s" >> "$job_log"

	if [ "$exit_code" -gt 0 ]; then
		log "Failure  build: $1/$2 number: $next_bn duration: $duration"
		echo "[INFO] Failure" >> "$job_log"
		mv "$job_log" "${job_log}_failed_${duration}.log"
	else
		log "Success  build: $1/$2 number: $next_bn duration: $duration"
		echo "[INFO] Success" >> "$job_log"
		mv "$job_log" "${job_log}_success_${duration}.log"
	fi
}

function update() {

	exits=0

	cd $base || exits=$((exits+$?))
	git fetch origin; exits=$((exits+$?))
	git rebase origin/master; exits=$((exits+$?))

	deploy; exits=$((exits+$?))

	if [ "$exits" -gt 0 ]; then
		log "Updating jobs from git repository failed: $exits"
	else
		log "Updating jobs from git repository succeeded"
	fi
}

submodule_base="$(dirname "$(readlink -f $0)")"
base="${submodule_base//.croni/croni}"
export base submodule_base
$@
