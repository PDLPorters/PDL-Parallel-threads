use strict;
use warnings;

use Test::More;
use Test::Exception;

use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);

# Allocate workspace with one extra slot (to verify zeroeth element troubles)
my $N_threads = 20;
my %workspaces = (
	c => sequence(byte, $N_threads + 1, 2)->share_as('workspace_c'),
	s => sequence(short, $N_threads + 1, 2)->share_as('workspace_s'),
	n => sequence(ushort, $N_threads + 1, 2)->share_as('workspace_n'),
	l => sequence(long, $N_threads + 1, 2)->share_as('workspace_l'),
	q => sequence(longlong, $N_threads + 1, 2)->share_as('workspace_q'),
	f => sequence(float, $N_threads + 1, 2)->share_as('workspace_f'),
	d => sequence($N_threads + 1, 2)->share_as('workspace_d'),
);

use threads;
use threads::shared;

###############################################
# Spawn a bunch of threads that work together #
###############################################

use PDL::NiceSlice;
my @success : shared;
my @correct_pointer : shared;
my @expected : shared;
threads->create(sub {
	my $tid = shift;
	
	my (%pointer_hash, %expected_hash, %success_hash, %bits_hash);
	for my $type_letter (keys %workspaces) {
		my $workspace = retrieve_pdls("workspace_$type_letter");
		
		# Make sure that this thread's data pointer points exactly to the
		# PV part of the piddle's datasv
		$pointer_hash{$type_letter}
			= PDL::Parallel::threads::__pdl_datasv_pv_is_data($workspace);
		
		# Build this up one thread at a time
		$expected_hash{$type_letter} = 1;
		
		# Have this thread touch one of the values, and have it double-check
		# that the value is correctly set
		$workspace($tid+1) .= sqrt($tid + 1);
		my $to_test = pdl($workspace->type, sqrt($tid + 1));
		$success_hash{$type_letter}
			= ($workspace->at($tid+1,0) == $to_test->at(0));
		
		# Have only certain threads touch the zeroeth element
		if ($tid % 3 == 0) {
			$workspace(0) .= sqrt(5);
		}
	}
	
	# Make sure the results for each type have a space in shared memory
	$correct_pointer[$tid] = shared_clone(\%pointer_hash);
	$expected[$tid] = shared_clone(\%expected_hash);
	$success[$tid] = shared_clone(\%success_hash);
	
}, $_) for 0..$N_threads-1;

# Reap the threads
for my $thr (threads->list) {
	$thr->join;
}

########################
# Now test the results #
########################

# Do all the threads think their datasv's pv is the same as their data?
is_deeply(\@correct_pointer, \@expected, 'All threads think the location of the data is correct');
# Do all the threads think that they were successful at setting their value?
is_deeply(\@success, \@expected, 'All threads changed their local values');
# Do the results of all but the zeroeth element agree with what we expect?

# Something gets messed up near the beginning of the data arrays when data
# are shared. These tests verify the documented "unsafe" offsets. Note that
# when these get fixed, be sure to update the slice offsets in test 30.

my %n_bad_offsets_for = (
	c => 0,
	s => 2,
	n => 2,
	l => 2,
	q => 2,
	f => 1,
	d => 1,
);

TODO: {
	for my $type_letter (keys %workspaces) {
		for my $start (0 .. $n_bad_offsets_for{$type_letter}) {
			my $workspace = $workspaces{$type_letter};
			my $subspace = $workspace($start:-1,(0));
			my $type = $workspace->type;
			# Set all but the last bad offset value as a "TODO" test
			local $TODO = "Figure out why ${start}th element of $type array gets scrozzled"
				unless $start == $n_bad_offsets_for{$type_letter};
			my $expected = ($subspace->sequence + $start)->sqrt;
			$expected(0) .= sqrt(5) if $start == 0;
			is_deeply([$subspace->list], [$expected->list],
				"Sharing all but ${start}th element of $type piddles works")
				or diag("Got (sub)workspace of $subspace; expected $expected");
		}
	}

};

for my $type_letter (keys %workspaces) {
	my $workspace = $workspaces{$type_letter};
	my $type = $workspace->type;

	my $expected = sequence($type, $N_threads + 1)->sqrt;
	$expected(0) .= sqrt(5);
	is_deeply([$workspace(:,1)->list], [$expected->list],
		"Sharing second row is perfectly safe for $type piddles")
		or diag("Got second row of " . $workspace(:,1));
}

######################################################
# Test croaking behavior for slices of various kinds #
######################################################

# Test what happens when we try to share a slice
my $slice = $workspaces{d}->(11:20);
throws_ok {
	$slice->share_as('slice');
} qr/share_pdls: Could not share a piddle under.*because the piddle is a slice/
, 'Sharing a slice croaks';

my $rotation = $workspaces{d}->rotate(5);
throws_ok {
	$rotation->share_as('rotation')
} qr/share_pdls: Could not share a piddle under.*because the piddle is a slice/
, 'Sharing a rotation (slice) croaks';


done_testing();
