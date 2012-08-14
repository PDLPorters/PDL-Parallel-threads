# Boilerplate
use strict;
use warnings;

package My::Foo;
use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);
use Test::More tests => 3;

##############################
# Basic namespace munging: 3 #
##############################

sequence(20)->sqrt->share_as('test');
my $short_name = retrieve_pdls('test');
my $long_name = eval{ retrieve_pdls('My::Foo::test') };
is($@, '', 'Retrieving fully resolved name does not croak (that is, they '
		. 'exist)');
ok(all($short_name == $long_name), 'Regular names get munged with the '
		. 'current package name');

sequence(20)->share_as('??foo');
eval{ retrieve_pdls('My::Foo::??foo') };
isnt($@, '', 'Names with weird characters are not packaged')
