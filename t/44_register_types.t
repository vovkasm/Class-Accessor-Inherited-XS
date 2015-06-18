use strict;
use Test::More;
use Class::Accessor::Inherited::XS;

BEGIN {
    Class::Accessor::Inherited::XS::register_types(
        sone => {read_cb => sub {shift() + 1}},
        stwo => {read_cb => sub {shift() + 2}},
    );
}

use Class::Accessor::Inherited::XS
    sone => ['foo'],
    stwo => ['bar'],
;

is(main->foo, 1);
is(main->bar, 2);

done_testing;
