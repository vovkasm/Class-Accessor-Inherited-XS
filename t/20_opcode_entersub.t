use Test::More;
use Class::Accessor::Inherited::XS;
use strict;

{
    package Jopa;
    use base qw/Class::Accessor::Inherited::XS/;

    sub new { return bless {}, shift }
    sub foo { 42 }

    Jopa->mk_inherited_accessors(qw/a b/);
}

my $o = new Jopa;
$o->{a} = 1;

my $cref = $o->can('a');

for (1..3) {
    is($cref->($o), 1);
}

for (1..3) {
    is($cref->($o, 6), 6);
}

$o->{b} = 12;
my @res = (6,12,12,12,6,12,6);
for (qw/a b b b a b a/) {
    $cref = $o->can($_);
    is($cref->($o), shift @res);
}

@res = (12,6,42,12,6,42,6);
for (qw/b a foo b a foo a/) {
    $cref = $o->can($_);
    is($cref->($o), shift @res);
}

@res = (42,12,42,6,12,42);
for (qw/foo b foo a b foo/) {
    $cref = $o->can($_);
    is($cref->($o), shift @res);
}

done_testing;
