#!/bin/sh

function print_error_page()
{
	echo Content-type: text/plain
	echo ""
	echo "Error: $1" 
}

FILE_TYPE=`echo $PATH_TRANSLATED | sed 's/\(.*\)\.\(.*\)/\2/'`
case "$FILE_TYPE" in
	probe)
		$PWD/gplot.probe.sh
		;;
	iperf)
		$PWD/gplot.iperf.sh
		;;
	dump)
		$PWD/gplot.dump.sh
		;;
	*)
		print_error_page "file type didn't match";
		;;
esac
