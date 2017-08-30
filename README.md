## Why?

Croni shall help persons and small teams, who are having the need for a CI server, which at least runs daily/hourly. But don't want to setup and maintain a fully blown CI setup like Jenkins, Travis CI, Bamboo, et cetera.
<br>

## What functionalities does croni provide?

Basically, croni adds a front end to cron for better overview and forces one to put each cronjob in a repository.

List of functionalities/requirements:

* separate workspaces for each build
* sendmail for failed builds
* declaring global/job-specific timeout, recipients and failure message depending on exit code
<br>

* timeline, log and workspace rotation of jobs (gc)
* everything lives in repo to share easily within teams
* provide update automation for jobs repository
* provide manual croni update
<br>

* expose build information on local HTTP server (static web pages)
* show console log for each job run in pop up window
* show croni.log in pop up window
* expose job workspaces

Dependencies:

* shell (timeout command must be available)
* python < 3 (for HTTP server only)
<br>

## Give it a try!

First, <b>back up</b> your crontab it will replaced.

```
git clone https://github.com/boddenberg-it/croni-test
cd croni-test
./init.sh
```

Now, you should see your croni instance on [http://localhost:8080](http://localhost:8080).

![croni front end after init.sh call](https://boddenberg.it/github_images/croni_welcome.png")

The first shown repo in the first table is the one you just cloned, which holds the croni.cfg file
```
# CRONI CONFIG FILE
# https://git.boddenberg.it/croni

croni_update_expression="0 5,17 * * *"
croni_port="8080"
croni_server_check_expression="0 * * * *"
croni_workspace_rotation="14"
croni_build_rotation="28"

# Note: all default_xyz parameters can be overridden by each job/script.
default_croni_timeout="1800"
default_croni_mail_recipients="croni@boddenberg.it"

# default reasons, might be handy
default_croni_reason_87="This is the global (croni.cfg) reason message for exit code 87"
```

as well as all init.sh and the jobs folder.
```
.
├── croni  # git submodule
├── croni.cfg
├── init.sh
├── jobs
│   └── hello_project
│       └── hello_world.sh
└── README.md
```


A job can be any executable file, which declares following parameters in code or comment.
```
#!/bin/sh
croni="0 * * * *"

echo
echo "Hello world!"
mkdir hello
touch hello/world
```

Here is an example with all available job parameters.

```
#!/bin/sh

croni="0 * * * *"

do_magic
```

Additionally, you can create a 'scripts' or any other folder next to jobs and call them as follows
```
#!/bin/sh
croni="0 * * * * "

$base/scripts/example_script.sh "foo" "bar"
```

> The 'initialised' branch holds the test suite. It should give a good overview.
<br>

## Okay, how do I keep this example?

You can simply fork this repository on github or create an empty repository on your own git server. Then you must do steps in "Give it a try!" section and change the remote-url to the one of your create repository and push to your empty repository.

```
git remote set-url origin $URL
git push -u origin master
```
<br>

## How to maintain croni?

Croni automatically updates the jobs repository as long as croni_run is "true".
> Any local changes will be stashed in order to fulfill the update - nothing is lost!

Furthermore, you can use following commands to maintain croni:
```
# deploys local $base/jobs directory
./croni.sh deploy

# fetches changes of jobs respository
./croni.sh update

# fetches changes of croni submodule
./croni.sh upgrade

# ensures server is running if croni_port is declared
./croni.sh start_server

./croni.sh run $project $jobfile

# runs although croni_run is "false" in ~/.croni
./croni.sh test $project $jobfile
```

An alias in ~/.bashrc à la:
```
alias croni="[PATH_JOBS_REPO]/croni.sh $@"
```
might be useful to execute jobs from any directory.
<br>

## What's next?

Basically, it's a hacky prototype. It would be interesting to (re)write croni properly in python to build a basis to go towards a "mature" CI server,
but this depends on the feedback. Personally, it's a handy cronjob presenter and handler.
