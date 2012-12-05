use strict;
use warnings;

my $N_threads = $ARGV[0] || 2;

use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);
use PDL::Parallel::threads::SIMD qw(barrier_sync launch_simd);
zeroes(10_000_000)->share_as('test');
use PDL::IO::FastRaw;
mapfraw('foo.dat', {Creat => 1, Dims => [$N_threads], Datatype => double})
	->share_as('mapped');

print "Main thread is about to rest for 5 seconds\n";
sleep 5;

launch_simd($N_threads, sub {
	my $tid = shift;
	my ($piddle, $mapped) = retrieve_pdls('test', 'mapped');
	
	print "Thread id $tid is about to sleep for 5 seconds\n";
	barrier_sync;
	sleep 5;
	barrier_sync;
});


END {
	# Clean up the testing files
	unlink $_ for qw(foo.dat foo.dat.hdr);
}
