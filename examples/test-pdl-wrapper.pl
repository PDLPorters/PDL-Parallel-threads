use strict;
use warnings;

use PDL;
use PDL::NiceSlice;
use PDL::Parallel::threads qw(retrieve_pdls);
use Test::More;

my $N_points = 10;

my $data = zeroes($N_points) + sqrt(5);
is($data->at(0), sqrt(5), 'Initial value is correct');
$data->share_as('test');
is($data->at(0), sqrt(5), 'Zeroeth value still correct after sharing');
for my $cid (0 .. $N_points-1) {
	# Ensure correct values
	is($data->at(0), sqrt(5), "Zeroeth value of data correct before copy id $cid");
	
	# Retrieve a copy; modify the slot
	my $copy = retrieve_pdls('test');
#	is($data->at(0), sqrt(5), "Zeroeth value of data correct after copy id $cid retrieval, before set");
	is($copy->at(0), sqrt(5), "Zeroeth value of copy correct after copy id $cid retrieval, before set");
	
	$copy($cid) .= sqrt(1 + $cid);
	$copy(0) .= sqrt(5) if $cid % 3 == 0;
	
#	is($copy->at(0), sqrt(5), "Zeroeth value correct after copy id $cid sets values");
}


my $expected = ($data(1:-1)->sequence + 2)->sqrt;
ok(all (approx ($data(1:-1), $expected)), 'Numerical agreement for all but first element')
	or diag("Expected $expected but got " . $data(1:-1));

#my @copies = map { retrieve_pdls('test') } 1..$N_points;

done_testing;
