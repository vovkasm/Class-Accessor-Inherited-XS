use Test::More;
use strict;

{
    package Jopa;
    use Class::Accessor::Inherited::XS inherited => {
        foo => 'bar',
    };
    use Class::Accessor::Inherited::XS {
        inherited => [qw/boo baz/],
    };

    sub new { return bless {}, shift }
}

my $o = Jopa->new;
$o->{bar} = 1;
is($o->foo, 1);

is($o->boo(12), 12);
is($o->baz(10), 10);

done_testing;
