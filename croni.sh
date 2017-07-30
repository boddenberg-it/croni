#!/bin/bash

function log() {
	echo "[$(date)] $1" >> "$base/croni_logs/croni.log"
}

function init() {
	mkdir -p $base/croni_logs/

	if [ ! -f "index.html" ]; then
		ln -s croni/webroot/index.html index.html
	fi

	if [ ! -f "croni.sh" ]; then
		ln -s croni/croni.sh croni.sh
	fi

	deploy
}

function deploy() {

	mkdir -p $base/croni_logs/

	old_crontab="$HOME/.croni"
	new_crontab="$HOME/.croni_new"

	echo "# croni gererated crontab (https://git.boddenberg.it/croni)" >> $new_crontab
	echo "0 5,17 * * * $submodule_base/croni.sh update" >> $new_crontab
	echo "" >> $new_crontab

	projects="$(ls "$base/croni_jobs")"
	for project in $projects; do
		jobs="$(ls "$base/croni_jobs/$project")"
		for job in $jobs; do
			deploy_job "$project" "$job"
		done
	done

	# deploy new crontab if changes have been introduced
	diff="$(diff "$old_crontab" "$new_crontab")"
	if [ $? -gt 0 ]; then
		log "deploy call: Folloging changing have been applied: $diff [end of changes]"
		cp "$new_crontab" "$old_crontab"
		crontab "$old_crontab"
		/etc/init.d/cron reload
		rm "$new_crontab"
	else
		log "deploy call: Nothing changed, nothing added."
	fi
}

function deploy_job() {

	croni="$(cat "$base/croni_jobs/$1/$2" | grep "croni\=" | cut -d "\"" -f2)"

	if [ "$croni" = "" ]; then
		log "[ERROR] No croni variable declared in $base/croni_jobs/$1/$2"
		echo "# $croni $submodule_base/croni.sh run $1 $2 -- FAILED" >> $new_crontab
	else
		echo "$croni $submodule_base/croni.sh run $1 $2" >> $new_crontab
	fi

	job_logs="$base/croni_logs/$1/$2"
	job_logs="${job_logs//.sh/}"
	mkdir -p "$job_logs"
}

### ###
function run() {
	project="$1"
	job="$2"

	job_dir="$base/croni_logs/$project/$job"
	job_dir="${job_dir//.sh/}"

	if [ ! -f "$job_dir/latest_build_number" ]; then
		echo "-1" > "$job_dir/latest_build_number"
	fi


	current_bn="$(cat $job_dir/latest_build_number)"
	next_bn="$((current_bn+1))"
	echo "$next_bn" > "$job_dir/latest_build_number"

	date="$(date +%y-%m-%w_%H:%m:%S)"
	log "Starting build: $project/$job number: $next_bn"
	job_log="$job_dir/${job}_${next_bn}"

	# create workspace and use it for build
	mkdir -p "$job_dir/workspaces/${next_bn}/"
	cd "$job_dir/workspaces/${next_bn}/" || exit

	echo "[INFO] Build started at $date"
	start=$(date +%s)
	# exit code is 124 in case of a timeout
	timeout 1 "$base/croni_jobs/$project/$job" > "$job_log" 2>&1
	exit_code=$?
	stop=$(date +%s)
	duration=$((stop-start))
	echo ""
	echo "[INFO] Build took: $duration s" >> "$job_log"

	if [ "$exit_code" -gt 0 ]; then
		# timeout
		if [ "$exit_code" -eq 124 ]; then
			log "build timeout: $1/$2 number: $next_bn duration: $duration"
			echo "[INFO] Timeout" >> "$job_log"
			mv "$job_log" "${job_log}_TIMEOUT_${duration}.log"
		# failure
		else
			log "Suild failure: $1/$2 number: $next_bn duration: $duration"
			echo "[INFO] Failure" >> "$job_log"
			mv "$job_log" "${job_log}_FAILED_${duration}.log"
		fi
	# success
	else
		log "Build Success: $1/$2 number: $next_bn duration: $duration"
		echo "[INFO] Success" >> "$job_log"
		mv "$job_log" "${job_log}_SUCCESS_${duration}.log"
	fi
}

# UPDATE & UPGRADE
function revision() {
	cd "$base/$1" || exit
	echo "$(git rev-parse HEAD)"
}

function upgrade() {
	old_head="$(revision croni)"
	cd $base || exit
	git submodule update --remote
	new_head="$(revision croni)"

	if [ "$old_head" != "$new_head" ]; then
		log "Upgrade: croni has been updated old: $old_head new: $new_head"
	else
		log "Upgrade: nothing changed. currrent HEAD: $new_head"
	fi
}

function update() {
	cd $base || exit

	old_head="$(revision)"

	git fetch origin
	git rebase origin/master
	if [ $? -gt 0 ]; then
		log "update call: rebase failed, stashing possible local changes before retrying"
		git stash
		git rebase origin/master
	fi

	new_head="$(revision)"

	if [ "$new_head" != "$old_head" ]; then
		deploy
	fi
}

submodule_base="$(dirname "$(readlink -f $0)")"
base="${submodule_base:0:-5}"
export base submodule_base
$@
