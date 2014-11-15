use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;
    use strict;

    sub new { return bless {}, shift }

    Jopa->mk_group_accessors(inherited => qw/foo bar/);

    1;
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
