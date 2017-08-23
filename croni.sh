#!/bin/bash

function log() {

	file="$base/logs/croni.log"

	if [ ! -f "$file" ]; then
		echo "<pre>$1 [$(date)]</pre>" > "$file"
	else
		# append at the beginning
		sed -i "1i<pre>$1 [$(date)]</pre>" "$file"
	fi
}

### CLI commands ###
function init() {

	mkdir -p $submodule_base/webroot/logs/.runtime
	if [ ! -d "$base/logs" ]; then
		ln -s $submodule_base/webroot/logs/ $base/logs
	fi

	log "initialising croni..."

	if [ ! -f "$HOME/.croni" ]; then
		cat <<-EOT > "$HOME/.croni"
			# croni instance configuration file
			# https://git.boddenberg.it/croni

			croni_run=true
			croni_send_mail=false
		EOT
	fi

	if [ ! -f "croni.sh" ]; then
		ln -s croni/croni.sh $base/croni.sh
	fi

	# set n/a values for updates
	echo "n/a" > $submodule_base/webroot/logs/.runtime/last_update
	echo "n/a" > $submodule_base/webroot/logs/.runtime/croni_last_update

	update_croni_table
	create_croni_page

  if [ ! -f "$base/index.html" ]; then
	  ln -s $submodule_base/webroot/index.html $base/index.html
	fi
}

function deploy() {

	update_navbar

	old_crontab="$base/.cronitab"
	new_crontab="$base/.cronitab_new"

	echo "$update_expression $submodule_base/croni.sh update" > $new_crontab

	if [ "$croni_update_expression" != "" ]; then
		echo "$croni_update_expression $submodule_base/croni.sh upgrade" >> $new_crontab
	fi

	projects="$(ls "$base/croni_jobs")"
	for project in $projects; do

		create_project_page $project
		jobs="$(ls "$base/croni_jobs/$project")"

		for job in $jobs; do
			create_job_page "$project" "$job"
			deploy_job "$project" "$job"
		done

	done

	# deploy new crontab if changes have been introduced
	diff="$(diff "$old_crontab" "$new_crontab")"
	if [ $? -gt 0 ]; then
		log "Job/script changes have been fetched... successful update!"
		cp "$new_crontab" "$old_crontab"
		crontab "$old_crontab"
		/etc/init.d/cron reload
		rm "$new_crontab" # clean up
	else
		log "deploy call: Nothing changed, nothing added."
	fi
}


# updating job repository
function update() {
	cd $base || exit
	echo "$(date +%H:%m:%S\ %d.%m.%y)" > $submodule_base/webroot/logs/.runtime/last_update
	old_head="$(revision)"

	git fetch origin
	git rebase origin/master

	if [ $? -gt 0 ]; then
		log "update call: rebase failed, stashing possible local changes before retrying"
		git stash
		git rebase origin/master
	fi

	new_head="$(revision)"

	date="$(date +%H:%m:%S\ %d.%m.%y)"
	# update front-end
	remote_url="$(git config --get remote.origin.url)"
	echo "<a href=\"$remote_url\">$remote_url</a>" > $submodule_base/webroot/logs/.runtime/repository
	echo "$(git branch)" > $submodule_base/webroot/logs/.runtime/branch
	echo "${new_head:0:7}" > $submodule_base/webroot/logs/.runtime/revision
	echo "$(date +%H:%m:%S\ %d.%m.%y)" > $submodule_base/webroot/logs/.runtime/last_update
	echo "$update_expression" > $submodule_base/webroot/logs/.runtime/update_interval

	if [ "$new_head" != "$old_head" ]; then
		log "update call: changes found -> deploying jobs"
		deploy
	fi
	update_croni_table
}

# updating croni submodule
function upgrade() {
	cd $base || exit
	echo "$(date +%H:%m:%S\ %d.%m.%y)" > $submodule_base/webroot/logs/.runtime/croni_last_update

	old_head="$(revision croni)"

	git submodule update --remote
	if [ $? -gt 0 ]; then
		cd $submodule_base || exit
		git stash
		git reset HEAD --hard
		cd $base || exit
		git submodule update --remote
	fi

	new_head="$(revision croni)"

	if [ "$new_head" != "$old_head" ]; then
		log "Upgrade: croni has been updated old: $old_head new: $new_head"
		deploy
	else
		log "Upgrade: nothing changed. currrent HEAD: $new_head"
	fi

	update_croni_table
}

### page creation ###
function create_page() {

	# obtain page name
	page=""
	if [ "$#" -gt 2 ]; then
		page="$1-$3"
	else
		page="$1"
	fi

	dest="$submodule_base/webroot/${page}.html"
	source "$templates"

	# create page
	echo "$page_start" > "$dest"
	echo "$2" >> "$dest"
	echo "$page_end" >> "$dest"
}

function create_croni_page() {
	source "$templates"
	create_page "croni" "$landing_page"
	mv "$submodule_base/webroot/croni.html" "$submodule_base/webroot/index.html"
}

function create_project_page() {
	project="$1"
	page="$1"
	source "$templates"
	create_page "$project" "$project_page"
}

function create_job_page() {
	project="$1"
	script="$2"
	page="$1-$2"
	source "$templates"
	create_page "$project" "$job_page" "$script"
}


