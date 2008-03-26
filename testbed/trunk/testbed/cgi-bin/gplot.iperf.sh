#!/bin/sh

# plot iperf data 
tempf=$PATH_TRANSLATED

f=`mktemp -t f.XXXXXX` || echo "can't create temp file"
zcat $tempf > $f || cp $tempf $f

echo Content-type: image/png
echo ""

#first get list of unique destination ip and ports
flow_ids=`grep -v -i "#" $f | cut -d ' ' -f 1 | sort | uniq `

#now sort output for gnuplot
temp=`mktemp -t probe.XXXXXX` || echo "can't create temp file"
comma=''; plot='plot '; 
j=0
for i in $flow_ids; do
   grep -i $i $f >> $temp
   echo -e '\n\n' >>$temp
   plot="$plot $comma '$temp' index $j u 2:4 w p title 'flow $j tput'"
   comma=","
   ((j++))
done

title1=`grep -i "#" $f | sed -n '1p' | sed -e 's/#//'`
title2=`grep -i "#" $f | sed -n '2p' | sed -e 's/#//'`

gnuplot <<EOF
set xlabel "time (seconds)"
set ylabel "throughput (Mbps)"
set yrange [0:]
set title "$title1 \n $title2"
set terminal png 
$plot
EOF

rm $f $temp 

