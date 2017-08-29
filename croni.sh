#!/bin/sh
# doc: https://git.boddenberg.it/croni
# author: André Boddenberg
# license: GPL 3.0

init () {
	# creating necessary directories & symlinks
	mkdir -p "$runtime"
	if [ ! -d "$base/logs" ]; then
		ln -s $webroot/logs/ $base/logs
	fi

	log "initialising croni..."

	if [ ! -f "croni.sh" ]; then
		ln -s "$croni" "$base/croni.sh"
	fi

	# avoid vanishing last update information if already initialised
	if [ ! -f "$runtime/last_update" ]; then
		echo "n/a" > $runtime/last_update
	fi
	if [ ! -f "$runtime/croni_last_update" ]; then
		echo "n/a" > $runtime/croni_last_update
	fi

	# creating config file in home directory
	if [ ! -f "$HOME/.croni" ]; then
		cat <<-EOT > "$HOME/.croni"
			# croni instance configuration file
			# https://git.boddenberg.it/croni

			croni_run=true
			croni_sendmail=false
		EOT
	fi

	update_croni_table
	create_index_html

	if [ ! -f $base/index.html ]; then
		ln -s $webroot/index.html $base/index.html
	fi

	deploy
	start_server
}

deploy () {

	update_navbar
	old_crontab="$base/.cronitab"
	new_crontab="$base/.cronitab_new"

	# create job unrelated cronjobs to update and ensure HTTPS server is listening
	echo "$update_expression $croni update" > $new_crontab
	echo "@reboot $croni start_server" >> $new_crontab
	if [ "$croni_server_check_expression" != "" ]; then
		echo "$croni_server_check_expression $croni start_server" >> $new_crontab
	fi

	# create project and job pages
	projects="$(ls "$base/jobs")"
	for project in $projects; do

		create_project_page "$project"
		jobs="$(ls "$base/jobs/$project")"

		for job_file in $jobs; do
			job="$(echo $job_file | cut -d '.' -f1)"
			create_job_page "$project" "$job"
			deploy_job "$project" "$job" "$job_file"
		done
		update_project_table "$project"
	done

	# deploy new crontab if changes have been introduced
	diff "$old_crontab" "$new_crontab"
	if [ $? -gt 0 ]; then
		cp "$new_crontab" "$old_crontab"
		crontab "$old_crontab"
		/etc/init.d/cron reload
		log "deploy call: changes applied"
	else
		log "deploy call: nothing changed."
	fi
	rm "$new_crontab"
}

deploy_job () {
	project="$1"
	job="$2"
	job_file="$3"

	# ensure logs folder exists
	mkdir -p "$base/logs/$project/$job"

	if [ ! -f "$base/logs/$project/${job}.last_build" ]; then
		echo "NOT RUN YET" > "$base/logs/$project/${job}.last_build"
	fi

	croni_expression="$(job_value "$project" "$job_file" "croni")"
	if [ "$croni" = "" ]; then
		log "[ERROR] Cannot deploy, no cron_expression declared in $base/jobs/$project/$job_file"
	else
		echo "$croni_expression $croni run $project $job_file" >> $new_crontab
	fi
}

# updating jobs repository
update () {
	cd $base || exit
	old_head="$(revision)"
	branch="$(git branch | cut -d ' ' -f2)"

	git fetch origin
	git rebase "origin/$branch"

	if [ $? -gt 0 ]; then
		set -e
		log "update call: rebase failed, stashing possible local changes before retrying"
		git stash
		git rebase "origin/$branch"
		set +e
	fi

	new_head="$(revision)"
	date="$(date +%H:%m:%S\ %d.%m.%y)"
	echo "$date" > "$runtime/last_update"

	if [ "$new_head" != "$old_head" ]; then
		log "update call: changes found -> deploy()"
		deploy
	fi

	update_croni_table
}

# updating croni submodule
upgrade () {
	cd $base || exit
	echo "$(date +%H:%m:%S\ %d.%m.%y)" > "$runtime/croni_last_update"

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
		log "Upgrade: updated changes, old: $old_head, new: $new_head"
		deploy
	else
		log "Upgrade: no changes, currrent: $new_head"
	fi

	update_croni_table
}

# allow user to test jobs on disabled instance
test () {
	croni_run=true
	run $@
}

