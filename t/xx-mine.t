use strict;
use Test::More;

use Class::Accessor::Inherited::XS {
    object      => 'foo',
    constructor => 'new',
};

ok (eval { __PACKAGE__->new(foo => 'v'); 1 }, "when required key is supplied, all ok");
is (eval { __PACKAGE__->new(k => 'v'); 1 }, undef, "when required key is missing, die");
like $@, qr/key 'foo' is required/;

done_testing;
