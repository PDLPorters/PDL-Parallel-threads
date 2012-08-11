package PDL::Parallel::threads;

use strict;
use warnings;
use Carp;
use PDL;
use PDL::IO::FastRaw;
use threads;
use threads::shared;

BEGIN {
	our $VERSION = '0.02';
	use XSLoader;
	XSLoader::load 'PDL::Parallel::threads', $VERSION;
}

# These are the means by which we share data across Perl threads. Note that
# we cannot share piddles directly accross threads, but we can share arrays
# of scalars, scalars whose integer values are the pointers to piddle data,
# etc.
my %datasv_pointers :shared;
my %dim_arrays :shared;
my %types :shared;
#my %file_names :shared;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(share_pdls retrieve_pdls free_pdls);

# PDL data should not be naively copied by Perl
sub PDL::CLONE_SKIP { 1 }

sub share_pdls {
	croak("PDL::Parallel::threads::share_pdl expects key/value pairs")
		unless @_ == 2;
	my %to_store = @_;
	
	while (my ($name, $to_store) = each %to_store) {
		
		# Make sure we're not overwriting already shared data
		if (exists $datasv_pointers{$name}) {# or exists $file_names{$name}) {
			croak("share_pdls: you already have data associated with '$name'");
		}
		
#		# Handle the special case where a memory mapped piddle was sent, and
#		# for which the memory mapped piddle knows its file name
#		if ( eval{$to_store->isa("PDL")} and exists $to_store->hdr->{"mmapped_filename"}) {
#			$to_store = $to_store->hdr->{"mmapped_filename"};
#		}
		
		if ( eval{$to_store->isa("PDL")} ) {
			# Share piddle memory directly
			$datasv_pointers{$name} = _get_and_mark_datasv_pointer($to_store);
			if ($datasv_pointers{$name} == 0) {
				delete $datasv_pointers{$name};
				croak(join('', 'Cannot share piddles for which the data is ',
						'*not* from the datasv, which is the case for ',
						"'$name'"));
			}
			$dim_arrays{$name} = shared_clone([$to_store->dims]);
			$types{$name} = $to_store->get_datatype;
		}
#		elsif (ref($to_store) eq '') {
#			# A file name, presumably; share via memory mapping
#			if (-w $name) {
#				$file_names{$name} = $to_store;
#			}
#			else {
#				my $to_croak = join('', 'When share_pdls gets a scalar, it '
#									, 'expects that to be a file to share as '
#									, "memory mapped data.\n For key '$name', "
#									, "'$to_store' was given, but ");
#				# In the case the file is read only:
#				croak("$to_croak you do not seem to have write permissions "
#						. "for that file") if -f $to_store;
#				# In th case the file does not exist
#				croak("$to_croak the file does not exist");
#			}
#		}
		else {
			croak("share_pdls passed data under '$name' that it doesn't know how to store");
		}
	}
}

# Frees the memory associated with the given names.
sub free_pdls {
	# Keep track of each name that is successfully freed
	my @removed;
	
	for my $name (@_) {
		# If it's a regular piddle, decrement the memory's refcount
		if (exists $datasv_pointers{$name}) {
			_dec_datasv_refcount($datasv_pointers{$name});
			delete $datasv_pointers{$name};
			delete $dim_arrays{$name};
			delete $types{$name};
			push @removed, $name;
		}
		# If it's mmapped, remove the file name
#		elsif (exists $file_names{$name}) {
#			delete $file_names{$name};
#			push @removed, $name;
#		}
		# If its none of the above, indicate that we didn't free anything
		else {
			push @removed, 0;
		}
	}
	
	return @removed;
}

# PDL method to share an individual piddle
sub PDL::share_as {
	my ($self, $name) = @_;
	share_pdls($name => $self);
	return $self;
}

# Method to get a piddle that points to the shared data assocaited with the
# given name(s).
sub retrieve_pdls {
	
	return if @_ == 0;
	
	my @to_return;
	for my $name (@_) {
		if (exists $datasv_pointers{$name}) {
			# Create the new thinly wrapped piddle
			my $new_piddle = _new_piddle_around($datasv_pointers{$name});
			$new_piddle->set_datatype($types{$name});  # set datatype
			
			# Set the dimensions
			my @dims = @{$dim_arrays{$name}};
			$new_piddle->setdims(\@dims);
			
			# Set flags to protect the piddle's memory:
			_update_piddle_data_state_flags($new_piddle);
			
			push @to_return, $new_piddle;
		}
#		elsif (exists $file_names{$name}) {
#			push @to_return, mapfraw($file_names{$name});
#		}
		else {
			croak("retrieve_pdls could not find data associated with '$name'");
		}
	}
	
	# In list context, return all the piddles
	return @to_return if wantarray;
	
	# Scalar context only makes sense if they asked for a single name
	return $to_return[0] if @_ == 1;
	
	# We're here if they asked for multiple names but assigned the result
	# to a single scalar, which is probably not what they meant:
	carp("retrieve_pdls: requested many piddles... in scalar context?");
	return $to_return[0];
}

1;

__END__

=head1 NAME

PDL::Parallel::threads - sharing PDL data between Perl threads

=head1 VERSION

This documentation describes version 0.02 of PDL::Parallel::threads.

