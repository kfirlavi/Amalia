#!/bin/sh

function print_error_page()
{
	cat <<- EOF
		Content-type: text/plain
		
		Error: $1
		FILE_TYPE=$FILE_TYPE
		PATH_TRANSLATED=$PATH_TRANSLATED
		EOF
}

function get_file_type()
{
	FILE_TYPE=`echo $PATH_TRANSLATED | sed 's/\(.*\)\.\(.*\)/\2/'`

	# if the file type is 'gz', then we need the type before (probe.gz ie. probe)
	if [[ $FILE_TYPE == "gz" ]]
	then
		FILE_TYPE=`echo $PATH_TRANSLATED | sed 's/\(.*\)\.\(.*\)\.gz/\2/'`
	fi
	echo $FILE_TYPE
}

FILE_TYPE=`get_file_type`
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
