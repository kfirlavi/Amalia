#!/usr/local/bin/bash
RTT=$1
STEP=$2
SLEEP=$3
TOTAL_TIME_TO_RUN=$4
MIN_RTT=$5
MAX_RTT=$6
RESTORE_RTT=$RTT
DIRECTION_FLAG="inc" # inc/dec RTT

set_rtt()
{
	local rtt=$(($1 / 2))
	ipfw pipe 1 config delay ${rtt}ms
}

set_rtt_direction()
{
	if (( $RTT <= $MIN_RTT ))
	then 
		DIRECTION_FLAG="up"
	fi

	if (( $RTT >= $MAX_RTT ))
	then 
		DIRECTION_FLAG="down"
	fi
}

while [[ $TOTAL_TIME_TO_RUN != 0 ]] 
do  
	((TOTAL_TIME_TO_RUN--))
	set_rtt $RTT
	echo $RTT
	if [[ $DIRECTION_FLAG == "up" ]]
	then 
		((RTT+=${STEP}))
	else
		((RTT-=${STEP}))
	fi
	set_rtt_direction
	sleep ${SLEEP}
done

set_rtt $RESTORE_RTT
