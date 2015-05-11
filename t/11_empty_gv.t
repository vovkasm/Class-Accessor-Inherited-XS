use Test::More;
use strict;

sub __cag_foo;

use parent qw/Class::Accessor::Inherited::XS/;
__PACKAGE__->mk_inherited_accessor(qw/foo foo/);

is(__PACKAGE__->foo(12), 12);

done_testing;
