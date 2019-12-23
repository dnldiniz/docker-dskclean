#!/bin/bash

typeset -i deepclean=0
typeset -i checkonly=0
typeset -i verbose=0
typeset -i quiet=0

# time-stamping can be turned on if package 'moreutils' is installed and replacing "cat" with "ts"
ts="cat"

prepare_log()
{
	logfile="./clean.log"
	rm -f $logfile
	touch $logfile
}

log()
{
	echo -e $1 2>&1 | $ts >> $logfile 2>&1
}

echo_log()
{
	log "$1"
	echo -e $1
}

# Continously log all from stdin to stdout and logfile
# Truncate really long lines on stdout
log_to_stdout_and_file()
{
	tee >($ts >> $logfile) | cut -c -4000
}

# Continously log all from stdin to logfile
log_to_file()
{
	$ts >> $logfile
}

verbose()
{
	log "$1"
	if [[ $quiet -eq 0 ]]
	then
		echo -e $1
	fi
}

check_docker()
{
	# This is the socket to the Docker REST API, through which the many docker clients (such as CLI)
	# send their requests towards the server.
	# Check if it exists so we can use the channel with the Docker Server.
	if [ ! -e "/var/run/docker.sock" ]; then
		echo "Cannot find /var/run/docker.sock, this script cannot be run from a container."
		exit 1
	fi
	
	# This might require sudo rights (tries to access /var/run/docker.sock)
	if docker version >/dev/null; then
		echo "docker is working and responsive"
	else
		echo "Something is wrong with docker. Try running as root?"
		exit 1
	fi
}

clean()
{
	echo_log "Starting the clean-up process"
	check_docker
}

usage_and_exit()
{
	cat << MAYDAY 2>&1
    USAGE:
        docker-dskclean [OPTIONS] 

    OPTIONS:
        -c - Check only. This will do a dry run and list all resources which would have been deleted if this flag was not passed.
        -D - Deep clean. Use this when you don't care about losing any images, containers or the data stored in the volumes.
            - Note: This will remove all containers, images and unused data volumes.
        -h - Display this help message and exit.
        -q - 'quiet', the clean-up process will go as silently as possible - most of the output will be redirected to the
            log file and only the most relevant info.
        -v - 'verbose', clean-up phase will output more textual information about what's being done.
	
    DESCRIPTION:
        In its most simple form, this script will clean up exited containers, unused images and layers that have no
        relationship to any tagged images (dangling).  It is also possible to extend the cleaning to dangling volumes and
        maybe in some future release, the user will be allowed to manually specify resources to be kept so all the rest
        can be pruned.
MAYDAY
	  exit 1
}

main()
{
	prepare_log	
	while getopts "cDhqv" opt; do
		case $opt in
			C)
				deepclean=1
				;;
			c)
				checkonly=1
				;;
			q)
				quiet=1
				echo_log "Starting script. All output will be stored in $logfile."
				;;
			v)
				verbose=1
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

	exit $result
}

main $@
