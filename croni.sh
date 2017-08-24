#!/bin/bash

# helper
function write_to_file() {
	file="$1"
	msg="$2"

	if [ ! -f "$file" ]; then
		echo "$msg" > "$file"
	else
		# append at the beginning
		sed -i "1i${msg}" "$file"
	fi
}
function log() {
	file="$base/logs/croni.log"
	write_to_file "$file" "\<pre\>[$(date +%H:%m:%S\ %d.%m.%y)] $1\</pre\>"
}


### CLI commands ###
function start_server() {
	is_online="$(ps a | grep "python -m SimpleHTTPServer $croni_port" | head -1 | cut -d ' ' -f2 | wc -l)"
	if [ "$is_online" = "1" ]; then
		cd "$submodule_base/webroot"
		python -m SimpleHTTPServer "$croni_port" > "$base/logs/server.log" 2>&1 &
	fi
}

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


# called everytime a job finishes within this project
update_project_table() {
	project="$1"
	jobs="$(ls "$base/croni_jobs/$project")"
	# clean up
	rm "$base/logs/.runtime/${project}_project" || true

	for job in $jobs; do
		job_no_ext="${job//.sh/}"
		state="$(cat "$base/logs/$1/${job_no_ext}.last_build")"
		job=${job//.sh/}
		page="${project}-${job}"
		name="$job"
		source "$templates"
		echo "$script_item_template" >> "$base/logs/.runtime/${project}_project"
	done
	source "$templates"
	write_to_file "$base/logs/.runtime/${project}_project" "$project_table_header"
}

function deploy() {

	update_navbar

	old_crontab="$base/.cronitab"
	new_crontab="$base/.cronitab_new"

	echo "$update_expression $submodule_base/croni.sh update" > $new_crontab
	echo "@reboot $submodule_base/croni.sh start-server" >> $new_crontab

	if [ "$croni_update_expression" != "" ]; then
		echo "$croni_update_expression $submodule_base/croni.sh upgrade" >> $new_crontab
	fi

	if [ "$croni_server_check_expression" != "" ]; then
		echo "$croni_server_check_expression $submodule_base/croni.sh start-server" >> $new_crontab
	fi

	echo "" >> $new_crontab
	projects="$(ls "$base/croni_jobs")"
	for project in $projects; do

		create_project_page $project
		jobs="$(ls "$base/croni_jobs/$project")"

		for job in $jobs; do
			create_job_page "$project" "$job"
			deploy_job "$project" "$job"
		done

		update_project_table "$project"
	done

	# deploy new crontab if changes have been introduced
	diff="$(diff "$old_crontab" "$new_crontab")"
	if [ $? -gt 0 ]; then
		cp "$new_crontab" "$old_crontab"
		crontab "$old_crontab"
		/etc/init.d/cron reload
		log "deploy call: job/script changes have been fetched... successful update!"
	else
		log "deploy call: Nothing changed, nothing added."
	fi
	rm "$new_crontab"
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
		script="$3"
		script_no_ext="${script//.sh/}"
		page="$1-${script_no_ext}"
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
	script_no_ext="${script//.sh/}"
	source "$templates"
	create_page "$project" "$job_page" "$script"
}

# TODO: add cleanup after each job run checking job stuff, projects stuff, croni_timeline (x2). That's it. simply pipe it real good :D

cleanup_timeline() {
	timeline_name="$1"
	lines="$2"
	tl="$base/logs/.runtime/${timeline_name}_timeline"
	cat "$tl" | head -$lines > "${tl}.tmp"
	mv "${tl}.tmp" "$tl"
}

cleanup_timelines() {
	cleanup_timeline "$2" "$default_build_rotation"
	cleanup_timeline "$1-$2" "$default_build_rotation"
	cleanup_timeline "croni" "$((default_build_rotation*2))"
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

	# ensure logs folder exists
	job_logs="$base/logs/$1/$2"
	job_logs="${job_logs//.sh/}"
	mkdir -p "$job_logs"

	# create .last_build file
	if [ ! -f "${job_logs}.last_build" ]; then
		echo "NOT RUN YET" > "${job_logs}.last_build"
	fi

	croni="$(job_value "$1" "$2" "croni")"
	if [ "$croni" = "" ]; then
		log "[ERROR] No cron_expression declared in $base/jobs/$1/$2"
		echo "# $croni $submodule_base/croni.sh run $1 $2 -- FAILED" >> $new_crontab
	else
		echo "$croni $submodule_base/croni.sh run $1 $2" >> $new_crontab
	fi
}

# allow user to test jobs on disabled instances
function test() {
	croni_run=true
	run $@
}

function run() {

	if [ "$croni_run" = "false" ]; then
		echo
		echo "[ERROR] croni is currently disabled... try 'test' instead."
		exit 0;
	fi

	project="$1"
	job="$2"

	job_dir="$base/logs/$project/$job"
	job_dir="${job_dir//.sh/}"

	# obtain build number
	if [ ! -f "$job_dir/latest_build_number" ]; then
		echo "-1" > "$job_dir/latest_build_number"
	fi
	current_bn="$(cat $job_dir/latest_build_number)"
	next_bn="$((current_bn+1))"
	echo "$next_bn" > "$job_dir/latest_build_number"

	# obtain log file
	job_log="$job_dir/${job}_${next_bn}.log"
	job_log="${job_log//.sh/}"

	# create workspace
	mkdir -p "$job_dir/workspaces/${next_bn}/"
	cd "$job_dir/workspaces/${next_bn}/" || exit
	# obtain timeout from job script
	timeout="$(job_value "$project" "$job" "timeout")"
	script="$base/croni_jobs/$project/$job"

	# triggering script with timeout trap
	date="$(date +%y-%m-%d_%H:%m:%S)"
	echo "<pre>[INFO] Build $1/$2 #${next_bn} triggered at $date" >> "$job_log"
	start=$(date +%s)
	# FYI: exit code is 124 in case of a timeout
	timeout "$timeout" "$script" >> "$job_log" 2>&1
	exit_code=$?
	stop=$(date +%s)
	duration=$((stop-start))
	echo "" >> "$job_log"
	echo "[INFO] Build took: $duration s" >> "$job_log"

	result=""
	# exit code evaluation
	if [ "$exit_code" -gt 0 ]; then
		if [ "$exit_code" -eq 124 ]; then
			result="TIMEOUT"
		else
			# failure let's try to parse the error from script
			reason="unknown"
			parsed_reason="$(job_value "$project" "$job" "reason_${exit_code}")"
			if [ "$parsed_reason" != "" ]; then
				reason="$parsed_reason"
				echo "[INFO] Noted failure reason: $reason" >> "$job_log"
				result="KNOWN FAIL"
			else
				result="FAIL"
			fi
		fi
	else
		result="OK"
	fi

	echo "[INFO] Build result: $result </pre>" >> "$job_log"
	log "Build $project/$job # $next_bn took ${duration}s, result: $result $reason"

	# updating front end + cleanup
	job_no_ext=${job//.sh/}
	echo "$result" > "$base/logs/$1/${job_no_ext}.last_build"
	add_job_to_timelines "$project" "$job" "$result" "$next_bn" "$duration"
	cleanup_timelines "$project" "$job"
	update_project_table "$project"
	job_cleanup "$project" "$job" "$next_bn"
}

add_job_to_timelines() {
	 project="$1"
	 job="$2"
	 result="$3"
	 build_number="$4"
	 duration="$5"

	 job="${job//.sh/}"
	 date="$(date +%H:%m:%S\ -\ %d.%m.%y)"
	 item="$project - $job"
	 item_path="${project}-${job}.html"
	 log_path="logs/$project/$job/${job}_${build_number}.log"
	 log_path="${log_path//.sh/}"
	 workspace_path="/logs/$project/$job/workspaces/${build_number}/"

	 source $templates
	 write_to_file "$base/logs/.runtime/croni_timeline" "$timeline_item_template"
	 item="$job"
	 source $templates
	 write_to_file "$base/logs/.runtime/${project}_timeline" "$timeline_item_template"
	 write_to_file "$base/logs/.runtime/${project}-${job}_timeline" "$timeline_item_template"
}

# UPDATE & UPGRADE
function revision() {
	cd "$base/$1" || exit
	echo "$(git rev-parse HEAD)"
}

job_cleanup() {
	project="$1"
	job="$2"

	number="$3"
	number="$((number - default_build_rotation))"
	while [ -f "$base/logs/$project/$job/${job}_${number}.log" ]; do
		rm "$base/logs/$project/$job/${job}_${number}.log"
		number=$((number-1))
	done

	number="$3"
	number="$((number - default_workspace_rotation))"
	while [ -d "$base/logs/$project/$job/workspaces/$number" ]; do
		rm -rf "$base/logs/$project/$job/workspaces/$number"
		number=$((number-1))
	done
}

# update static navbar and croni-table
update_navbar() {
	# update navbar
	rm "$base/logs/.runtime/navbar" || true
	for p in $(ls "$base/croni_jobs"); do
		echo "<li><a class="croni_navbar" href=\"$p.html\">$p</a></li>" >> "$base/logs/.runtime/navbar"
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
templates="$submodule_base/webroot/templates.html"

export base submodule_base templates

if [ ! "$1" = "init" ]; then
	source "$base/croni.cfg"
	source "$HOME/.croni"
fi

$@