run () {

	if [ "$croni_run" = "false" ]; then
		echo
		echo "[ERROR] croni is currently disabled... try 'test' instead."
		exit 0;
	fi

	project="$1"
	job_file="$2"
	job="$(echo $job_file | cut -d '.' -f1)"
	job_dir="$base/logs/$project/$job"

	if [ ! -f "$base/jobs/$project/$job_file" ]; then
		echo "[ERROR] Job is not existing"
		exit 1
	fi

	# obtain build number
	if [ ! -f "$job_dir/latest_build_number" ]; then
		echo "-1" > "$job_dir/latest_build_number"
	fi
	# increase build number
	current_bn="$(cat $job_dir/latest_build_number)"
	next_bn="$((current_bn+1))"
	echo "$next_bn" > "$job_dir/latest_build_number"

	# obtain log file
	job_log="$job_dir/${job}_${next_bn}.log"

	# create workspace
	mkdir -p "$job_dir/workspaces/${next_bn}/"
	cd "$job_dir/workspaces/${next_bn}/" || exit

	# obtain timeout from job script
	timeout="$(job_value "$project" "$job_file" "timeout")"
	script="$base/jobs/$project/$job_file"

	# triggering job
	date="$(date +%y-%m-%d_%H:%m:%S)"
	echo "<pre>[INFO] Build $project/$job_file #${next_bn} triggered at $date" >> "$job_log"
	start=$(date +%s)
	# exit code is 124 in case of a timeout
	timeout "$timeout" "$script" >> "$job_log" 2>&1
	exit_code=$?
	stop=$(date +%s)
	duration=$((stop-start))
	echo "" >> "$job_log"
	echo "[INFO] Build took: $duration s" >> "$job_log"

	# exit code evaluation
	result=""
	if [ "$exit_code" -gt 0 ]; then
		if [ "$exit_code" -eq 124 ]; then
			result="TIMEOUT"
		else
			# failure let's try to parse the error from script
			reason="unknown"
			parsed_reason="$(job_value "$project" "$job_file" "reason_${exit_code}")"
			if [ "$parsed_reason" != "" ]; then
				reason="$parsed_reason"
				echo "[INFO] Noted failure reason: $reason" >> "$job_log"
				result="KNOWN FAIL"
				# if croni_sendmail; sendmail
			else
				result="FAIL"
			fi
		fi
	else
		result="OK"
	fi

	echo "[INFO] Build result: $result </pre>" >> "$job_log"
	log "Build $project/$job # $next_bn took ${duration}s, result: $result $reason"

	# rotate logs and workspaces
	job_cleanup "$project" "$job" "$next_bn"

	# updating/cleanup front end
	echo "$result" > "$base/logs/$project/${job}.last_build"
	add_job_to_timelines "$project" "$job" "$result" "$next_bn" "$duration"
	echo "project passed to timelines: $project $job"
	update_timelines "$project" "$job"
	update_project_table "$project"
}

job_cleanup () {
	project="$1"
	job="$2"

	# clean up old log(s)
	number="$3"
	number="$((number - default_build_rotation))"
	while [ -f "$base/logs/$project/$job/${job}_${number}.log" ]; do
		rm "$base/logs/$project/$job/${job}_${number}.log"
		number=$((number-1))
	done

	# clean up old workspace(s)
	number="$3"
	number="$((number - default_workspace_rotation))"
	while [ -d "$base/logs/$project/$job/workspaces/$number" ]; do
		rm -rf "$base/logs/$project/$job/workspaces/$number"
		number=$((number-1))
	done
}

start_server () {
	is_online="$(ps a | grep "python -m SimpleHTTPServer $croni_port" | wc -l)"
	if [ "$is_online" = "1" ]; then
		cd "$webroot"
		python -m SimpleHTTPServer "$croni_port" > "$base/logs/server.log" 2>&1 &
	fi
}

### page creation ###
create_page () {
	project="$1"
	content="$2"
	job="$3"

	# obtain page name
	page=""
	if [ "$#" -gt 2 ]; then
		page="${project}-${job}"
	else
		page="$project"
	fi

	dest="$webroot/${page}.html"
	. "$templates"

	# create page
	echo "$page_start" > "$dest"
	echo "$content" >> "$dest"
	echo "$page_end" >> "$dest"
}

create_index_html () {

	create_page "croni" "$landing_page"
	mv "$webroot/croni.html" "$webroot/index.html"
}

