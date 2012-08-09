package PDL::Parallel::threads;

use strict;
use warnings;
use Carp;
use PDL;
use threads;
use threads::shared;

=head1 NAME

PDL::threads - enabling sharing of PDL data between Perl threads

=head1 VERSION

Version 0.01

=cut

BEGIN {
	our $VERSION = '0.01';
	use XSLoader;
	XSLoader::load 'PDL::Parallel::threads', $VERSION;
}

my %pointers :shared;

# PDL data should not be naively copied by Perl
sub PDL::CLONE_SKIP { 1 }

sub data_share {
	croak("PDL::Parallel::threads::share expects key/value pairs")
		unless @_ == 2;
	my %to_store = @_;
	
	while (my ($name, $piddle) = each %to_store) {
		$pointers{$name} = _get_pointer($piddle);
	}
}

sub PDL::share_as {
	my ($self, $name) = @_;
	data_share($name => $self);
}

sub retrieve {
	my @to_return;
	for my $name (@_) {
		push @to_return, _wrap($pointers{$name});
	}
	return @to_return if wantarray;
	return $to_return[0];
}

1;
