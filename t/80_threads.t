use strict;
our $have_threads;
BEGIN {
    $have_threads = eval{require threads; threads->create(sub{return 1})->join};
}
use Test::More ($have_threads) ? ('no_plan') : (skip_all => 'for threaded perls only');

package Test;

use parent qw/Class::Accessor::Inherited::XS/;
__PACKAGE__->mk_inherited_accessor(qw/foo foo/);

package main;
my @threads;

Test->foo(3);

sub same_name {
    my $val = $_;
    return sub {
        die if Test->foo($val) != $val;
        die if Test->foo != $val;
    };
}

sub same_name_recreate {
    my $val = $_;
    return sub {
        Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::foo", "bar", "__cag_bar");
        die if Jopa->foo($val) != $val;
        die if $Jopa::__cag_bar != $val;
        die if Jopa->foo != $val;

        no strict 'refs';
        undef *{"Jopa::foo"};
    };
}

sub diff_name_over {
    my $val = $_;
    return sub {
        Class::Accessor::Inherited::XS::install_inherited_accessor("Jopa::foo", "bar_$val", "__cag_bar_$val");
        die if Jopa->foo($val) != $val;
        {
            no strict 'refs';
            die if ${"Jopa::__cag_bar_$val"} != $val;
        }
        die if Jopa->foo != $val;
    };
}

sub run_threaded {
    my $generator = shift;

    for my $code (map $generator->(), qw/17 42 80/) {
        push @threads, threads->create(sub {
            $code->() for (1..100_000);
        });
    }

    $_->join for splice @threads;

    ok 1;
}

run_threaded(\&same_name);
is(Test->foo, 3); #still in main thr

run_threaded(\&same_name_recreate);
run_threaded(\&diff_name_over);
