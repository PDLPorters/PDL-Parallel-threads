package PDL::Parallel::threads::SIMD;

use strict;
use warnings;
use Carp;
use PDL;

=head1 NAME

PDL::Parallel::threads::SIMD - facilities for a Single-Instruction-Multiple-Dataset approach

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

require Exporter;
our @ISA = qw(Exporter);


our @EXPORT_OK = qw(barrier_sync launch_simd);

use threads qw(yield);
use threads::shared qw(cond_wait);

my $N_threads :shared = -1;

################
# barrier_sync #
################

my $barrier_count :shared = 0;
my $barrier_state :shared = 'ready';

sub barrier_sync {
	croak("Cannot call barrier_sync outside the context of a SIMD launch")
		if $N_threads < 1;
	
	yield until $barrier_state eq 'ready' or $barrier_state eq 'up';
	
	lock($barrier_count);
	$barrier_state = 'up';
	$barrier_count++;
	
	if ($barrier_count == $N_threads) {
		$barrier_count--;
		$barrier_state = 'down';
		cond_broadcast($barrier_count);
		yield;
	}
	else {
		cond_wait($barrier_count) while $barrier_state eq 'up';
		$barrier_count--;
		$barrier_state = 'ready' if $barrier_count == 0
	}
}

##################
# SIMD launching #
##################

sub run_it {
	my ($tid, $subref, @args) = @_;
	$subref->($tid, @args);
	
	barrier_sync;
}

sub launch_simd {
	($N_threads, my @args) = @_;
	# Launch N-1 threads...
	threads->create(\&run_it, $_, @args) for (1..$N_threads-1);
	# ... and execute the last thread in this, the main thread
	run_it(0, @args);
	
	# Reap the threads
	for my $thr (threads->list) {
		$thr->join;
	}
}

1;
