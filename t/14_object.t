use Test::More;
use strict;
use Class::Accessor::Inherited::XS object => ['foo'];

my $o = bless {foo => 66};
my $z = bless {};

is($o->foo, 66);
is($o->foo(12), 12);

is($z->foo, undef);
is(exists $z->{foo}, '');

is($o->foo, 12);

is($z->foo(42), 42);
is($o->foo, 12);
is($z->foo, 42);

done_testing;
