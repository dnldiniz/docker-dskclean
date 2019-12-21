# Balena Disk Clean-up

The goal of this script is to reclaim as much storage memory as possible
from the disk space occupied with redundant or otherwise unnecessary Docker files,
accumulated after cycles of deployment, testing and prototyping of applications
and services with this tool.
Before running this script, it's recommended to first analyse what the current
system status is. The following monitoring commands are useful to get an overview
of how much space each Docker component is currently using:

* [Monitoring Commands](#monitoring-commands)
* [Docker Storage Internals](#docker-storage-internals)

This road map is a living document, providing an overview of the goals and
considerations made in respect of the future of the project.

## Monitoring Commands

- docker info
- docker ps
- docker system df [-v]
## Images
- docker image ls
## Volumes
- docker volume ls [-f dangling=true]
- du -h /var/lib/docker/volumes/VOLUME\_ID/\_data
## Containers
- docker container ls -s

## Docker Storage Internals

*** TEST TYPE OF TEXT ****

### Clean-up Process

To clean up Docker environment, containers are the first resources that have
to be removed, as they lock all the rest.
Finally, to perform any kind of analysis docker commands have the inspect
subcommand, that combined with the format option become a powerful tool for
investigating any docker resource.

#### Cleaning Containers
docker rm -f $(docker ps -q -a)

#### Cleaning Images
docker rmi -f $(docker images -a -q)
Besides the force flag, this command will not delete an image if it’s used by a container or if it has dependent child images.


