use strict;
use warnings;

use Test::More tests => 4;

use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);

my $N_threads = 20;
zeroes($N_threads)->share_as('workspace');

use threads;

# Spawn a bunch of threads that do the work for us
use PDL::NiceSlice;
my @success : shared;
threads->create(sub {
	my $tid = shift;
	my $workspace = retrieve_pdls('workspace');
	$workspace .= 5 if $tid == 0;
	$workspace($tid) .= sqrt($tid + 1);
	print "Thread $tid setting value of ", sqrt($tid + 1), "\n";
	$success[$tid] = ($workspace->at($tid) == sqrt($tid + 1));
	print "According to thread $tid, the workspace is $workspace\n";
}, $_) for 0..$N_threads-1;

# Reap the threads
for my $thr (threads->list) {
	$thr->join;
}

is_deeply(\@success, [(1)x$N_threads], 'All threads changed their local values');

my $expected = (sequence($N_threads) + 1)->sqrt;
my $workspace = retrieve_pdls('workspace');
is_deeply([$workspace->list], [$expected->list],
	'Sharing physical piddles works');

# Test what happens when we try to share a slice
my $slice = $workspace(11:20);
eval { $slice->share_as('slice') };
isnt($@, '', 'Sharing a slice croaks');

my $rotation = $workspace->rotate(5);
eval { $rotation->share_as('rotation') };
isnt($@, '', 'Sharing a rotation (slice) croaks');

