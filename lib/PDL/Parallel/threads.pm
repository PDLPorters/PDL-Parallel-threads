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
my %originating_tid :shared;
my %file_names :shared;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(share_pdls retrieve_pdls free_pdls);

# PDL data should not be naively copied by Perl
sub PDL::CLONE_SKIP { 1 }

sub auto_package_name {
	my $name = shift;
	my ($package_name) = caller(1);
	$name = join('::', $package_name, $name) if $name =~ /^\w+$/;
	return $name;
}

sub share_pdls {
	croak("PDL::Parallel::threads::share_pdl expects key/value pairs")
		unless @_ == 2;
	my %to_store = @_;
	
	while (my ($name, $to_store) = each %to_store) {
		$name = auto_package_name($name);
		
		# Make sure we're not overwriting already shared data
		if (exists $datasv_pointers{$name} or exists $file_names{$name}) {
			croak("share_pdls: you already have data associated with '$name'");
		}
		
		# Handle the special case where a memory mapped piddle was sent, and
		# for which the memory mapped piddle knows its file name
		if ( eval{$to_store->isa("PDL")}
			and exists $to_store->hdr->{mmapped_filename}
		) {
			$to_store = $to_store->hdr->{mmapped_filename};
		}
		
		if ( eval{$to_store->isa("PDL")} ) {
			# Share piddle memory directly
			$datasv_pointers{$name} = eval{_get_and_mark_datasv_pointer($to_store)};
			if ($@) {
				my $error = $@;
				chomp $error;
				delete $datasv_pointers{$name};
				croak('share_pdls: Could not share a piddle under '
					. "name '$name' because $error");

				
				print "Got error [[[$error]]]\n";
				if ($error eq 'not allocated') {
					croak(join('', 'share_pdls: You tried to share a piddle ',
						'that did not have allocated memory (probably a ',
						"slice) under name '$name'"));
				}
				elsif ($error eq 'dataflow') {
					croak(join('', 'share_pdls: You tried to share a piddle ',
						"under name '$name' that was marked as doing data ",
						'flow. Consider sharing a copied or severed piddle ',
						'instead'));
				}
				else {
					croak(join('', 'Apart from memory mapped piddles created ',
						"using PDL::IO::FastRaw, PDL::Parallel::threads cannot\n",
						'share piddles for which the data is *not* from the ',
						"datasv, which is the case for '$name'"));
				}
			}
			$dim_arrays{$name} = shared_clone([$to_store->dims]);
			$types{$name} = $to_store->get_datatype;
			$originating_tid{$name} = threads->tid;
		}
		elsif (ref($to_store) eq '') {
			# A file name, presumably; share via memory mapping
			if (-w $to_store and -r "$to_store.hdr") {
				$file_names{$name} = $to_store;
			}
			else {
				my $to_croak = join('', 'When share_pdls gets a scalar, it '
									, 'expects that to be a file to share as '
									, "memory mapped data.\nFor key '$name', "
									, "'$to_store' was given, but");
				# In the case the file is read only:
				croak("$to_croak there is no associated header file")
					unless -f "$to_store.hdr";
				croak("$to_croak you do not have permissions to read the "
					. "associated header file") unless -r "$to_store.hdr";
				croak("$to_croak you do not have write permissions for that "
					. "file") if -f $to_store;
				# In th case the file does not exist
				croak("$to_croak the file does not exist");
			}
		}
		else {
			croak("share_pdls passed data under '$name' that it doesn't "
				. "know how to store");
				}
	}
}



# Frees the memory associated with the given names.
sub free_pdls {
	# Keep track of each name that is successfully freed
	my @removed;
	
	for my $short_name (@_) {
		my $name = auto_package_name($short_name);
		
		# If it's a regular piddle, decrement the memory's refcount
		if (exists $datasv_pointers{$name}) {
			_dec_datasv_refcount($datasv_pointers{$name});
			delete $datasv_pointers{$name};
			delete $dim_arrays{$name};
			delete $types{$name};
			delete $originating_tid{$name};
			push @removed, $name;
		}
		# If it's mmapped, remove the file name
		elsif (exists $file_names{$name}) {
			delete $file_names{$name};
			push @removed, $name;
		}
		# If its none of the above, indicate that we didn't free anything
		else {
			push @removed, '';
		}
	}
	
	return @removed;
}

# PDL method to share an individual piddle
sub PDL::share_as {
	my ($self, $name) = @_;
	share_pdls(auto_package_name($name) => $self);
	return $self;
}

