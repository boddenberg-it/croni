## Why?

Croni shall help persons and small teams, who are having the need for a CI server, which at least runs daily/hourly. But don't want to setup and maintain a fully blown CI setup like Jenkins, Bamboo, et cetera.
<br>

## What functionalities does croni provide?

Basically, croni adds a bootstrap powered front end to cron for better overview and forces one to put each cronjob in a repository, which makes it easy to share, keep track of changes and deploy croni in seconds.

The croni front end does not provide any interaction like triggering a build or the like. Furthermore, it only provides information about finished builds, i.e. no informaton about running jobs.

<u>List of functionalities/requirements:</u>

* separate workspaces for each build
* declaring global/job-specific timeout, recipients and failure message depending on exit code
* log and workspace rotation of jobs (gc)
* provide update automation for jobs repository
* provide manual croni submodule update
* 'sendmail' for failed builds
* expose build information on local HTTP server (static web pages)
* show console log for each job run in pop up window
* show croni.log in pop up window
* expose job workspaces

<u>Dependencies:</u>

* <b>cron</b>
* <b>shell</b>
* python < 3
* commands:
  * <b>timeout</b>
  * sendmail

> Dependencies in <b>bold</b> has to be met!
> Python is only necessary for HTTP server and firefox should open croni's index.html locally without it.
> Croni will run fine without sendmail, it simply just doesn't send mails.

<br>

## Give it a try!

First, <b>back up</b> your current crontab - it will be replaced! Then execute following commands:

```
git clone https://github.com/boddenberg-it/croni-test
cd croni-test
./init.sh
```

Now, you should see your croni instance on [http://localhost:8080](http://localhost:8080).
> Firefox should open the index.html file locally.
<br>

![croni welcome page](https://boddenberg.it/github_images/croni/croni_welcome.png)

The first table shows information about jobs and submodule repositories. The second table is a build timeline.

<u>Some rows provide links:</u>
* duration opens workspace.
* name opens job page.
* build number opens console log as seen below.

![croni log pop up](https://boddenberg.it/github_images/croni/croni_console_log.png)
> Clicking 'welcome to croni' will show croni.log in same pop up.
<br>

Each project page is linked in the navigation bar and shows a table holding latest results of jobs within project.

![croni project page](https://boddenberg.it/github_images/croni/croni_project2.png)
<br>

## Configurations

After explaining the front end let's take a look at the structure of the example jobs repository:
```
.
├── croni
├── croni.cfg
├── init.sh
├── jobs
│   └── hello_project
│       └── hello_world.sh
└── README.md
```

Btw, croni creates ~/.croni while initialising. It is not listed above and holds following parameter:
```
croni_run=true
croni_update=false
croni_sendmail=false
```

The croni.cfg file holds following parameter:
```
croni_update_expression="0 5,17 * * *"

croni_port="8080"
croni_server_check_expression="0 * * * *"

croni_workspace_rotation="14"
croni_build_rotation="28"

# all default_xyz parameters can be overridden by job.
default_croni_timeout="1800"
default_croni_mail_recipients="croni@boddenberg.it"
default_croni_reason_87="This is the global (croni.cfg) reason message for exit code 87"
```
<br>

## How to create jobs?

A job can be any executable script, which declares following parameters in code or comment.
```
#!/usr/bin/python

croni="0 * * * *"

print('Hello World!')
```

Here is an example with all available job parameters.
```
#!/bin/sh

croni="0 * * * *"

croni_mail_recipients="croni@boddenberg.it"
croni_timeout="90"
croni_reason_87="job failed with exit code 87"

echo "foobar"
```

Additionally, creating a folder e.g. 'scripts' will allow you to call scripts within this folder and pass arguments as follows:
```
#!/bin/sh
croni="0 * * * *"

$base/scripts/example_script.sh "foo" "bar"
```
> The 'initialised' branch holds the test suite. It should give a good overview.

<br>

## How to maintain croni?

Croni automatically updates the jobs repository as long as croni_run in ~/.croni is true.
> Any local changes will be stashed in order to fulfill the update - nothing is lost!
<br>

Furthermore, you can use following commands to maintain croni:
```
# deploys changes
./croni.sh deploy

# fetches changes of jobs repository
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

## Okay, how do I keep this example?

You can simply fork this repository on github or create an empty repository on any arbitrary git server. Then do steps in "Give it a try!" section and change the remote-url to the one of your repository and push.

```
git remote set-url origin $URL
git push -u origin master
```
<br>

## What's next?

Basically, it's a hacky prototype. It would be interesting to (re)write croni properly in python to build a basis to go towards a "mature" CI server, but this depends on the feedback. Personally, it's a handy cronjob presenter and handler.
