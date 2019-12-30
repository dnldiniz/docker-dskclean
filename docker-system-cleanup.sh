#!/bin/bash - 
#===============================================================================
#
#          FILE: docker-system-cleanup.sh
# 
#         USAGE: ./docker-system-cleanup.sh [OPTIONS]
# 
#   DESCRIPTION: In its most simple form, this script will clean up exited 
#                containers, unused images and layers that have no relationship
#                to any tagged images (dangling).  It is also possible to extend
#                the cleaning to dangling volumes and maybe in some future release,
#                the user will be allowed to manually specify resources to be kept 
#                so all the rest can be pruned.
# 
#       OPTIONS: -D; -c; -v; -q
#  REQUIREMENTS: Docker v1.9.0 or higher
#        AUTHOR: Daniel Diniz
#  ORGANIZATION: Balena
#       CREATED: 12/26/2019 10:45
#      REVISION: v0.5
#===============================================================================

set -o nounset                              # Treat unset variables as an error



typeset -i deepclean=0
typeset -i checkonly=0
typeset -i quiet=0

# Time-stamping can be turned on if package 'moreutils' is installed and replacing "cat" with "ts"
ts="cat"

# Images older than this date will be removed with deep clean
BEFORE_DATETIME=$(date --date='10 weeks ago' +"%Y-%m-%dT%H:%M:%S.%NZ")

prepare_log()
{
	logfile="./clean.log"
	rm -f $logfile
	touch $logfile
}

log()
{
	echo -e $1 2>&1 | $ts >> "$logfile" 2>&1
}

echo_log()
{
	log "$1"
	if [[ ! $quiet -eq 1 ]]; then
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
	
	# This might require sudo rights (tries to access /var/run/docker.sock)
	if docker version >/dev/null; then
		echo_log "Docker is working and responsive"
        API_VER=$(docker version --format '{{.Server.APIVersion}}')
        log "Docker API version: $API_VER"
        IFS='.'
        read -ra SPLIT_API_VER <<< $API_VER
        IFS=' '

        if [[ (${SPLIT_API_VER[0]} -lt 1) || (${SPLIT_API_VER[1]} -lt 25) ]]; then
            # TODO: Here we might want implement a legacy way to clean up resources for Docker Servers with API 
            # version older than 1.25
            echo_log "Legacy Docker version detected. This script might run commands that are not supported by this
            engine"
            exit 1
        fi

	else
		echo_log "Something is wrong with docker. Try running as root?"
		exit 1
	fi

}

clean_volumes()
{
	# Delete all volumes not associated with at least one container (dangling). 
	# Note that both automatically created container volumes and named volumes that aren't currently in use are also 
    # classified as "dangling". 
	# TODO: Filter out named volumes from being deleted with a smart egrep? 

	echo_log "Cleaning all volumes not associated with at least one container"
    DANGLING_VOLUMES=$(docker volume ls -qf dangling=true)

    if [[ ! -z $DANGLING_VOLUMES ]]; then
    	for VOLUME in $DANGLING_VOLUMES; do
    		if [[ $checkonly -eq 0 ]]; then
    			echo_log "Removing ${VOLUME}"
    			docker volume rm "${VOLUME}"
    		else
    			echo_log "Check only: volume ${VOLUME} would be removed"
    		fi 
    	done
    else
        echo_log "No volumes need to be cleaned"
    fi

    unset VOLUME
    unset DANGLING_VOLUMES
}

clean_containers()
{
	# Container status filters can be one of created, restarting, running, removing, paused, exited, or dead
	# Delete all containers marked as "exited" or "dead".
	# TODO: We could probably consider cleaning "created" containers, after checking that they do not start after a given
    # time has passed. Compare current time with container's created time?

	echo_log "Cleaning all containers either 'dead' or 'exited'"
    DANGLING_CONTAINERS=$(docker ps -a -q -f status=exited -f status=dead | xargs echo)

    if [[ ! -z $DANGLING_CONTAINERS ]]; then
        for CONTAINER in $DANGLING_CONTAINERS; do
	    	if [[ $checkonly -eq 0 ]]; then
	    		echo_log "Removing stopped or dead container $CONTAINER"
	    		if [[ $deepclean -eq 1 ]]; then
	    			docker rm -v $CONTAINER # Note that the -v will also remove any volumes associated with the container!
	    		else 
	    			docker rm $CONTAINER
	    		fi
	    	else
	    		echo_log "Check only: container ${CONTAINER} would be removed"
          fi
        done
    else
        echo_log "No containers need to be cleaned"
    fi

    unset CONTAINER
    unset DANGLING_CONTAINERS
}

