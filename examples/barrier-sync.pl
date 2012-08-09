use strict;
use warnings;

use PDL;
use PDL::Parallel::threads;
use PDL::Parallel::threads::SIMD;
my $piddle = zeroes(20);
$piddle->share_as('test');

my $N_threads = 5;

launch_simd($N_threads, sub {
	my $tid = threads->self->tid;
	my $piddle = PDL::Parallel::threads::retrieve('test');
	
	print "Thread id $tid says the piddle is $piddle\n";
	barrier_sync;

	my $N_data_to_fix = $piddle->nelem / $N_threads;
	for (0..$N_data_to_fix-1) {
		$piddle->set($_ * $N_threads + $tid, $tid);
	}
	barrier_sync;
	
	print "After set, thread id $tid says the piddle is $piddle\n";
	barrier_sync;
	
	$piddle->set($tid, 0);
	barrier_sync;
	
	print "Thread id $tid says the piddle is now $piddle\n";
	
	barrier_sync;
});

