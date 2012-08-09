package PDL::Parallel::threads;

use strict;
use warnings;
use Carp;
use PDL;
use threads;
use threads::shared;

BEGIN {
	our $VERSION = '0.01';
	use XSLoader;
	XSLoader::load 'PDL::Parallel::threads', $VERSION;
}

my %pointers :shared;
my %piddles;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(share_pdls retrieve_pdls remove_pdls);

# PDL data should not be naively copied by Perl
sub PDL::CLONE_SKIP { 1 }

sub share_pdls {
	croak("PDL::Parallel::threads::share_pdl expects key/value pairs")
		unless @_ == 2;
	my %to_store = @_;
	
	while (my ($name, $piddle) = each %to_store) {
		$pointers{$name} = _get_pointer($piddle);
		$piddles{$name} = $piddle;
	}
}

sub remove_pdls {
	for my $name (@_) {
		delete $pointers{$name};
		delete $piddles{$name};
	}
}

sub PDL::share_as {
	my ($self, $name) = @_;
	share_pdls($name => $self);
}

sub retrieve_pdls {
	my @to_return;
	for my $name (@_) {
		push @to_return, _wrap($pointers{$name});
	}
	return @to_return if wantarray;
	return $to_return[0];
}

1;

__END__

=head1 NAME

PDL::Parallel::threads - sharing PDL data between Perl threads

=head1 VERSION

This documentation describes version 0.01 of PDL::Parallel::threads.

=head1 SYNOPSIS

 use PDL;
 use PDL::Parallel::threads qw(retrieve_pdl share_pdl);
 
 # Technically, this is pulled in for you by PDL::Parallel::threads
 use threads;
 
 # Create some PDL data
 my $test_data = zeroes(1_000_000);
 
 # Store it for retrieval in the threads
 share_pdl(some_name => $test_data);
 
 # Another way to store data:
 $test_data->share_as('some_name');
 
 # Kick off some processing in the background
 async {
     my $shallow_copy = retrieve_pdl('some_name');
     $shallow_copy++;
 };
 
 # ... do some other stuff ...
 
 # Rejoin all threads
 for my $thr (threads->list) {
     $thr->join;
 }
 
 use PDL::NiceSlice;
 print "First ten elements of test_data are ",
     $test_data(0:9), "\n";

=head1 DESCRIPTION

This module aims to provide a means to share PDL data between different
Perl threads. In contrast to PDL's posix thread support (see
L<PDL::ParallelCPU>), this module lets you work with Perl's built-in
threading model. In contrast to Perl's L<threads::shared>, this module
focuses on sharing I<data>, not I<variables>.

The mechanism by which this module achieves data sharing is remarkably cheap.
It's even cheaper then a simple affine transformation. In contrast, I have
been led to believe the cost of creating a new Perl thread is quite high in
general compared with other means for performing parallel computing. I cannot
say more because I need to back up any claims with benchmarks, which I do not
yet have.

But getting back to that data sharing: it is quite cheap. It is so cheap,
in fact, that it does not work for all kinds of PDL data. The sharing works
by creating a new shell of a piddle in each requesting thread and setting
that piddle's C<data> and C<datasv> struct members to point back to the same
locations of the original (shared) piddle. This means that you can share
piddles that are (1) created with standard constructos like C<zeroes>,
C<pdl>, and C<sequence>, (2) memory mapped, and (3) the result of operations
and function evaluations for which there is no data flow, such as C<cat> (but
not C<dog>), arithmetic, C<copy>, and C<sever>. When in doubt, C<sever> your
piddle before sharing and everything should work.

C<PDL::Parallel::threads> behaves differently from L<threads::shared> because
it focuses on sharing data, not variables. As such, it does not use attributes
to mark shared variables. Instead, you must explicitly share your data by using
the C<share_pdls> function or C<share_as> PDL method that this module
introduces. Those both associate a name with your data, which you use later
to retrieve the data with the C<retrieve_pdls>. Once your thread has access to
the piddle data, any modifications will operate directly on the shared
memory, which is exactly what shared data is supposed to do. When you are
completely done using a piece of data, you need to explicitly remove the data
from the shared pool with the C<remove_pdls> function. Otherwise you have a
memory leak.

=head1 FUNCTIONS AND METHODS

This modules provides three stand-alone functions and adds one new PDL method.

=over

=item share_pdls (name => piddle, ...)

This function takes key/value pairs where the value is the piddle to store
and the key is the name under which to store the piddle. The module keeps a
local reference to your piddle, so you can C<undef> or otherwise reuse the
variable that originally held your data.

=for example

 my $data1 = zeroes(20);
 my $data2 = ones(30);
 share_pdls(foo => $data1, bar => $data2);

=item piddle->share_as(name)

This is a PDL method, letting you share directly from any piddle. It does
the exact same thing as C<shared_pdls>, but it's invocation is a little
different:

=for example

 my $data1 = zeroes(20);
 my $data2 = ones(30);
 $data1->share_as('foo');
 $data2->share_as('bar');

=item retrieve_pdls (name, name, ...)

This function takes a list of names and returns a list of piddles whose
memory points to the shared memory of the given names. In scalar context the
function returns the piddle corresponding with the first named data set.

=for example

 my $local_copy = retrieve_pdls('foo');
 my @both_piddles = retrieve_pdls('foo', 'bar');
 my ($foo, $bar) = retrieve_pdls('foo', 'bar');

=item remove_pdls(name, name, ...)

This function frees the memory associated with the given names. Note that you
must call this function from the thread that originally shared the data in
order to actually free the memory. If you call it from some other thread,
the memory will no longer be available, but it will not be de-allocated.

=back

=head1 BUGS AND LIMITATIONS

Need to make sure the docs get pulled in by the docs database.

Need to write the test suite.

=head1 SEE ALSO

L<PDL::ParallelCPU>, L<MPI>, L<PDL::Parallel::MPI>, L<OpenCL>, L<threads>,
L<threads::shared>

=head1 AUTHOR, COPYRIGHT, LICENSE

This module was written by David Mertens. The documentation is copyright (C)
David Mertens, 2012. The source code is copyright (C) Northwestern University,
2012. All rights reserved.

This module is distributed under the same terms as Perl itself.

=cut

