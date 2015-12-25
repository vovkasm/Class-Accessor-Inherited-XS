use strict;
use Test::More;

{
    package Jopa;
    use Class::Accessor::Inherited::XS inherited => [qw/foo bar/];

    sub new { return bless {}, shift }
}

my $o = new Jopa;

is(Jopa->foo(12), 12);
is($o->foo, 12);
is(Jopa->foo, 12);

is(Jopa->bar(42), 42);
is(Jopa->foo, 12);
is($o->foo, 12);
is($o->bar, 42);

is($o->foo("oops"), "oops");
is($o->foo, "oops");
is(Jopa->foo, 12);
is(Jopa->bar, 42);

done_testing;
