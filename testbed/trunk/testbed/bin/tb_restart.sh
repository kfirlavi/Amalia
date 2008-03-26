#!/bin/bash

if [ -z "$1" ]; then
	echo -e "\nUsage: `basename $0` comp 1 [comp 2] [etc.]..."
	exit 1
fi

echo "Found $# Command-Line Arguments"

idx=1
for arg in "$@"
do
	ssh root@${arg} reboot
	let "idx += 1"
done

exit 0


