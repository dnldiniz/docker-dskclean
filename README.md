# Docker Disk Clean-up

The goal of this script is to reclaim as much storage memory as possible from the disk space 
occupied with redundant or otherwise unnecessary Docker files, usually accumulated with heavy usage 
and cycles of deployment, testing and prototyping of applications and services.


* [Minimum Requirements](#minimum-requirements)
* [Docker Storage Internals](#docker-storage-internals)
* [Clean-up Process](#clean-up-process)
* [Monitoring Commands](#monitoring-commands)
* [Improvements and Optimizations](#improvements-and-optimizations)

## Minimum Requirements

1. Linux system running Docker
2. User account with sudo priviliges
3. Cleaning volumes requires features available on Docker v1.9.0 and higher. See the 
[Docker v1.9.0 Release Notes](https://github.com/moby/moby/releases/tag/v1.9.0).

## Docker Storage Internals

In UNIX systems, Docker stores all of its resources in the /var/lib/docker directory.
The actual file structure under this folder varies dependeing on the driver used for storage, which
defaults to ```aufs```, but can fall back to ```overlay```, ```overlay2```, ```btrfs```, 
```devicemapper``` or ```zfs```.

__NOTE__: These files are managed by Docker and should be handled using the interfaces exposed by the Docker API.

If your system deviates from standard listed below, use 
[docker info](https://docs.docker.com/edge/engine/reference/commandline/info/) with the ```--filter``` parameter 
to extract which driver and location are currently in use by Docker.

```bash
$ docker info --format '{{.DriverStatus}}'
```
### Containers

Containers are started with their base imaged mounted as read-only. On top of that, a writable layer is mounted, which
store all the delta between its current and starting states. 
To effectively remove all containers, run ```docker container stop $(docker container ls –aq)``` before executing this
script.
Containers are stored in ```/var/lib/docker/containers```.

__NOTE__: All data stored in the writable layer of the removed containers will be permanently lost.

### Volumes

A volume allows data to persist, even when a container is deleted. 
Volumes are also a convenient way to share data between the host and the container, or between containers.
Volumes created by Docker are usually located under ```/var/lib/docker/volumes```

If the ```deep-clean``` flag is used, this script will remove all volumes not associated with any running containers.  
Otherwise, no volumes will be removed, as that could potentially cause valuable data to be permanently lost.

### Images

A Docker image is a collection of read-only layers. Dangling images are layers that have no relationship with any tagged
images. These are not strictly necessary anymore and are mostly only used for Docker's caching mechanism, thus safe to
remove to free up disk space.

- When using aufs:
-- ```/var/lib/docker/aufs/diff/<id>``` has the file contents of the images.
-- ```/var/lib/docker/repositories-aufs``` is a JSON file containing local image information. 

- When using devicemapper:
-- ```/var/lib/docker/devicemapper/devicemapper/data``` stores the images
-- ```/var/lib/docker/devicemapper/devicemapper/metadata``` the metadata

In most other cases:
- ```/var/lib/docker/{driver-name}``` will contain the driver specific storage for contents of the images.
- ```/var/lib/docker/graph/<id>``` contains metadata about the image, in the json and layersize files.

__Note__: These files are thin provisioned "sparse" files so they aren't as big as they seem.

## Clean-up Process

When cleaning up a Docker environment, containers are the first resources that should be removed, as they lock the all 
the rest (images, volumes, networks). This script has primarily two execution modes, namely "Normal" (without -D flag) 
and "Deep-clean" mode (with -D flag). 

### Normal Mode

Only "dangling" resources are cleaned and no volumes are touched.
Containers are filtered based on their current status and removed when it's either "exited" or "dead".

### Deep-clean Mode

Besides "dangling" resources, volumes and tagged images not associated with any containers will also be removed.

### Cleaning Log Files

Sometimes, just cleaning the log files generated by containers can free up a lot of space.
This is currently not handled by the script, but can be done using the command below.
Remember to always restart the containers afterwards so the log files can be re-generated.

```bash
find /var/lib/docker/containers/ -type f -name “*.log” -delete

# Restart docker containers to have those log files created again:

docker-compose down && docker-compose up -d
```

## Monitoring Commands
It is highly advisable to use the built-in monitoring commands available in Docker to understand on a high level which
resources are being stored in your system.`

## General 
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

# Improvements and Optimizations
To limit the scope of this assignment, I've left a number of improvement ideas scattered through the code tagged with
TODO's. This is of course not meant to be released, but are easier to understand when left within the context in which
they belong.

One nifty idea I got from StackOverflow to effectively reduce disk usage without using the Docker engine would be as
follows:

1. Save all images: 
+ ```docker save $(docker images |sed -e '/^/d' -e '/^REPOSITORY/d' -e 's,[ ][ ],:,' -e 's,[ ].,,') > /root/docker.img```
3. Uninstall docker.
4. Erase everything in /var/lib/docker: 
+ ```rm -rf /var/lib/docker/[cdintv]*```
5. Reinstall docker
6. Enable docker: 
+ ```systemctl enable docker```
7. Start docker: 
+ ```systemctl start docker```
8. Restore images: 
+ ```docker load < /root/docker.img```
9. Start any persistent containers you need running.
