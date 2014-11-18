use constant HAS_LEAKTRACE => eval{ require Test::LeakTrace };
use Test::More HAS_LEAKTRACE ? (no_plan) : (skip_all => 'require Test::LeakTrace');
use Test::LeakTrace;
use Class::Accessor::Inherited::XS;

Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::foo", "foo");

no_leaks_ok {
    for (1..100) {
        Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::foo", "foo");
    }
};

no_leaks_ok {
    for (1..100) {
        Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::foo_$_", "foo_$_");
        undef *{"Jopa::foo_$_"};
    }
};

my $obj = bless {}, 'Jopa';
no_leaks_ok {
    $obj->foo;
};

$obj->{foo} = 42;
no_leaks_ok {
    $obj->foo;
};

no_leaks_ok {
    my $z = \($obj->foo(24));
};

no_leaks_ok {
    $obj->foo(24);
};

no_leaks_ok {
    Jopa->foo;
};

no_leaks_ok {
    Jopa->foo('bar');
};

Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::foobaz", "foobaz");

no_leaks_ok {
    Jopa->foobaz('bar');
};

no_leaks_ok {
    Jopa->foobaz;
};
