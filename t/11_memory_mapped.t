use strict;
use warnings;
use threads;

use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);
use PDL::IO::FastRaw;

use Test::More;

my $N_threads;
BEGIN {
	$N_threads = 10;
	require Test::More;
	eval {
		mapfraw('foo.dat', {Creat => 1, Dims => [$N_threads], Datatype => double})
			->share_as('workspace');
		Test::More->import(tests => 1);
		1;
	} or do {
		Test::More->import(skip_all => 'Platform does not support memory mapping');
	};
}


# Spawn a bunch of threads that do the work for us
use PDL::NiceSlice;
threads->create(sub {
	my $tid = shift;
	my $workspace = retrieve_pdls('workspace');
	$workspace($tid) .= sqrt($tid + 1);
}, $_) for 0..$N_threads-1;

# Reap the threads
for my $thr (threads->list) {
	$thr->join;
}

my $expected = (sequence($N_threads) + 1)->sqrt;
my $workspace = retrieve_pdls('workspace');
ok(all($expected == $workspace), 'Sharing memory mapped piddles works');

END {
	# Clean up the testing files
	unlink $_ for qw(foo.dat foo.dat.hdr);
}

done_testing;