=head1 SYNOPSIS

 use PDL;
 use PDL::Parallel::threads qw(retrieve_pdls share_pdls);
 
 # Technically, this is pulled in for you by PDL::Parallel::threads,
 # but using it in your code pulls in the named functions like async.
 use threads;
 
 # Also, technically, you can use PDL::Parallel::threads with
 # single-threaded programs.
 
 # Create some shared PDL data
 zeroes(1_000_000)->share_as('My::shared::data');
 
 # Create a piddle and share its data
 my $test_data = sequence(100);
 share_pdls(some_name => $test_data);  # allows multiple at a time
 $test_data->share_as('some_name');    # or use the PDL method
 
 ## # Or work with memory mapped files: XXX
 ## share_pdls(other_name => 'mapped_file.dat');
 
 # Kick off some processing in the background
 async {
     my ($shallow_copy, $mapped_piddle)  # XXX
         = retrieve_pdls('some_name', 'other_name');
     
     # thread-local memory
     my $other_piddle = sequence(20);
     
     # Modify the shared data:
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

This module provides a means to share PDL data between different Perl
threads. In contrast to PDL's posix thread support (see
L<PDL::ParallelCPU>), this module lets you work with Perl's built-in
threading model. In contrast to Perl's L<threads::shared>, this module
focuses on sharing I<data>, not I<variables>.

This module lets you share data by two means. First, you can share the
actual physical memory associated with a piddle that you create in your code.
XXX Second, you can share data using memory mapped files.

The mechanism by which this module achieves data sharing of physical memory
is remarkably cheap. It's even cheaper then a simple affine transformation.
It is so cheap, in fact, that it does not work for all kinds of PDL data.
The sharing works by creating a new shell of a piddle in each requesting
thread and setting that piddle's memory structure to point back to the same
locations of the original (shared) piddle. This means that you can share
piddles that are created with standard constructos like C<zeroes>,
C<pdl>, and C<sequence>, or which are the result of operations and function
evaluations for which there is no data flow, such as C<cat> (but
not C<dog>), arithmetic, C<copy>, and C<sever>. When in doubt, C<sever> your
piddle before sharing and everything should work.

The mechanism by which this module achieves data sharing of memory mapped
files is exactly how you would share data using memory mapping. In particular,
you must have a file with raw data already on disk before you perform any
data retrieval.

Unfortunately, at the moment there is an important distinction when sharing
(but not retrieving) memory mapped vs physical piddles. I believe this can
be fixed by making a few changes to how current PDL memory mapping routines
mark their piddles. Stay tuned...

C<PDL::Parallel::threads> behaves differently from L<threads::shared> because
it focuses on sharing data, not variables. As such, it does not use attributes
to mark shared variables. Instead, you must explicitly share your data by using
the C<share_pdls> function or C<share_as> PDL method that this module
introduces. Those both associate a name with your data, which you use later
to retrieve the data with the C<retrieve_pdls>. Once your thread has access to
the piddle data, any modifications will operate directly on the shared
memory, which is exactly what shared data is supposed to do. When you are
completely done using a piece of data, you need to explicitly remove the data
from the shared pool with the C<free_pdls> function. Otherwise you have a
memory leak.

=head1 FUNCTIONS AND METHODS

This modules provides three stand-alone functions and adds one new PDL method.

=over

=item share_pdls (name => piddle|filename, name => piddle|filename, ...)

This function takes key/value pairs where the value is the piddle to store
or the file name to memory map, and the key is the name under which to store
the piddle or file name. You can later retrieve the memory (or a piddle
mapped to the given file name) with the L</retrieve_pdls> method.

At the moment, if you pass a B<piddle> that is memory mapped (rather than
the file name associated with that memory mapping), C<share_pdls>
will croak. Unfortunately, this means that you must understand your data's
provenance, which may not always be possible. There may be some fancy way to
work around this, but it is a limitation of the current design.

Sharing a piddle with physical memory (as opposed to one that is memory
mapped) increments the data's reference count; you can decrement the
reference count by calling L</free_pdls> on the given C<name>. In general
this ends up doing what you mean, and freeing memory only when you are
really done using it. Memory mapped data does not need to worry about
reference counting as there is always a persistent copy on disk.

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

This doesn't work with memory mapped piddles at the moment, unfortunately.

=item retrieve_pdls (name, name, ...)

This function takes a list of names and returns a list of piddles that use
the shared data. In scalar context the function returns the piddle
corresponding with the first named data set, which is usually what you mean
when you use a single name.

=for example

 my $local_copy = retrieve_pdls('foo');
 my @both_piddles = retrieve_pdls('foo', 'bar');
 my ($foo, $bar) = retrieve_pdls('foo', 'bar');

This function works transparently, whether the shared data is a memory mapped
file or a physical piddle. XXX

=item free_pdls(name, name, ...)

This function marks the memory associated with the given names as no longer
being shared, handling all reference counting and other low-level stuff.

=back

=head1 BUGS AND LIMITATIONS

Need to make sure the docs get pulled in by the docs database.

Need to write the test suite.

Need to smooth the difference between memory mapping and regular piddles.
One strategy is to use the datasv part for memory mapped piddles (which isn't
used for memory mapped piddles) to track the reference counting. To avoid
hassles with the delete data magic, it might make sense to set the datasv
to a reference pointing to the actual, original memory mapped piddle, so
that its delete data magic doesn't get called until the refcount has dropped
to the appropriate level.

=head1 SEE ALSO

L<PDL::ParallelCPU>, L<MPI>, L<PDL::Parallel::MPI>, L<OpenCL>, L<threads>,
L<threads::shared>

=head1 AUTHOR, COPYRIGHT, LICENSE

This module was written by David Mertens. The documentation is copyright (C)
David Mertens, 2012. The source code is copyright (C) Northwestern University,
2012. All rights reserved.

This module is distributed under the same terms as Perl itself.

=cut

