use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };
use Test::More HAS_LEAKTRACE ? ('no_plan') : (skip_all => 'requires Test::LeakTrace');
use Test::LeakTrace;

use Class::Accessor::Inherited::XS {
    constructor => 'new',
    accessors   => 'acc',
};

my $foo = __PACKAGE__->new;
$foo->acc(__PACKAGE__->new);
$foo->acc->acc(12);

no_leaks_ok {
    for (1..10) {
        my $t = $foo->acc;
    }
};

no_leaks_ok {
    my $t = $foo->acc for (1..10);
};

is $foo->acc->acc, 12;
