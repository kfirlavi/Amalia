#!/bin/bash

# load libraries
LIB_PATH="$(dirname $0)/../lib"

source $LIB_PATH/io
source $LIB_PATH/cgi
source $LIB_PATH/plots
source $LIB_PATH/tcpdump

# plot cwnd data reconstructed from tcpdump 
input_file=$PATH_TRANSLATED
INPUTFILE_BASE_NAME=$(echo $input_file | sed 's/\.dump//')

[ -e $input_file ] \
	&& TCPDUMP_FILE=$(io_uncompress_file $input_file)

get_query_string_params()
{
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
	SINGLEPLOT=$(cgi_query_string singleplot $QUERY_STRING)
	POINTSIZE=$(cgi_query_string pointsize $QUERY_STRING)
}

set_format()
{
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
}

set_style()
{
	if [[ $STYLE = "" ]]; then
		STYLE="points"
	fi
}

generate_gnuplot_command_of_cwnd_tput_plot()
{
	local tcpdump_file=$1
	local cwnd_plot_data=$2
	local tput_plot_data=$3
	local comma=
	local plot_command='plot ' 
	local j=0
	for i in $(tcpdump_get_uniq_ip_and_ports_from_tcpdump $tcpdump_file); do
		grep -i $i $tcpdump_file >> $cwnd_plot_data
		echo -e '\n\n' >> $cwnd_plot_data
		plot_command="$plot_command $comma '$cwnd_plot_data' index $j u (\$1-$starttime):(\$3/1448) with $STYLE title 'flow $j cwnd' "
		if [[ ! $NOTPUT ]]; then
			plot_command="$plot_command, '$tput_plot_data' index $j u (\$1-$starttime):2 with $STYLE axes x1y2 title 'flow $j tput' "
		fi
		comma=","
		((j++))
	done
	echo $plot_command
}

get_title_from_dumpfile()
{
	local dumpfile=$1
	local title_number=$2
	grep -i "#" $dumpfile \
		| sed -n "${title_number}p" \
		| sed -e 's/#//'
}

generate_ping_data()
{
	local rttfile=$1
	awk '/time=/ {
		split($0,pieces,"time="); 
		split(pieces[2],pieces," "); 
		print pieces[1]
	}' $rttfile
}

generate_ping_plot_command()
{
	local ping_plot_command=
	if [  -e $rttfile ]; then
		ping_inputfile=$INPUTFILE_BASE_NAME.ping.gz
		rttfile=$(io_uncompress_file $ping_inputfile)
		rtt_plot_data=$(create_temp_file)
		generate_ping_data $rttfile > $rtt_plot_data
		ping_plot_command="plot \"$rtt_plot_data\" u (\$0*1):1 with $STYLE title \"ping time\" "
	fi
	echo $ping_plot_command
}

main()
{
	get_query_string_params
	set_format
	set_style
	starttime=$(tcpdump_get_start_time $TCPDUMP_FILE)
	echo Content-type: $MIME 
	echo ""
	cwnd_plot_data=$(create_temp_file)
	tput_plot_data=$(create_temp_file)
	plot=$(generate_gnuplot_command_of_cwnd_tput_plot $TCPDUMP_FILE $cwnd_plot_data $tput_plot_data)
	tcpdump_generate_tput_plot_data $cwnd_plot_data > $tput_plot_data
	title1=$(get_title_from_dumpfile $TCPDUMP_FILE 1)
	title2=$(get_title_from_dumpfile $TCPDUMP_FILE 2)
	ping_plot_command=$(generate_ping_plot_command)
}
main

iperffile=$INPUTFILE_BASE_NAME.iprf
[  -e $iperffile ] && iperf=$(io_uncompress_file $iperffile)

#first get list of unique destination ip and ports
flow_ids=`grep -v -i "#" $iperf | cut -d ' ' -f 1 | sort | uniq `
units=`cut -d ' ' -f 5 $iperf | head -n 1`

##now sort output for gnuplot
iperf_plot_data=$(create_temp_file)
comma=''; 
iperf_plot_command='plot '; 
j=0
for i in $flow_ids; do
	grep -i $i $iperf >> $iperf_plot_data
	echo -e '\n\n' >>$iperf_plot_data
	iplot="$iperf_plot_command $comma '$iperf_plot_data' index $j using 2:4 with $STYLE title 'flow $j tput'"
	comma=","
	((j++))
done


