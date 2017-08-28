# croni

### Why?

Croni shall help persons and small teams, who are feeling the need for a CI server that at least runs daily. But don't want to setup and maintain a fully blown CI setup like Jenkins, Travis CI, Bamboo, et cetera.


### What functionalities does croni provide?

Basically, croni adds a front end to cron for better overview and forces one to put each cronjob in a repository.

List of functionalities:

- running each job run in a separate workspace
- declaring global timeout and job specific timeout
- declaring failure message for log depending on exit code

- build and workspace rotation of jobs (gc)
- provide update automation jobs and submodule
- everything lives in repo to share easily within teams,
  except ~/.croni to disable croni.

- expose information on local HTTP server
- static web pages
- show console log for each job run in pop up window
- show croni.log in pop up window
- expose job workspaces


### How?

To use croni one needs two git repositories. One holds the jobs and is created and maintained by you. The other one is croni itself, added as a submodule to the first mentioned repository. The current branch and revision of both repositories are exposed in front end.

bild auf croni_table

The first shown repo holds the croni.cfg file:

<croni.cfg file>

as well as all jobs in their project folder:

<tree -L 3>

A job can be any executable file, which declares following parameters in code or comment.

<example job>


Simply fork "repo" to get a prepared setup or clone it and change the remote url afterwards:

git clone
cd
git remote set-url origin [URL]

Then you can add your project and their jobs. Then initialise and deploy croni:

./croni/croni.sh init

Afterwards a croni.sh and logs/ symlink will be created as well as ~/.croni holding following configurations:


Et voilà, you can visit your croni instance on http://localhost:8080.


## Using croni

Croni automatically updates the jobs repository and submodule based on the cron expressions declared in croni.cfg, as long as croni_run is "true".
Note: any local changes will be stashed in order to fulfill the update in both cases.

The croni page holds a table providing information jobs and croni repository as well as a timeline of all jobs. All projects are linked in the navigation bar.
<image croni_page>

Each project page holds a timeline of its jobs and an overview table for each script, showing the result of the last build.

Finally, each job has an own page proividing its timeline.

Each timeline column provides following links:

- build bumber  -> console log pop up
- name          -> job page
- duration      -> workspace (dir-listing)

Note: clicking "welcome to croni" on croni page will show content of croni.log file.

Furthermore, you can use following commands:

./croni.sh init
./croni.sh deploy
./croni.sh start_server

./croni.sh run $project $jobfile
# runs although croni_run is "false" in croni.cfg
./croni.sh test $project $jobfile

an alias in ~/.bashrc à la:

alias croni="[PATH_JOBS_REPO]/croni.sh $@"

might be helpful to execute jobs from any directory.


### What's next?

Basically, it's a hacky prototype. It would be interesting to (re)write croni properly in python to build a basis to go towards a "mature" CI server,
but this depends on the feedback. Personally, it's a handy cronjob booster.
