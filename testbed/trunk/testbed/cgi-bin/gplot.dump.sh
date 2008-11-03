#!/bin/bash

# load libraries
LIB_PATH="$(dirname $0)/../lib"

source $LIB_PATH/io
source $LIB_PATH/cgi
source $LIB_PATH/plots

# plot cwnd data reconstructed from tcpdump 
input_file=$PATH_TRANSLATED

[  -e $input_file ] \
	&& tcpdump_file=$(io_uncompress_file $input_file)

FORMAT=$(cgi_query_string format $QUERY_STRING)
STYLE2=$(cgi_query_string style2 $QUERY_STRING)
PLOTNUM=$(cgi_query_string plot $QUERY_STRING)
TITLE=$(cgi_query_string title $QUERY_STRING)
XHI=$(cgi_query_string xhi $QUERY_STRING)
YHI=$(cgi_query_string yhi $QUERY_STRING)
XLO=$(cgi_query_string xlo $QUERY_STRING)
YLO=$(cgi_query_string ylo $QUERY_STRING)
STYLE=$(cgi_query_string style $QUERY_STRING)
SIZE=$(cgi_query_string size $QUERY_STRING)
NOTPUT=$(cgi_query_string tput $QUERY_STRING)

if [[ $FORMAT = "eps" ]]; then
  FORMAT="postscript eps enhanced color"
  MIME="Application/PostScript"
fi
if [[ $FORMAT = "" ]]; then
	if [[ $SIZE -gt 0 ]]; then
  		FORMAT="png size $(plots_get_zoom_plot_size $SIZE)"
	else
  		FORMAT="png size $(plots_get_plot_size)"
	fi
  	
  MIME="image/png"
fi

if [[ $STYLE = "" ]]; then
  STYLE="points"
fi

echo Content-type: $MIME 
echo ""

#start time
starttime=`grep -v -i "#" $tcpdump_file | head -n 1 | cut -d ' ' -f 1`
#first get list of unique destination ip and ports
flow_ids=` grep -v -i "#" $tcpdump_file | cut -d ' ' -f 2 | sort | uniq `

#now sort output for gnuplot
itemp=$(create_temp_file)
temp=$(create_temp_file)
tput=$(create_temp_file)

comma=''; plot='plot '; 
j=0
for i in $flow_ids; do
   grep -i $i $tcpdump_file >> $temp
   echo -e '\n\n' >>$temp
   #plot="$plot $comma '$temp' index $j u (\$1-$starttime):(\$3/1448) with $STYLE title 'flow $j cwnd', '$itemp' index $j u 2:4 with $STYLE axes x1y2 title 'flow $j tput'"
   if [[ $NOTPUT ]]; then
      plot="$plot $comma '$temp' index $j u (\$1-$starttime):(\$3/1448) with $STYLE title 'flow $j cwnd' "
   else
      plot="$plot $comma '$temp' index $j u (\$1-$starttime):(\$3/1448) with $STYLE title 'flow $j cwnd', '$tput' index $j u (\$1-$starttime):2 with $STYLE axes x1y2 title 'flow $j tput' "
   fi
   comma=","
   ((j++))
done

title1=`grep -i "#" $tcpdump_file | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $tcpdump_file | sed -n '2p' | sed -e 's/#//'`

if [  -e $rttfile ]; then
	ping_inputfile=$(echo $input_file | sed -e 's/\.dump/\.ping/')
	rttfile=$(io_uncompress_file $ping_inputfile)
	rtt=$(create_temp_file)
        awk '/time=/ {split($0,pieces,"time="); split(pieces[2],pieces," "); print pieces[1]} ' $rttfile > $rtt
	#sed -e '1d' | cut -f 7 -d ' ' | cut -f 2 -d '=' >$rtt
        plotping="plot \"$rtt\" u (\$0*1):1 with $STYLE title \"ping time\" "
else
        plotping=""
fi

iperffile=`echo $input_file | sed -e 's/dump/iprf/'`
[  -e $iperffile ] && iperf=$(io_uncompress_file $iperffile)

#first get list of unique destination ip and ports
flow_ids=`grep -v -i "#" $iperf | cut -d ' ' -f 1 | sort | uniq `
units=`cut -d ' ' -f 5 $iperf | head -n 1`

##now sort output for gnuplot
comma=''; iplot='plot '; 
j=0
for i in $flow_ids; do
   grep -i $i $iperf >> $itemp
   echo -e '\n\n' >>$itemp
   iplot="$iplot $comma '$itemp' index $j using 2:4 with $STYLE title 'flow $j tput'"
   comma=","
   ((j++))
done

# get throughput from packet sequence numbers in tcpdump
awk --non-decimal-data \
	'BEGIN {t=-1; dt=1; } {
		if (NF < 3) 
			printf "\n\n"; 
		else {
			seq=$4; 
			if (t<0 || t>$1) {
				t=$1; 
				lastseq=seq; 
				print $1, 0
			}; 
			if ($1-t >= dt) {
				print $1, (seq-lastseq)*8/1024/1024/($1-t); 
				t=$1; 
				lastseq=seq
			}; 
		} 
	}' $temp > $tput

ititle1=`grep -i "#" $iperf | sed -n '1p' | sed -e 's/#//'`
ititle2=`grep -i "#" $iperf | sed -n '2p' | sed -e 's/#//'`

title1=`grep -i "#" $tcpdump_file | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $tcpdump_file | sed -n '2p' | sed -e 's/#//'`
title3=$meantputs

plott="plot [][0:1] 2"
MSTART="set size 2,2; set origin 0,0; set multiplot"
MEND="unset multiplot"
if [[ "$PLOTNUM" -eq 1 ]]; then
   iplot=""
   plotping=""
   plott=""
   #MSTART=""
   #MEND=""
elif [[ "$PLOTNUM" -eq 2 ]]; then
   plot=""
   plotping=""
   plott=""
   #MSTART=""
   #MEND=""
fi

if [[ $TITLE = "off" ]]; then
   title1=""
   title2=""
   title3=""
   plott=""
fi

preamble=""
if [[ $STYLE2 = "lachlan" ]]; then
   preamble="set size 0.5,0.35" 
   #preamble="set size 0.5,0.42"
fi

YAXIS='set y2label "throughput (Mbps)"; set ytics nomirror; set y2range [0:]; set y2tics'
if [[ $NOTPUT ]]; then
	YAXIS=""
fi

gnuplot <<- EOF
	set terminal $FORMAT  
	#set pointsize 0.3
	set xlabel "time (s)"
	set ylabel "cwnd (packets)"
	set xrange [$XLO:$XHI]
	set yrange [$YLO:$YHI]
	#set y2label "throughput (Mbps)"
	#set ytics nomirror
	#set y2range [0:]
	#set y2tics
	$YAXIS
	$MSTART
	set title ""

	set size 1, 0.95
	set origin 0, 1 
	$preamble
	$plot

	#set size 1,0.95
	set origin 1, 1
	set ylabel "throughput (${units}bps)"
	#set title "$ititle1 \n $ititle2"
	$iplot

	#set size 1,0.95
	set origin 0, 0
	set ylabel 'ping time (ms)'
	$plotping

	set size 2,0
	set origin 0,2
	set title "$title1 $title2"
	unset border; unset key; unset xtics; unset ytics
	unset xlabel; unset ylabel
	#plot [][0:1] 2
	$plott

	$MEND
EOF

release_temp_file $tcpdump_file 
release_temp_file $temp 
release_temp_file $rtt 
release_temp_file $iperf 
release_temp_file $itemp

