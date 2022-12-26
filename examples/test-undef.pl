use strict;
use warnings;

use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);
use PDL::Parallel::threads::SIMD qw(parallel_sync parallelize parallel_id);
my $pdl = zeroes(20);
$pdl->share_as('test');
undef($pdl);

my $N_threads = 5;

use PDL::NiceSlice;
parallelize {
	my $tid = parallel_id;
	my $pdl = retrieve_pdls('test');
	
	print "Thread id $tid says the ndarray is $pdl\n";
	parallel_sync;

	my $N_data_to_fix = $pdl->nelem / $N_threads;
	my $idx = sequence($N_data_to_fix) * $N_threads + $tid;
	$pdl($idx) .= $tid;
	parallel_sync;
	
	print "After set, thread id $tid says the ndarray is $pdl\n";
	parallel_sync;
	
	$pdl->set($tid, 0);
	parallel_sync;
	
	print "Thread id $tid says the ndarray is now $pdl\n";
} $N_threads;


print "Final ndarray value is ", retrieve_pdls('test'), "\n";
