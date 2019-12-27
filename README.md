# Balena Disk Clean-up

The goal of this script is to reclaim as much storage memory as possible from the disk space 
occupied with redundant or otherwise unnecessary Docker files, usually accumulated with heavy usage 
and cycles of deployment, testing and prototyping of applications and services.


* [Minimum Requirements](#minimum-requirements)
* [Monitoring Commands](#monitoring-commands)
* [Docker Storage Internals](#docker-storage-internals)


## Minimum Requirements

- This script requires Docker v1.9.0 to run properly
-- https://github.com/moby/moby/releases/tag/v1.9.0

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

In UNIX systems, Docker stores all of its resources in the /var/lib/docker directory.
The actual file structure under this folder varies dependeing on the driver used for storage, which
defaults to ***aufs***, but can fall back to ***overlay***, ***overlay2***, ***btrfs***, 
***devicemapper*** or ***zfs***.
__NOTE__: These files are managed by Docker and should be handled using the interfaces exposed by the Docker API.

If your system deviates from standard listed below, use [docker info](https://docs.docker.com/edge/engine/reference/commandline/info/) with the ```--filter``` parameter to extract which driver and location are currently in use by Docker.

```bash
$ docker info --format '{{.DriverStatus}}'
```
### Containers
- /var/lib/docker/containers

### Volumes
A volume allows data to persist, even when a container is deleted. 
Volumes are also a convenient way to share data between the host and the container, or between containers.
Volumes created by Docker are usually located under ```/var/lib/docker/volumes```

### Images
A Docker image is a collection of read-only layers. 
- When using aufs:
-- ***/var/lib/docker/aufs/diff/<id>*** has the file contents of the images.
-- ***/var/lib/docker/repositories-aufs*** is a JSON file containing local image information. 

- When using devicemapper:
-- ***/var/lib/docker/devicemapper/devicemapper/data*** stores the images
-- ***/var/lib/docker/devicemapper/devicemapper/metadata*** the metadata

In most other cases:
- ***/var/lib/docker/{driver-name}*** will contain the driver specific storage for contents of the images.
- ***/var/lib/docker/graph/<id>*** contains metadata about the image, in the json and layersize files.

__Note__: These files are thin provisioned "sparse" files so they aren't as big as they seem.

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

#### Cleaning Log Files
```bash
find /var/lib/docker/containers/ -type f -name “*.log” -delete

Restart docker containers to have those log files created again:
docker-compose down && docker-compose up -d
```

