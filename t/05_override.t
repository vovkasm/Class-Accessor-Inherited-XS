use strict;
use Test::More;

{
    package Test;
    use Class::Accessor::Inherited::XS inherited => [qw/foo/];
    our $foo = 12;
}

is(Test->foo(42), 42);
is($Test::foo, 12);
is(Test->foo, 42);

done_testing;