# Method to get a piddle that points to the shared data assocaited with the
# given name(s).
sub retrieve_pdls {
	return if @_ == 0;
	
	my @to_return;
	for my $short_name (@_) {
		my $name = auto_package_name($short_name);
		
		if (exists $datasv_pointers{$name}) {
			# Make sure that the originating thread still exists, or the
			# data will be gone.
			if ($originating_tid{$name} > 0
				and not defined (threads->object($originating_tid{$name}))
			) {
				croak("retrieve_pdls: '$name' was created in a thread that "
				. "is no longer available");
			}
			
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
		elsif (exists $file_names{$name}) {
			push @to_return, mapfraw($file_names{$name});
		}
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

# Now for a nasty hack: this code modifies PDL::IO::FastRaw's symbol table
# so that it adds the "mmapped_filename" key to the piddle's header before
# returning the result. As long as the user says "use PDL::IO::FastRaw"
# *after* using this module, this will allow for transparent sharing of both
# memory mapped and standard piddles.

{
	no warnings 'redefine';
	my $old_sub = \&PDL::IO::FastRaw::mapfraw;
	*PDL::IO::FastRaw::mapfraw = sub {
		my $name = $_[0];
		my $to_return = $old_sub->(@_);
		$to_return->hdr->{mmapped_filename} = $name;
		return $to_return;
	};
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
 
 # Or work with memory mapped files:
 share_pdls(other_name => 'mapped_file.dat');
 
 # Kick off some processing in the background
 async {
     my ($shallow_copy, $mapped_piddle)
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
L<PDL::Parallel::CPU>
or, for older versions of PDL, L<PDL::ParallelCPU>), this module lets you
work with Perl's built-in
threading model. In contrast to Perl's L<threads::shared>, this module
focuses on sharing I<data>, not I<variables>.

Because this module focuses on sharing data, not variables, it does not use
attributes to mark shared variables. Instead, you must explicitly share your
data by using the C<share_pdls> function or C<share_as> PDL method that this
module introduces. Those both associate a name with your data, which you use
later to retrieve the data with the C<retrieve_pdls>. Once your thread has
access to the piddle data, any modifications will operate directly on the
shared memory, which is exactly what shared data is supposed to do. When you
are completely done using a piece of data, you need to explicitly remove the
data from the shared pool with the C<free_pdls> function. Otherwise your
data will continue to consume memory until the originating thread terminates.

This module lets you share two sorts of piddle data. You can share data for
a piddle that is based on actual I<physical memory>, such as the result of
C<zeroes>. You can also share data using I<memory mapped> files. There are
other sorts of piddles whose data you cannot share. You cannot directly
share slices (though a simple C<sever> or C<copy> command will give you a
piddle based on physical memory that you can share). Also, certain functions
wrap external data into piddles so you can manipulate them with PDL methods.
For example, see C<PDL::Graphics::PLplot/plmap> and
C<PDL::Graphics::PLplot/plmeridians>. For these, making a physical copy with
PDL's C<copy> method will give you something that you can safey share.

=head2 Physical Memory

The mechanism by which this module achieves data sharing of physical memory
is remarkably cheap. It's even cheaper then a simple affine transformation.
It is so cheap, in fact, that it does not work for all kinds of PDL data.
The sharing works by creating a new shell of a piddle for each retrieval and
setting that piddle's memory structure to point back to the same
locations of the original (shared) piddle. This means that you can share
piddles that are created with standard constructors like C<zeroes>,
C<pdl>, and C<sequence>, or which are the result of operations and function
evaluations for which there is no data flow, such as C<cat> (but
not C<dog>), arithmetic, C<copy>, and C<sever>. When in doubt, C<sever> your
piddle before sharing and everything should work.

=head2 Memory Mapped Data

The mechanism by which this module achieves data sharing of memory mapped
files is exactly how you would share data across threads or processes using 
L<PDL::IO:::FastRaw>. However, there are a couple of important caveats to
using memory mapped piddls with C<PDL::Parallel::threads>. First, you must
load C<PDL::Parallel::threads> before loading L<PDL::IO::FastRaw>:

 # Good
 use PDL::Parallel::threads qw(retrieve_pdls);
 use PDL::IO::FastRaw;
 
 # BAD
 use PDL::IO::FastRaw;
 use PDL::Parallel::threads qw(retrieve_pdls);

This is necessary because C<PDL::Parallel::threads> has to perform a few
internal tweaks to L<PDL::IO::FastRaw> before you load its fuctions into
your local package.

Furthermore, any memory mapped files B<must> have header files associated
with the data file. That is, if the data file is F<foo.dat>, you must have
a header file called F<foo.dat.hdr>. This is overly restrictive and in the
future the module may perform more internal tweaks to L<PDL::IO::FastRaw> to
store whatever options were used to create the original piddle. But for the
meantime, be sure that you have a header file for your raw data file.

=head2 Package and Name Munging

C<PDL::Parallel::threads> provides a global namespace. Without some
combination of discipline and help, it would be easy for shared memory names
to clash. One solution to this would be to require users (i.e. you) to
choose names that include thier current package, such as
C<My::Module::workspace> instead of just C<workspace>. Well, I decided that
this is such a good idea that C<PDL::Parallel::threads> does this for you
automatically. At least, most of the time.

The basic rules are that the package name is prepended to the name of the
shared memory as long as the name is only composed of word characters, i.e.
names matching C</^\w+$/>. Here's an example demonstrating how this works:

 package Some::Package;
 use PDL;
 use PDL::Parallel::threads 'retrieve_pdls';
 
 # Stored under '??foo'
 sequence(20)->share_as('??foo');
 
 # Shared as 'Some::Package::foo'
 zeroes(100)->share_as('foo');
 
 # Retrieves 'Some::Package::foo'
 my $copy = retrieve_pdls('foo');
 
 # To retrieve shared data from some other package,
 # use the fully qualified name:
 my $other_data = retrieve_pdls('Other::Package::foo');

The upshot of all of this is that namespace clashes are very unlikely to
occur with shared data from other modules as long as you use simple names,
like the sort of thing that works for variable names.

=head1 FUNCTIONS AND METHODS

This module provides three stand-alone functions and adds one new PDL method.

=over

=item share_pdls (name => piddle|filename, name => piddle|filename, ...)

This function takes key/value pairs where the value is the piddle to store
or the file name to memory map, and the key is the name under which to store
the piddle or file name. You can later retrieve the memory (or a piddle
mapped to the given file name) with the L</retrieve_pdls> method.

Sharing a piddle with physical memory increments the data's reference count;
you can decrement the reference count by calling L</free_pdls> on the given
C<name>. In general this ends up doing what you mean, and freeing memory
only when you are really done using it. Memory mapped data does not need to
worry about reference counting as there is always a persistent copy on disk.

=for example

 my $data1 = zeroes(20);
 my $data2 = ones(30);
 share_pdls(foo => $data1, bar => $data2);

This can be combined with constructors and fat commas to allocate a
collection of shared memory that you may need to use for your algorithm:

 share_pdls(
     main_data => zeroes(1000, 1000),
     workspace => zeroes(1000),
     reduction => zeroes(100),
 );

=item piddle->share_as(name)

This is a PDL method, letting you share directly from any piddle. It does
the exact same thing as C<shared_pdls>, but it's invocation is a little
different:

=for example

 # Directly share some constructed memory
 sequence(20)->share_as('baz');
 
 # Share individual piddles:
 my $data1 = zeroes(20);
 my $data2 = ones(30);
 $data1->share_as('foo');
 $data2->share_as('bar');

There's More Than One Way To Do It, because it can make for easier-to-read
code. In general I recommend using the C<share_as> method for sharing
individual piddles:

 $something->where($foo < bar)->share_as('troubling');

=item retrieve_pdls (name, name, ...)

This function takes a list of names and returns a list of piddles that use
the shared data. In scalar context the function returns the piddle
corresponding with the first named data set, which is usually what you mean
when you use a single name. If you specify multiple names but call it in
scalar context, you will get a warning indicating that you probably meant to
say something differently.

=for example

 my $local_copy = retrieve_pdls('foo');
 my @both_piddles = retrieve_pdls('foo', 'bar');
 my ($foo, $bar) = retrieve_pdls('foo', 'bar');

=item free_pdls(name, name, ...)

This function marks the memory associated with the given names as no longer
being shared, handling all reference counting and other low-level stuff.
You generally won't need to worry about the return value. But if you care,
you get a list of values---one for each name---where a successful removal
gets the name and an unsuccessful removal gets an empty string.

So, if you say C<free_pdls('name1', 'name2')> and both removals were
successful, you will get C<('name1', 'name2')> as the return values. If
there was trouble removing C<name1> (because there is no memory associated
with that name), you will get C<('', 'name2')> instead. This means you
can handle trouble with perl C<grep>s and other conditionals:

 my @to_remove = qw(name1 name2 name3 name4);
 my @results = free_pdls(@to_remove);
 if (not grep {$_ eq 'name2'} @results) {
     print "That's weird; did you remove name2 already?\n";
 }
 if (not $results[2]) {
     print "Couldn't remove name3 for some reason\n";
 }

=back

=head1 LIMITATIONS

I have tried to make it clear, but in case you missed it, this module does
not let you share slices or specially marked piddles. If you need to share a
slice, you should C<sever> or C<copy> the slice first.

Another limitation is that you cannot share memory mapped files that require
features of L<PDL::IO::FlexRaw>. That is a cool module that lets you pack
multiple piddles into a single file, but simple cross-thread sharing is not
trivial and is not (yet) supported.

Finally, you B<must> load C<PDL::Parallel::threads> before loading
L<PDL::IO::FastRaw> if you wish to share your memory mapped piddles. Also,
you must have a C<.hdr> file for your data file, which is not strictly
necessary when using C<mapfraw>. Hopefully that limitation will be lifted
in forthcoming releases of this module.

=head1 BUGS

Need to document error messages. This bit of test may prove useful for
slices and other non-physical piddles:

 You can share this piddle by severing it first, or you can
 share a copy of this piddle

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