clean_images()
{
    # Docker keeps all images ever used in the disk, even if those are not actively running.
	# Delete all images not associated with at least one container.
	# TODO: This function could benefit from a classification system to filter out images with specific TAGs, REPO's or 
    # CREATED timestamps. 
	# User input + docker inspect/grep|awk?

    if [[ $deepclean -eq 0 ]]; then
        echo_log "Cleaning all dangling (untagged) images"
        DANGLING_IMAGES=$(docker images --no-trunc --format "{{.ID}}" --filter dangling=true)
        # TODO: Also remove images older than a given [configurable] time span

        if [[ ! -z $DANGLING_IMAGES ]]; then
            for IMAGE in $DANGLING_IMAGES; do
	        	if [[ $checkonly -eq 0 ]]; then
	        		echo_log "Removing stopped or dead container $CONTAINER"
                    docker rmi $IMAGE
	        	else
	        		echo_log "Check only: image ${IMAGE} would be removed"
              fi
            done
        else
    		echo_log "No images need to be cleaned"
        fi

        unset IMAGE
        unset DANGLING_IMAGES
    else
        echo_log "Cleaning all images not associated with any containers (unused)"
    	ImagesBeforeCleanup=$(docker images -a | tail -n +2 | wc -l)
        RemainingContainers=$(docker ps -aq --no-trunc | xargs echo)
    
    	rm -f ImagesInUse	
        touch ImagesInUse	
    	docker images -q --no-trunc | sort -o ImageList
    
    	# Check which images are in use by current running containers and remove from the image cleanup list
    	# This prevents images being pulled from being deleted 
    	for CONTAINER in ${RemainingContainers}; do
    		INSPECT=$(docker inspect ${CONTAINER} | grep "\"Image\": \"\(sha256:\)\?[0-9a-fA-F]\{64\}\"")
    		IMAGE=$(echo ${INSPECT} | awk -F '"' '{print $4}')
    		echo "${IMAGE}" >> ImagesInUse
    	done
    
    	sort ImagesInUse -o ImagesInUse
        ToBeCleaned=$(comm -23 ImageList ImagesInUse | xargs echo)
    
    	# Remove all images and layers not currently in use by any container
    	# NOTE: I've deliberately decided not to use docker rmi $(docker images -f "dangling=true" -q) on this function;
    	# Dangling in this case means not tagged at all (just an id), while we want to remove all unused images.
    	if [[ ! -z "${ToBeCleaned// }" ]]; then
            echo_log "$(echo $ToBeCleaned | wc -l) images can be removed"

            for IMAGE in $ToBeCleaned; do
                if [[ $checkonly -eq 0 ]]; then
                    echo_log "Removimg image $IMAGE"
                    docker rmi $IMAGE
                else
                    echo_log "Check only: image $IMAGE would have been removed"
                fi
            done

            (( CLEANED_LAYERS=${ImagesBeforeCleanup} - $(docker images -a | tail -n +2 | wc -l) ))
            echo_log "Image deep clean-up done! ${CLEANED_LAYERS} images/layers have been cleaned"
    	else
    		echo_log "No images need to be cleaned"
    	fi
    fi
}

clean()
{
	echo_log "Starting the clean-up process"
	check_docker

	# Only clean (dangling) volumes on deepclean to prevent possibly valuable data loss
	if [[ $deepclean -eq 1 ]]; then
		clean_volumes	
	fi

	# Clean containers first as this will catch more dangling images and generate less errors
	clean_containers
	clean_images
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
        -q - 'quiet', the clean-up process will go as silently as possible - most of the output will be redirected to the
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
			D)
				deepclean=1
				;;
			c)
				checkonly=1
				;;
			q)
				quiet=1
				echo_log "Starting script, all output will be stored in $logfile"
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
