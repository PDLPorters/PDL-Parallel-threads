use strict;
use warnings;

use PDL;
use PDL::NiceSlice;
use PDL::Parallel::threads qw(retrieve_pdls);
use PDL::Parallel::threads::SIMD qw(parallelize parallel_sync parallel_id);
use threads::shared;

my $N_threads = 20;

my %workspaces = (
	c => sequence(byte, $N_threads + 1)->share_as('workspace_c'),
	s => sequence(short, $N_threads + 1)->share_as('workspace_s'),
	l => sequence(long, $N_threads + 1)->share_as('workspace_l'),
	q => sequence(longlong, $N_threads + 1)->share_as('workspace_q'),
	f => sequence(float, $N_threads + 1)->share_as('workspace_f'),
	d => sequence($N_threads + 1)->share_as('workspace_d'),
);


use PDL::NiceSlice;
parallelize {
	my $pid = parallel_id;
	
	for my $type_letter (keys %workspaces) {
		my $workspace = retrieve_pdls("workspace_$type_letter");
		my $type = $workspace->type;
		
		# Make sure that this thread's data pointer points exactly to the
		# PV part of the piddle's datasv
		PDL::Parallel::threads::__pdl_datasv_pv_is_data($workspace)
			or print "Thread $pid, type $type: datasv's pv is not data\n";
		
		# Have this thread touch one of the values, and have it double-check
		# that the value is correctly set
		$workspace($pid+1) .= sqrt($pid + 1);
		my $to_test = pdl($workspace->type, sqrt($pid + 1));
		($workspace->at($pid+1) == $to_test->at(0))
			or print "Thread $pid, type $type: setting data does not stick\n";
		
		# Have only certain threads touch the zeroeth element
		if ($pid % 3 == 0) {
			$workspace(0) .= sqrt(5);
		}
		
		# Have all threads examine the zeroeth element's bits, stringify, and
		# store in the shared array
		my $printing_id = $pid;
		$printing_id = "0$pid" if $pid < 10;
		my @to_examine = $workspace->at(0);
		push @to_examine, $workspace->at(1) unless $type_letter =~ /[fd]/;
		print "Thread $printing_id, type $type: Early bits are ",
			unpack ('b*', pack($type_letter, @to_examine)), "\n";
	}
	
} $N_threads-1;