create_project_page () {
	project="$1"
	. "$templates"
	create_page "$project" "$project_page"
}

create_job_page () {
	project="$1"
	job="$2"
	. "$templates"
	create_page "$project" "$job_page" "$job"
}


update_navbar () {
	rm "$base/logs/.runtime/navbar" || true

	for p in $(ls "$base/jobs"); do
		echo "<li><a class="croni_navbar" href=\"$p.html\">$p</a></li>" >> "$runtime/navbar"
	done
}

update_croni_table () {

	revision="$(revision)"
	croni_revision="$(revision croni)"

	cd "$base" || exit
	remote_url="$(git config --get remote.origin.url)"
	repo="<a href=\"$remote_url\"croni_>$remote_url</a>"
	branch="$(git branch | head -1)"
	last_update="$(cat $runtime/last_update)"

	cd "$submodule_base" || exit
	croni_remote_url="$(git config --get remote.origin.url)"
	croni_repo="<a href=\"$croni_remote_url\">$croni_remote_url</a>"
	croni_branch="$(git branch | head -1)"
	croni_last_update="$(cat ${runtime}/croni_last_update)"

	. "$templates"
	echo "$croni_table_template" > "${runtime}/croni_table"
}

# called everytime a job finishes within this project
update_project_table () {
	project="$1"
	jobs="$(ls "$base/jobs/$project")"
	rm "$base/logs/.runtime/${project}_project" || true

	for job in $jobs; do
		job="$(echo $job | cut -d '.' -f1)"
		state="$(cat "$base/logs/$project/${job}.last_build")"
		page="${project}-${job}"
		name="$job"
		. "$templates"
		echo "$script_item_template" >> "$base/logs/.runtime/${project}_project"
	done

	. "$templates"
	write_to_file "$base/logs/.runtime/${project}_project" "$project_table_header"
}

update_timeline () {
	timeline_name="$1"
	echo "update_timeline $1_timeline"
	tl="$base/logs/.runtime/${timeline_name}_timeline"
	cat "$tl" | head -"$default_build_rotation" > "${tl}.tmp"
	mv "${tl}.tmp" "$tl"
}

update_timelines () {
	update_timeline "$1-$2"
	update_timeline "$1"
	update_timeline "croni"
}

add_job_to_timelines () {
	 project="$1"
	 job="$2"
	 result="$3"
	 build_number="$4"
	 duration="$5"

	 date="$(date +%H:%m:%S\ -\ %d.%m.%y)"
	 item="$project - $job"
	 item_path="${project}-${job}.html"
	 # following paths are relative to webroot
	 log_path="logs/$project/$job/${job}_${build_number}.log"
	 workspace_path="logs/$project/$job/workspaces/${build_number}/"

	 . "$templates"
	 write_to_file "$runtime/croni_timeline" "$timeline_item_template"
	 # only job name for project and job page
	 item="$job"
	 . "$templates"
	 write_to_file "$runtime/${project}_timeline" "$timeline_item_template"
	 write_to_file "$runtime/${project}-${job}_timeline" "$timeline_item_template"
}

# HELPERS
revision () {
	cd "$base/$1" || exit
	echo "$(git rev-parse --short HEAD)"
}

# parsing job value from job file or using default value of ~/.croni
job_value () {
	job_var="$(cat "$base/jobs/$1/$2" | grep "$3\=" | cut -d "\"" -f2)"
	if [ "$job_var" = "" ]; then
		default="default_$3"
		default="echo \$$default"
		default=$(eval $default)

		if [ "$default" != "" ]; then
			echo "$default"
		fi
	else
		echo "$job_var"
	fi
}

write_to_file () {
	file="$1"
	msg="$2"

	if [ ! -f "$file" ]; then
		echo "" > "$file"
	fi
	# append at the beginning
	sed -i "1i${msg}" "$file"
}

log () {
	write_to_file "$base/logs/croni.log" "\<pre\>[$(date +%H:%m:%S\ %d.%m.%y)] $1\</pre\>"
}

# actual entry point
submodule_base="$(dirname "$(readlink -f $0)")"
base="$(dirname $submodule_base)"

croni="$submodule_base/croni.sh"
webroot="$submodule_base/webroot"
templates="$webroot/templates.html"
runtime="$webroot/logs/.runtime/"

export base submodule_base webroot templates runtime

. "$base/croni.cfg"
. "$HOME/.croni"
$@
