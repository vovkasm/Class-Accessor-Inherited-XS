use Test::More;
use strict;

sub __cag_foo;

my $s = \%main::;
$s->{__cag_bar} = sub {return time()};

use parent qw/Class::Accessor::Inherited::XS::Compat/;
__PACKAGE__->mk_inherited_accessors('foo', 'bar');

is(__PACKAGE__->foo(12), 12);
is(__PACKAGE__->bar(12), 12);

done_testing;
