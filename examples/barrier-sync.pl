use strict;
use warnings;

use PDL;
use PDL::NiceSlice;
use PDL::Parallel::threads qw(retrieve_pdl);
use PDL::Parallel::threads::SIMD qw(barrier_sync launch_simd);
my $piddle = zeroes(20);
$piddle->share_as('test');
#undef($piddle);

# Create and share a slice
my $slice = $piddle(10:15)->sever;
$slice->share_as('slice');

# Create and share a memory mapped piddle
use PDL::IO::FastRaw;
my $mmap = mapfraw('foo.bin', {Creat => 1, Datatype => double, Dims => [50]});
$mmap->share_as('mmap');

my $N_threads = 5;

launch_simd($N_threads, sub {
	my $tid = shift;
	my $piddle = retrieve_pdl('test');
	
	print "Thread id $tid says the piddle is $piddle\n";
	barrier_sync;

	my $N_data_to_fix = $piddle->nelem / $N_threads;
	my $idx = sequence($N_data_to_fix) * $N_threads + $tid;
	$piddle($idx) .= $tid;
	barrier_sync;
	
	print "After set, thread id $tid says the piddle is $piddle\n";
	barrier_sync;
	
	$piddle->set($tid, 0);
	barrier_sync;
	
	print "Thread id $tid says the piddle is now $piddle\n";
});

print "mmap is $mmap\n";
launch_simd($N_threads, sub {
	my $tid = shift;
	my $mmap = retrieve_pdl('mmap');
	
	$mmap($tid) .= $tid;
});

print "now mmap is $mmap\n";

launch_simd($N_threads, sub {
	my $tid = shift;
	my $piddle = retrieve_pdl('test');
	
	print "Thread id is $tid\n";
	
	my $N_data_to_fix = $piddle->nelem / $N_threads;
	my $idx = sequence($N_data_to_fix - 1) * $N_threads + $tid;
	use PDL::NiceSlice;
	$piddle($idx) .= -$tid;
	
	my $slice = retrieve_pdl('slice');
	$slice($tid) .= -10 * $tid;
});

print "Final piddle value is $piddle\n";
