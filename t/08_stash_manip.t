use Test::More;

package Test;

use parent qw/Class::Accessor::Inherited::XS/;
__PACKAGE__->mk_inherited_accessor(qw/foo foo/);

*bar = *foo;

package main;

is(Test->foo(42), 42);
is(Test->bar, 42);
Test->bar(17);
is(Test->foo, 17);

undef *{Test::foo};
is(Test->bar, 17);

done_testing;
