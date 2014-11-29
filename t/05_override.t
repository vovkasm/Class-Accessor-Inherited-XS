use Test::More;
use strict;

package Test;

use parent qw/Class::Accessor::Inherited::XS/;
__PACKAGE__->mk_inherited_accessor(qw/foo foo/);

our $foo = 12;

package main;

is(Test->foo(42), 42);
is($Test::foo, 12);
is(Test->foo, 42);

done_testing;
