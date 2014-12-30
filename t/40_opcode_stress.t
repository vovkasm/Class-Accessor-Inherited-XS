use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;
    use strict;

    sub new { return bless {}, shift }

    Jopa->mk_inherited_accessors(qw/a b/);

    sub foo { 42 }

    1;
}

my $o = new Jopa;
$o->{a} = 1;

for (1..3) {
    is($o->a, 1);
}

for (1..3) {
    is($o->a(6), 6);
}

$o->{b} = 12;
my @res = (6,12,12,12,6,12,6);
for (qw/a b b b a b a/) {
    is($o->$_, shift @res);
}

@res = (12,6,42,12,6,42,6);
for (qw/b a foo b a foo a/) {
    is($o->$_, shift @res);
}

@res = (42,12,42,6,12,42);
for (qw/foo b foo a b foo/) {
    is($o->$_, shift @res);
}

done_testing;
