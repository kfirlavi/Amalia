#!/bin/bash

# load libraries
LIB_PATH="$(dirname $0)/../lib"

source $LIB_PATH/io
source $LIB_PATH/cgi

# plot cwnd data reconstructed from tcpdump 
input_file=$PATH_TRANSLATED

tcpdump_file=$(create_temp_file)
$IO_UNCOMPRESS_COMMAND $input_file > $tcpdump_file \
	|| cp $input_file $tcpdump_file


FORMAT=$(cgi_query_string format $QUERY_STRING)
PLOTNUM=$(cgi_query_string plot $QUERY_STRING)
TITLE=$(cgi_query_string title $QUERY_STRING)
XHI=$(cgi_query_string xhi $QUERY_STRING)
STYLE=$(cgi_query_string style $QUERY_STRING)
SIZE=$(cgi_query_string size $QUERY_STRING)

if [[ $FORMAT = "eps" ]]; then
  FORMAT="postscript eps enhanced color"
  MIME="Application/PostScript"
fi
if [[ $FORMAT = "" ]]; then
  FORMAT="png"
  case $SIZE in
    normal) FORMAT="png size 1200,800";;
    big) FORMAT="png size 2400,1600";;
    huge) FORMAT="png size 3200,2400";;
    *) FORMAT="png";;
  esac
  MIME="image/png"
fi

echo Content-type: $MIME 
echo ""

#first get list of unique destination ip and ports
flow_ids=`grep -v -i "#" $tcpdump_file | grep -v ":22" | cut -d ' ' -f 2 | sort | uniq `
#now sort tcp_probe output for gnuplot
temp=`mktemp -t probe.XXXXXX` || echo "can't create temp file"
tput=`mktemp -t tput.XXXXX` || echo "can't create temp file"
rtt=`mktemp -t rtt.XXXXX` || echo "can't create temp file" 
comma=''; plot='plot '; plotrtt='plot '
j=0
meantputs=""
for i in $flow_ids; do
   grep -i $i $tcpdump_file >> $temp
   echo -e '\n\n' >>$temp
   plot="$plot $comma '$temp' index $j using 1:7 with lines title 'flow $j cwnd', '$tput' index $j using 1:2 with points axes x1y2 title 'flow $j tput'"
   plotrtt="$plotrtt $comma '$temp' index $j using 1:10 with lines title 'flow $j srtt', '$temp' index $j using 1:11 with points title 'flow $j rtt'"
   comma=","
   meantputs=$meantputs`grep -i $i $tcpdump_file | awk --non-decimal-data 'BEGIN {t=-1; dt=1; sum=0; count=1;} {seq=$6; if (t<0) {t=$1; lastseq=seq;}; if ($1-t >= dt ) {tput=(seq-lastseq)*8/1024/1024/($1-t); if (tput>0 && t>200) {count=count+1;sum=sum+tput};  t=$1; lastseq=seq};  } END {printf "mean tput=%s Mbps ", sum/count; } ' ` 

   ((j++))
done

rttfile=`echo $input_file | sed -e 's/\.probe/\.ping/'`
if [  -e $rttfile ]; then
	cut -f 8 -d ' ' $rttfile | cut -f 2 -d '=' >$rtt
	plotping="plot \"$rtt\" title \"ping time\" "
else
    	plotping=""
fi

# get throughput from packet sequence numbers
awk --non-decimal-data 'BEGIN {t=-1; dt=1; } {if (NF < 6) printf "\n\n"; else {seq=$6; if (t<0 || t>$1) {t=$1; lastseq=seq; print $1, 0}; if ($1-t >= dt) {print $1, (seq-lastseq)*8/1024/1024/($1-t); t=$1; lastseq=seq}; } } ' $temp > $tput
#meantputs=`awk --non-decimal-data 'BEGIN {t=-1; dt=1; sum=0; count=1;i=0;} {if (NF>=6 && t>0 && t>$1) {printf "flow %s: mean tput=%s Mbps "} if (NF>=6) {seq=$6; if (t<0 || t>$1) {t=$1; lastseq=seq; sum=0; count=1; i=i+1;}; if ($1-t >= dt) {count=count+1;sum=sum+ (seq-lastseq)*8/1024/1024/($1-t); t=$1; lastseq=seq}; } } END {printf "flow %s: mean tput=%s Mbps ", i,sum/count; i=i+1; sum=0; count=1;} ' $temp ` 
#meantputs=`awk --non-decimal-data 'BEGIN {t=-1; lastt=0; i=0; seq=0; lastseq=0;} {if (NF >= 6) {if (t<0 || t>$1) {t=$1; lastseq=$6;} else {lastt=$1; seq=$6}; } else {printf "flow %s: mean tput=%s Mbps",i,(seq-lastseq)*8/1024/1024/(lastt-t); i=i+1; t=-1;} } END {printf "flow %s: mean tput=%s Mbs",i,(seq-lastseq)*8/1024/1024/(lastt-t); i=i+1; } ' $temp`


title1=`grep -i "#" $tcpdump_file | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $tcpdump_file | sed -n '2p' | sed -e 's/#//'`
title3=$meantputs

MSTART="set multiplot"
MEND="unset multiplot"
if [[ $PLOTNUM -eq 1 ]]; then
   plotrtt=""
   plotping=""
   MSTART=""
   MEND=""
elif [[ $PLOTNUM -eq 2 ]]; then
   plot=""
   plotping=""
   MSTART=""
   MEND=""
fi

if [[ $TITLE = "off" ]]; then
   title1=""
   title2=""
   title3=""
fi
preamble=""
if [[ $STYLE = "lachlan" ]]; then
   preamble = "set size 0.5, 0.35"
fi

gnuplot <<EOF
set xlabel "time (s)"
set ylabel "cwnd (packets)"
set y2label "throughput (Mbps)"
set ytics nomirror
set y2range [0:]
set y2tics
set xrange [0:$XHI]
#set title "$j flows, ${3}Mbps, ${2}ms latency, Q ${4} xBDP, test ${6}"
set title "$title1 \n $title2 \n $title3"
set terminal $FORMAT 
set size 1,2
set origin 0,0
$MSTART

set size 1, 0.95
set origin 0, 1
$preamble
#set size 0.6,0.42
$plot

set size 1,0.95
set origin 0, 0
set xlabel "time (s)"
set ylabel "srtt (ms)"
unset y2label
unset y2range
unset y2tics
set title ""
$plotrtt

set ylabel 'ping time (ms)'
$plotping

$MEND 

EOF

rm -f $tcpdump_file $temp $tput $rttfile

