#!/bin/bash -x

# plot cwnd data reconstructed from tcpdump 
tempf=$PATH_TRANSLATED

f=`mktemp -t f.XXXXXX` || echo "can't create temp file"
zcat $tempf > $f || cp $tempf $f

FORMAT=`echo "$QUERY_STRING" | sed -n 's/^.*format=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
STYLE2=`echo "$QUERY_STRING" | sed -n 's/^.*style2=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
PLOTNUM=`echo "$QUERY_STRING" | sed -n 's/^.*plot=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
TITLE=`echo "$QUERY_STRING" | sed -n 's/^.*title=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
XHI=`echo "$QUERY_STRING" | sed -n 's/^.*xhi=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
YHI=`echo "$QUERY_STRING" | sed -n 's/^.*yhi=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
XLO=`echo "$QUERY_STRING" | sed -n 's/^.*xlo=\([^&]*\).*$/\1/p' | sed "s/%20//g"`
YLO=`echo "$QUERY_STRING" | sed -n 's/^.*ylo=\([^&]*\).*$/\1/p' | sed "s/%20//g"`
STYLE=`echo "$QUERY_STRING" | sed -n 's/^.*style=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
SIZE=`echo "$QUERY_STRING" | sed -n 's/^.*size=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`
NOTPUT=`echo "$QUERY_STRING" | sed -n 's/^.*tput=\([^&]*\).*$/\1/p' | sed "s/%20/ /g"`

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

if [[ $STYLE = "" ]]; then
  STYLE="points"
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
tput=`mktemp -t tput.XXXXX` || echo "can't create temp file"  
comma=''; plot='plot '; 
j=0
for i in $flow_ids; do
   grep -i $i $f >> $temp
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

title1=`grep -i "#" $f | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $f | sed -n '2p' | sed -e 's/#//'`

rtt=`mktemp -t rtt.XXXXX` || echo "can't create temp file"
rttfile=`echo $tempf | sed -e 's/\.dump/-0\.ping/'`
if [  -e $rttfile ]; then
        awk '/time=/ {split($0,pieces,"time="); split(pieces[2],pieces," "); print pieces[1]} ' $rttfile >$rtt
	#sed -e '1d' | cut -f 7 -d ' ' | cut -f 2 -d '=' >$rtt
        plotping="plot \"$rtt\" u (\$0*1):1 with $STYLE title \"ping time\" "
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
   grep -i $i $iperf >> $itemp
   echo -e '\n\n' >>$itemp
   iplot="$iplot $comma '$itemp' index $j using 2:4 with $STYLE title 'flow $j tput'"
   comma=","
   ((j++))
done

# get throughput from packet sequence numbers in tcpdump
awk --non-decimal-data 'BEGIN {t=-1; dt=1; } {if (NF < 3) printf "\n\n"; else {seq=$4; if (t<0 || t>$1) {t=$1; lastseq=seq; print $1, 0}; if ($1-t >= dt) {print $1, (seq-lastseq)*8/1024/1024/($1-t); t=$1; lastseq=seq}; } } '  $temp > $tput

ititle1=`grep -i "#" $iperf | sed -n '1p' | sed -e 's/#//'`
ititle2=`grep -i "#" $iperf | sed -n '2p' | sed -e 's/#//'`

fi
title1=`grep -i "#" $f | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $f | sed -n '2p' | sed -e 's/#//'`
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

gnuplot <<EOF
set terminal $FORMAT  
set pointsize 0.3
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

rm $f $temp $rtt $iperf $itemp

