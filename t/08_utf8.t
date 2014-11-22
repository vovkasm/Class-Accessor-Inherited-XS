use Test::More;
use Class::Accessor::Inherited::XS;
use strict;
use utf8;

my $broken_utf8_subs = $[ <= 5.016; #see perl5160delta

my $utf8_key = "ц";
my $nonutf_key = "ц";
utf8::encode($nonutf_key);

my $utf8_acc = "тест";
my $nonutf_acc = "тест";
utf8::encode($nonutf_acc);

Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::$utf8_acc", $utf8_key);
Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::$nonutf_acc", $nonutf_key);
my $obj = bless {}, 'Jopa';

is $obj->тест, undef;
$obj->тест(42);
is($obj->тест , 42);
is($obj->{ц}, 42);
is($obj->$utf8_acc, 42);
is($obj->{$utf8_key}, 42);
is($obj->{$nonutf_key}, undef);

if (!$broken_utf8_subs) {
    is($obj->$nonutf_acc, undef);

    is($obj->$nonutf_acc(17), 17);
    is($obj->{$nonutf_key}, 17);

    is($obj->$utf8_acc, 42);
    is($obj->{$utf8_key}, 42);
}

done_testing;
