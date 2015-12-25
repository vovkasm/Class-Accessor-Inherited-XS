use strict;
use Test::More;

{
    package Test;
    use Class::Accessor::Inherited::XS inherited => [qw/foo/];

    *bar = *foo;
}

is(Test->foo(42), 42);
is(Test->bar, 42);
Test->bar(17);
is(Test->foo, 17);

undef *{Test::foo};
is(Test->bar, 17);

undef *{Test::__cag_foo};
is(Test->bar, undef);

done_testing;
