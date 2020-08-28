#!/bin/bash - 
#===============================================================================
#
#          FILE: docker-system-cleanup.sh
# 
#         USAGE: ./docker-system-cleanup.sh [OPTIONS]
# 
#   DESCRIPTION: In its most simple form, this script will clean up exited 
#                containers, unused images and layers that have no relationship
#                with any tagged images (dangling).  It is also possible to extend
#                the cleaning to dangling volumes and maybe in some future release,
#                the user will be allowed to manually specify resources to be kept 
#                so all the rest can be pruned.
# 
#       OPTIONS: -D; -c; -v; -q
#  REQUIREMENTS: Docker v1.9.0 or higher (Docker API v1.21+)
#        AUTHOR: Daniel Diniz
#  ORGANIZATION: 
#       CREATED: 12/26/2019 10:45
#      REVISION: v0.5
#===============================================================================

set -o nounset                              # Treat unset variables as an error


typeset -i CHECK_ONLY=0
typeset -i DEEP_CLEAN=0
typeset -i QUIET=0

# Time-stamping can be turned on if package 'moreutils' is installed and replacing "cat" with "ts"
ts="cat"

# TODO: Images older than this date will be removed with deep clean
BEFORE_DATETIME=$(date --date='10 weeks ago' +"%Y-%m-%dT%H:%M:%S.%NZ")

prepare_log()
{
	log_file="./clean.log"
	rm -f $log_file
	touch $log_file
}

log()
{
	echo -e $1 2>&1 | $ts >> "$log_file" 2>&1
}

echo_log()
{
	log "$1"
	if [[ ! $QUIET -eq 1 ]]; then
		echo -e $1
	fi
}

check_docker()
{
	# This is the socket to the Docker REST API, through which the many docker clients (such as CLI)
	# send their requests towards the server.
	# Check if it exists so we can use the channel with the Docker Server.
	if [ ! -e "/var/run/docker.sock" ]; then
		echo_log "Cannot find /var/run/docker.sock, this script cannot be run from a container"
		exit 1
	fi
	
	# Verify that Docker is reachable.
	# This might require sudo rights (tries to access /var/run/docker.sock)
	if docker version >/dev/null; then
		echo_log "Docker is working and responsive"
	else
		echo_log "Something is wrong with docker. Try running as root?"
		exit 1
	fi
}

check_server_api_version()
{
	# Read Docker server API version to see if it supports volume cleaning commands.
	# NOTE: Might need to check for client version if running outside of host or in a container.
    local api_ver
    local split_api_ver

    api_ver=$(docker version --format '{{.Server.APIVersion}}')
	log "Docker Server API version: $api_ver"
	IFS='.' read -ra split_api_ver <<< $api_ver

	if [[ (${split_api_ver[0]} -lt 1) || (${split_api_ver[1]} -lt 21) ]]; then
		# TODO: Here we might want to implement a legacy way to clean up volumes for Docker Servers with API 
        # version older than 1.21.
        echo_log "Legacy Docker version detected. Volume cleaning will be skipped"
		return 1
	fi
	return 0
}

clean_volumes()
{
	# Delete all volumes not associated with at least one container (dangling). 
	# Note that both automatically created container volumes and named volumes that aren't currently in use are also 
    # classified as "dangling". 
	# TODO: Filter out named volumes from being deleted with a smart egrep? 
	echo_log "Cleaning all volumes not associated with at least one container"
    local dangling_volumes
    dangling_volumes=$(docker volume ls -qf dangling=true)

    if [[ ! -z $dangling_volumes ]]; then
    	for volume in $dangling_volumes; do
    		if [[ $CHECK_ONLY -eq 0 ]]; then
    			echo_log "Removing ${volume}"
    			docker volume rm "${volume}"
    		else
    			echo_log "Check only: volume ${volume} would have been removed"
    		fi 
    	done
    else
        echo_log "No volumes need to be cleaned"
    fi
}

clean_containers()
{
	# Container status filters can be one of created, restarting, running, removing, paused, exited, or dead
	# Delete all containers marked as "exited" or "dead".
	# TODO: We could probably consider cleaning "created" containers, after checking that they do not start after a 
    # given time has passed. Compare current time with container's created time?

	echo_log "Cleaning all containers either 'dead' or 'exited'"
    local dangling_containers
    dangling_containers=$(docker ps -a -q -f status=exited -f status=dead | xargs echo)

    if [[ ! -z $dangling_containers ]]; then
        for container in $dangling_containers; do
	    	if [[ $CHECK_ONLY -eq 0 ]]; then
	    		echo_log "Removing stopped or dead container $container"
	    		if [[ $DEEP_CLEAN -eq 1 ]]; then
					# Note that the -v flag used below will also remove any volumes associated with the container!
	    			docker rm -v $container >/dev/null 
	    		else 
	    			docker rm $container >/dev/null
	    		fi
	    	else
	    		echo_log "Check only: container ${container} would have been removed"
          fi
        done
    else
        echo_log "No containers need to be cleaned"
    fi
}

