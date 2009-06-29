#!/bin/bash

# load libraries
LIB_PATH="$(dirname $0)/../lib"

source $LIB_PATH/io
source $LIB_PATH/cgi

# plot cwnd data reconstructed from tcpdump 
input_file=$PATH_TRANSLATED

[  -e $input_file ] \
	&& iperf_datafile=$(io_uncompress_file $input_file)

echo Content-type: image/png
echo ""

#first get list of unique destination ip and ports
flow_ids=`grep -v -i "#" $iperf_datafile | cut -d ' ' -f 1 | sort | uniq `

#now sort output for gnuplot
temp=$(create_temp_file)
comma=''; plot='plot '; 
j=0
for i in $flow_ids; do
   grep -i $i $iperf_datafile >> $temp
   echo -e '\n\n' >>$temp
   plot="$plot $comma '$temp' index $j using 2:4 with points title 'flow $j tput'"
   comma=","
   ((j++))
done

title1=`grep -i "#" $iperf_datafile | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $iperf_datafile | sed -n '2p' | sed -e 's/#//'`

gnuplot <<EOF
set xlabel "time (seconds)"
set ylabel "throughput (Mbps)"
set yrange [0:]
set title "$title1 \n $title2"
set terminal png 
$plot
EOF

release_temp_file $temp
release_temp_file $iperf_datafile