# parsing job value from job file
function job_value() {
	job_var="$(cat "$base/croni_jobs/$1/$2" | grep "$3\=" | cut -d "\"" -f2)"
	if [ "$job_var" = "" ]; then
		default="default_$3"
		default="echo \$$default"
		default=$(eval $default)

		if [ "$default" != "" ]; then
			echo "$default"
		fi
		# TODO: else logging
	else
		echo "$job_var"
	fi
}

function deploy_job() {
	croni="$(job_value "$1" "$2" "croni")"
	if [ "$croni" = "" ]; then
		log "[ERROR] No cron_expression declared in $base/jobs/$1/$2"
		echo "# $croni $submodule_base/croni.sh run $1 $2 -- FAILED" >> $new_crontab
	else
		echo "$croni $submodule_base/croni.sh run $1 $2" >> $new_crontab
	fi

	# ensure logs folder exists
	job_logs="$base/logs/$1/$2"
	job_logs="${job_logs//.sh/}"
	mkdir -p "$job_logs"
}

### ###
function run() {
	# ~/.croni config
	if [ ! $croni_run ]; then exit 0; fi

	project="$1"
	job="$2"

	job_dir="$base/logs/$project/$job"
	job_dir="${job_dir//.sh/}"

	### run preparations
	# obtain build number
	if [ ! -f "$job_dir/latest_build_number" ]; then
		echo "-1" > "$job_dir/latest_build_number"
	fi
	current_bn="$(cat $job_dir/latest_build_number)"
	next_bn="$((current_bn+1))"
	echo "$next_bn" > "$job_dir/latest_build_number"
	# obtain log file
	date="$(date +%y-%m-%d_%H:%m:%S)"
	log "Starting build: $project/$job number: $next_bn"
	job_log="$job_dir/${job}_${next_bn}"
	# create workspace
	mkdir -p "$job_dir/workspaces/${next_bn}/"
	cd "$job_dir/workspaces/${next_bn}/" || exit
	# obtain timeout from job script
	timeout="$(job_value "$project" "$job" "timeout")"
	script="$base/croni_jobs/$project/$job"

	# triggering script with timeout trap
	echo "[INFO] Build started at $date" >> "$job_log"
	start=$(date +%s)
	# FYI: exit code is 124 in case of a timeout
	timeout "$timeout" "$script" >> "$job_log" 2>&1
	exit_code=$?
	stop=$(date +%s)
	duration=$((stop-start))
	echo "" >> "$job_log"
	echo "[INFO] Build took: $duration s" >> "$job_log"

	# exit code evaluation
	if [ "$exit_code" -gt 0 ]; then
		# timeout
		if [ "$exit_code" -eq 124 ]; then
			log "Build TIMEOUT: $1/$2 number: $next_bn duration: $duration"
			echo "[INFO] Timeout" >> "$job_log"
			mv "$job_log" "${job_log}_TIMEOUT_${duration}.log"
		else
			# failure let's try to parse the error from script
			reason="unknown"
			parsed_reason="$(job_value "$project" "$job" "reason_${exit_code}")"

			if [ "$parsed_reason" != "" ]; then
				reason="$parsed_reason"
			fi

			log "Build FAIL: $1/$2 number: $next_bn duration: $duration reason: $reason"
			echo "[INFO] Failure, reason_${exit_code}: $reason" >> "$job_log"
			mv "$job_log" "${job_log}_${exit_code}_FAIL.log"
		fi
	else
		# success
		log "Build OK: $1/$2 number: $next_bn duration: $duration"
		echo "[INFO] Success" >> "$job_log"
		mv "$job_log" "${job_log}_OK.log"
	fi

	# add to lists, call :D
}

# UPDATE & UPGRADE
function revision() {
	cd "$base/$1" || exit
	echo "$(git rev-parse HEAD)"
}

# update static navbar and croni-table
update_navbar() {
	# update navbar
	rm "$base/logs/.runtime/navbar" || true
	for p in $(ls "$base/croni_jobs"); do
		echo "<li><a href=\"$p.html\">$p</a></li>" >> "$base/logs/.runtime/navbar"
	done
}

update_croni_table(){

	revision="$(revision)"
	croni_revision="$(revision croni)"

	cd "$base" || exit
	remote_url="$(git config --get remote.origin.url)"
	repo="<a href=\"$remote_url\"croni_>$remote_url</a>"
	branch="$(git branch | head -1)"
	revision="${revision:0:7}"
	last_update="$(cat $submodule_base/webroot/logs/.runtime/last_update)"

	cd "$submodule_base" || exit
	croni_remote_url="$(git config --get remote.origin.url)"
	croni_repo="<a href=\"$croni_remote_url\">$croni_remote_url</a>"
	croni_branch="$(git branch | head -1)"
	croni_revision="${croni_revision:0:7}"
	croni_last_update="$(cat $submodule_base/webroot/logs/.runtime/croni_last_update)"

	source "$templates"
	echo "$croni_table_template" > "$submodule_base/webroot/logs/.runtime/croni_table"
}

# actual entry point
submodule_base="$(dirname "$(readlink -f $0)")"
base="${submodule_base:0:-5}"
templates="$submodule_base/webroot/templates"

export base submodule_base templates

if [ ! "$1" = "init" ]; then
	source "$base/croni.cfg"
	source "$HOME/.croni"
fi

$@