ititle1=$(get_title_from_dumpfile $iperf 1)
ititle2=$(get_title_from_dumpfile $iperf 2)

title1=$(get_title_from_dumpfile $TCPDUMP_FILE 1)
title2=$(get_title_from_dumpfile $TCPDUMP_FILE 2)
title3=$meantputs

plott="plot [][0:1] 2"
MSTART="set size 2,2; set origin 0,0; set multiplot"
MEND="unset multiplot"
if [[ "$PLOTNUM" -eq 1 ]]; then
	iplot=""
	ping_plot_command=""
	plott=""
	#MSTART=""
	#MEND=""
elif [[ "$PLOTNUM" -eq 2 ]]; then
	plot=""
	ping_plot_command=""
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
if [[ $STYLE2 = "lachlan" ]]; then
	preamble="set size 0.5,0.35" 
	#preamble="set size 0.5,0.42"
fi

get_tput_axis_command()
{
	if [[ -z $NOTPUT ]]; then
		cat <<- EOF
			set y2label "throughput (Mbps)"
			set ytics nomirror
			set y2range [0:]
			set y2tics
		EOF
	fi
}

multi_plot()
{
	gnuplot <<- EOF
		set terminal $FORMAT  
		$(plots_pointsize_command $POINTSIZE)
		set xlabel "time (s)"
		set ylabel "cwnd (packets)"
		set xrange [$XLO:$XHI]
		set yrange [$YLO:$YHI]
		#set y2label "throughput (Mbps)"
		#set ytics nomirror
		#set y2range [0:]
		#set y2tics
		$(get_tput_axis_command)
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
		$iperf_plot_command

		#set size 1,0.95
		set origin 0, 0
		set ylabel 'ping time (ms)'
		$ping_plot_command

		set size 2,0
		set origin 0,2
		set title "$title1 $title2"
		unset border; unset key; unset xtics; unset ytics
		unset xlabel; unset ylabel
		#plot [][0:1] 2
		$plott

		$MEND
	EOF
}

generate_cwnd_plot()
{
	local tcpdump_file=$1
	local xlabel="time (sec)"
	local ylabel="cwnd (packets)"
	local cwnd_plot_data=$(create_temp_file)
	local tput_plot_data=$(create_temp_file)
	local plot_command=$(generate_gnuplot_command_of_cwnd_tput_plot $tcpdump_file $cwnd_plot_data $tput_plot_data)
	tcpdump_generate_tput_plot_data $cwnd_plot_data > $tput_plot_data

	gnuplot <<- EOF
		set terminal $FORMAT  
		$(plots_pointsize_command $POINTSIZE)
		set xlabel "$xlabel"
		set ylabel "$ylabel"
		set xrange [$XLO:$XHI]
		set yrange [$YLO:$YHI]
		set title "$title"
		$(get_tput_axis_command)
		$plot_command
	EOF

	release_temp_file $cwnd_plot_data
	release_temp_file $tput_plot_data
}

generate_ping_plot()
{
	local ping_plot_command=$(generate_ping_plot_command)
	local xlabel="time (sec)"
	local ylabel="ping time (ms)"

	gnuplot <<- EOF
		set terminal $FORMAT  
		$(plots_pointsize_command $POINTSIZE)
		set xlabel "$xlabel"
		set ylabel "$ylabel"
		set xrange [$XLO:$XHI]
		set yrange [$YLO:$YHI]
		set title "$title"
		$ping_plot_command
	EOF
}

case "$SINGLEPLOT" in
	cwnd)
		generate_cwnd_plot $TCPDUMP_FILE
		;;
	tput)
		single_plot "time (s)" "cwnd (packets)"
		;;
	ping)
		generate_ping_plot
		;;
	*)
		multi_plot;
		;;
esac
cat <<- EOF > /tmp/kfir
TCPDUMP_FILE    $TCPDUMP_FILE 
rtt             $rtt 
rttfile         $rttfile
iperf           $iperf 
cwnd_plot_data  $cwnd_plot_data 
tput_plot_data  $tput_plot_data
rtt_plot_data   $rtt_plot_data
iperf_plot_data $iperf_plot_data
EOF

release_temp_file $TCPDUMP_FILE 
release_temp_file $rtt 
release_temp_file $rttfile
release_temp_file $iperf 
release_temp_file $cwnd_plot_data 
release_temp_file $tput_plot_data
release_temp_file $rtt_plot_data
release_temp_file $iperf_plot_data