clean_images()
{
    # Docker keeps all images ever used in the disk, even if those are not actively running.
	# Delete all images not associated with at least one container.
	# TODO: This function could benefit from a classification system to filter out images with specific TAGs, REPO's or 
    # CREATED timestamps. 
	# User input + docker inspect/grep|awk?
    # TODO: Also remove images older than a given [configurable] time span

    if [[ $DEEP_CLEAN -eq 0 ]]; then
        local dangling_images
        local image_repo # For pretty printing

        dangling_images=$(docker images --no-trunc --format "{{.ID}}" --filter dangling=true)

        echo_log "Cleaning all dangling (untagged) images"

        if [[ ! -z $dangling_images ]]; then
            for image_id in $dangling_images; do
                image_repo=$(docker images --no-trunc --format="{{.Repository}} {{.ID}}" \
                    | grep $image_id \
                    | awk '{print $1;}')
	        	if [[ $CHECK_ONLY -eq 0 ]]; then
	        		echo_log "Removing 'dangling' image: $image_repo"
                    docker rmi $image_id
	        	else
	        		echo_log "Check only: image ${image_repo} would have been removed"
              fi
            done
        else
    		echo_log "No images need to be cleaned"
        fi
    else
		declare -A used_images
    	local all_images

        all_images=$(docker images -a | tail -n +2 | wc -l)
		
		# collect images which has running container
		for image in $(docker ps | awk 'NR>1 {print $2;}'); do
		    image_id=$(docker inspect --format="{{.Id}}" $image);
		    used_images[$image_id]=$image;
		done
		
		if [ $all_images -gt ${#used_images[@]} ]; then
			# loop over images, delete those without a container
			for image_id in $(docker images --no-trunc -q); do
			    if [ -z ${used_images[$image_id]-} ]; then
					image_repo=$(docker images --no-trunc --format="{{.Repository}} {{.ID}}" \
                        | grep $image_id \
                        | awk '{print $1;}')
					if [[ $CHECK_ONLY -eq 0 ]]; then
						echo_log "Image $image_repo is NOT in use - cleaning"
						docker rmi $image_id
					else
						echo_log "Check only: $image_repo is NOT in use and would have been removed"
					fi
			    else
			        echo_log "Image ${used_images[$image_id]-} is in use - keeping"
			    fi
			done
        	    (( cleaned_layers=${all_images} - $(docker images -a | tail -n +2 | wc -l) ))
        	    echo_log "Image deep clean-up done! ${cleaned_layers} images/layers have been cleaned"
    	else
    		echo_log "No images need to be cleaned"
    	fi
    fi
}

clean()
{
	# TODO: Clean logs?
	echo_log "Starting the clean-up process"
	check_docker

	# Clean containers first as this will catch more dangling images and generate less errors
	clean_containers
	clean_images

	# Only clean (dangling) volumes on DEEP_CLEAN to prevent possibly valuable data loss
	if [[ $DEEP_CLEAN -eq 1 ]]; then
		check_server_api_version && clean_volumes	
	fi
}

usage_and_exit()
{
	cat << MAYDAY 2>&1
    USAGE:
        docker-dskclean [OPTIONS] 

    OPTIONS:
        -c - Check only. This will do a "dry run" and list all resources which would have been deleted if this flag was not passed.
        -D - Deep clean. Use this when you don't care about losing any data stored on the volumes.
            - Note: This will remove all volumes not currently associated with any container.
        -h - Display this help message and exit.
        -q - 'Quiet', the clean-up process will go as silently as possible - most of the output will be redirected to the
            log file and only the most relevant info.
	
    DESCRIPTION:
        In its most simple form, this script will clean up exited containers, unused images and layers that have no
        relationship to any tagged images (dangling).  It is also possible to extend the cleaning to dangling volumes and
        maybe in some future release, the user will be allowed to manually specify resources to be kept so all the rest
        can be pruned.
		NOTE: If you have exercised extreme caution with regard to irrevocable data loss, then you can delete unused (dangling) 
		volumes (v1.9 and up) by passing the -D (deep clean) flag.
MAYDAY
	  exit 1
}

main()
{
	prepare_log	
	while getopts "cDhq" opt; do
		case $opt in
			c)
				CHECK_ONLY=1
				;;
			D)
				DEEP_CLEAN=1
				;;
			q)
				QUIET=1
				echo "Starting script, all output will be stored in $log_file"
				;;
			h)
				usage_and_exit
				;;
			*)
				usage_and_exit
				;;
		esac
	done

	echo_log "docker disk clean initiated by `whoami` on `hostname` at `date -u`"
	clean
    result=$?

	exit $result
}

main $@
