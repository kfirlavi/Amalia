#!/usr/bin/perl
$queue_file=$ARGV[0];
$drain_file=$ARGV[1];
open($FQ, "<$queue_file") || die "can't open $queue_file";
open($FD, "<$drain_file") || die "can't open $drain_file";

while (<$FD>) {
	($time1, $draintime) = split;

	push @{$drains{$time1}}, $draintime;
}
close $FD;

while (<$FQ>) {
	($time2, $queue) = split;

	push @{$queues{$queue}}, @{$drains{$time2}};
}
close $FQ;

print "# queue qs smallest largest ql mean number_of_samples\n";
foreach $queue (sort {$a <=> $b} keys %queues) {
	@l = sort {$a <=> $b} @{$queues{$queue}};

	$smallest = $l[0];
	$largest = $l[$#l];
	$qs = $l[int($#l*0.10)];
	$ql = $l[int($#l*0.90)];

	$sum = 0;
	foreach $d (@l) { $sum += $d; }
	$mean = ( $#l > 0 ) ? $sum /$#l : 0;

	print "$queue $qs $smallest $largest $ql $mean $#l\n";
}

