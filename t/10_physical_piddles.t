use strict;
use warnings;

use Test::More tests => 3;

use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);

my $N_threads = 100;
zeroes($N_threads)->share_as('workspace');

use threads;

# Spawn a bunch of threads that do the work for us
use PDL::NiceSlice;
threads->create(sub {
	my $tid = shift;
	my $workspace = retrieve_pdls('workspace');
	$workspace($tid) .= sqrt($tid);
}, $_) for 0..$N_threads-1;

# Reap the threads
for my $thr (threads->list) {
	$thr->join;
}

my $expected = sequence($N_threads)->sqrt;
my $workspace = retrieve_pdls('workspace');
ok(all($expected == $workspace), 'Sharing physical piddles works');

# Test what happens when we try to share a slice
my $slice = $workspace(11:20);
eval { $slice->share_as('slice') };
isnt($@, '', 'Sharing a slice croaks');

my $rotation = $workspace->rotate(5);
eval { $rotation->share_as('rotation') };
isnt($@, '', 'Sharing a rotation (slice) croaks');

