#!/bin/sh

# plot cwnd data reconstructed from tcpdump 
tempf=$PATH_TRANSLATED

f=`mktemp -t f.XXXXXX` || echo "can't create temp file"
zcat $tempf > $f || cp $tempf $f

FORMAT=`echo "$QUERY_STRING" | sed -n 's/^.*format=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
STYLE=`echo "$QUERY_STRING" | sed -n 's/^.*style=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
PLOTNUM=`echo "$QUERY_STRING" | sed -n 's/^.*plot=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
TITLE=`echo "$QUERY_STRING" | sed -n 's/^.*title=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
XHI=`echo "$QUERY_STRING" | sed -n 's/^.*xhi=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
YHI=`echo "$QUERY_STRING" | sed -n 's/^.*yhi=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
if [[ $FORMAT = "eps" ]]; then
  FORMAT="postscript eps enhanced color"
  MIME="Application/PostScript"
else
  FORMAT="png"
  MIME="image/png"
fi

echo Content-type: $MIME 
echo ""

#start time
starttime=`grep -v -i "#" $f | head -n 1 | cut -d ' ' -f 1`
#first get list of unique destination ip and ports
flow_ids=` grep -v -i "#" $f | cut -d ' ' -f 2 | sort | uniq `

#now sort output for gnuplot
itemp=`mktemp -t i.XXXXXX` || echo "can't create temp file"
temp=`mktemp -t probe.XXXXXX` || echo "can't create temp file"
comma=''; plot='plot '; 
j=0
for i in $flow_ids; do
   grep -i $i $f >> $temp
   echo -e '\n\n' >>$temp
   #plot="$plot $comma '$temp' index $j u (\$1-$starttime):(\$3/1448) w p title 'flow $j cwnd', '$itemp' index $j u 2:4 w p axes x1y2 title 'flow $j tput'"
   plot="$plot $comma '$temp' index $j u (\$1-$starttime):(\$3/1448) w p title 'flow $j cwnd' "
   comma=","
   ((j++))
done

title1=`grep -i "#" $f | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $f | sed -n '2p' | sed -e 's/#//'`

rtt=`mktemp -t rtt.XXXXX` || echo "can't create temp file"
rttfile=`echo $tempf | sed -e 's/\.dump/-0\.ping/'`
if [  -e $rttfile ]; then
        awk '/time=/ {split($0,pieces,"time="); split(pieces[2],pieces," "); print pieces[1]} ' $rttfile >$rtt
	#sed -e '1d' | cut -f 7 -d ' ' | cut -f 2 -d '=' >$rtt
        plotping="plot \"$rtt\" u (\$0*1):1 w p title \"ping time\" "
else
        plotping=""
fi

iperf=`mktemp -t iperf.XXXXXX` || echo "can't create temp file"
iperffile=`echo $tempf | sed -e 's/dump/iprf/'`
if [  -e $iperffile ]; then
zcat $iperffile > $iperf || cp $iperffile $iperf
#first get list of unique destination ip and ports
flow_ids=`grep -v -i "#" $iperf | cut -d ' ' -f 1 | sort | uniq `
units=`cut -d ' ' -f 5 $iperf | head -n 1`

##now sort output for gnuplot
#itemp=`mktemp -t i.XXXXXX` || echo "can't create temp file"
comma=''; iplot='plot '; 
j=0
for i in $flow_ids; do
   grep -i $i $iperffile >> $itemp
   echo -e '\n\n' >>$itemp
   iplot="$iplot $comma '$itemp' index $j u 2:4 w p title 'flow $j tput'"
   comma=","
   ((j++))
done

ititle1=`grep -i "#" $iperf | sed -n '1p' | sed -e 's/#//'`
ititle2=`grep -i "#" $iperf | sed -n '2p' | sed -e 's/#//'`

fi
title1=`grep -i "#" $f | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $f | sed -n '2p' | sed -e 's/#//'`
title3=$meantputs

plott="plot [][0:1] 2"
MSTART="set size 2,2; set origin 0,0; set multiplot"
MEND="unset multiplot"
if [[ $PLOTNUM -eq 1 ]]; then
   iplot=""
   plotping=""
   plott=""
   MSTART=""
   MEND=""
elif [[ $PLOTNUM -eq 2 ]]; then
   plot=""
   plotping=""
   plott=""
   MSTART=""
   MEND=""
fi

if [[ $TITLE = "off" ]]; then
   title1=""
   title2=""
   title3=""
   plott=""
fi

preamble=""
if [[ $STYLE = "lachlan" ]]; then
   preamble="set size 0.5,0.35" 
   #preamble="set size 0.5,0.42"
fi

gnuplot <<EOF
set terminal $FORMAT  
set xlabel "time (s)"
set ylabel "cwnd (packets)"
set xrange [0:$XHI]
set yrange [0:$YHI]
#set y2label "throughput (Mbps)"
#set ytics nomirror
#set y2range [0:$YHI]
#set y2tics
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

rm $f $temp $rtt $iperf $itemp

