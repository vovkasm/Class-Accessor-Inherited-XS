use Test::More;
use Class::Accessor::Inherited::XS;
use strict;
no strict 'refs';
use utf8;

my $broken_utf8_subs = ($] < 5.016); #see perl5160delta

my $utf8_key = "ц";
my $nonutf_key = "ц";
utf8::encode($nonutf_key);

my $utf8_acc = "тест";
my $nonutf_acc = "тест";
utf8::encode($nonutf_acc);

Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::$utf8_acc", $utf8_key, "__cag_$utf8_key");
Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::$nonutf_acc", $nonutf_key, "__cag_$nonutf_key");

if ($broken_utf8_subs) {
    is Jopa->тест, undef;
    Jopa->тест(42);
    is(Jopa->тест , 42);

    is(Jopa->$utf8_acc, 42);
    is(Jopa->$nonutf_acc, 42);

    done_testing;
    exit;
}

{
    is Jopa->тест, undef;
    Jopa->тест(42);
    is(Jopa->тест , 42);
    is(${"Jopa::__cag_ц"}, 42);
    is(Jopa->$utf8_acc, 42);
    is(${"Jopa::__cag_$utf8_key"}, 42);
    is(${"Jopa::__cag_$nonutf_key"}, undef);

    is(Jopa->$nonutf_acc, undef);

    is(Jopa->$nonutf_acc(17), 17);
    is(${"Jopa::__cag_$nonutf_key"}, 17);

    is(Jopa->$utf8_acc, 42);
    is(${"Jopa::__cag_$utf8_key"}, 42);
}

done_testing;
