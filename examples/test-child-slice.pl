use strict;
use warnings;

use PDL;
use PDL::Parallel::threads qw(retrieve_pdls);
use PDL::Parallel::threads::SIMD qw(parallelize);

my $N_threads = 5;

use PDL::NiceSlice;

my $pdl = zeroes(20);
my $slice = $pdl->(0:9);
print "ndarray:\n";
$pdl->dump;
print "slice:\n";
$slice->dump;
my $second = sequence(20);
my $rotation = $second->rotate(5);
print "second:\n";
$second->dump;
print "rotation:\n";
$rotation->dump;
print "\n\n+++ Modified rotation/second +++\n";
$rotation++;
print "second:\n";
$second->dump;
print "rotation:\n";
$rotation->dump;

$pdl->dump;
$pdl->share_as('test');
$rotation->dump;	
$rotation->share_as('rotated');

parallelize {
	my $tid = shift;
	my ($pdl, $rotated) = retrieve_pdls('test', 'rotated');
	$pdl($tid) .= $tid;
	$rotated($tid) .= $tid;
} $N_threads;


print "Final ndarray value is $pdl\n";
print "Slice is $slice\n";
print "Rotated ndarray is $rotation\n";
print "Parent of rotated ndarray $second\n";
