use strict;
use Test::More;
use Class::Accessor::Inherited::XS;

my $type;
my $counter = 0;

sub wrt { is my $foo = $_[-1], $type; ++$counter; $_[1] }
sub rdt { is my $foo = $_[-1], $type; ++$counter; $_[0] }

BEGIN {
    Class::Accessor::Inherited::XS::register_type(
        nmd => {write_cb => \&wrt, read_cb => \&rdt}
    );
}

use Class::Accessor::Inherited::XS
    nmd       => ['bar', 'baz'],
;

my $obj = bless {};

for my $arg (1, 2, 100, 500) {
    {
        $type = 'bar';

        my $blah = $obj->bar(($arg) x $arg);
        is $blah, $arg;

        is $obj->bar, $arg;
        is $obj->$type, $arg;
    }

    {
        $type = 'baz';

        my $blah = $obj->baz(($arg) x $arg);
        is $blah, $arg;

        is $obj->baz, $arg;
        is $obj->$type, $arg;
    }
}

is $counter, 4 * 2 * 3; # arg - type - w/r/r
is(Class::Accessor::Inherited::XS::Debug::unstolen_count(), 0);

done_testing;
