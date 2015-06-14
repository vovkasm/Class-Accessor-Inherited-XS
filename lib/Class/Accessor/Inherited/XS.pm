package Class::Accessor::Inherited::XS;
use 5.010001;
use strict;
use warnings;

use Carp ();

our $VERSION = '0.08';
our $PREFIX  = '__cag_';

require XSLoader;
XSLoader::load('Class::Accessor::Inherited::XS', $VERSION);

my $REGISTERED_TYPES = {};
register_type(inherited => {no_cb => 1});

sub import {
    my $pkg = shift;
    return unless scalar @_;

    my $class = caller;
    my %opts = ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;

    for my $type (keys %opts) {
        my $type_info = $REGISTERED_TYPES->{$type};

        if (!defined $type_info) {
            Carp::confess("Don't know how to install '$type' accessors");
        }

        my $accessors = $opts{$type};
        if (ref($accessors) eq 'HASH') {
            $type_info->{installer}->($class, $_, $accessors->{$_}) for keys %$accessors;

        } elsif (ref($accessors) eq 'ARRAY') {
            $type_info->{installer}->($class, $_, $_) for @$accessors;

        } else {
            Carp::confess("Can't understand format for '$type' accessors initializer");
        }
    }
}

sub mk_inherited_accessors {
    my $class = shift;

    for my $entry (@_) {
        if (ref($entry) eq 'ARRAY') {
            _mk_inherited_accessor($class, @$entry);
        } else {
            _mk_inherited_accessor($class, $entry, $entry);
        }
    }
}

sub register_type {
    my ($type, $args) = @_;

    if (exists $REGISTERED_TYPES->{$type}) {
        Carp::confess("Type '$type' has already been registered");
    }

    if (exists $args->{no_cb}) {
        $args->{installer} = \&_mk_inherited_accessor;

    } else {
        $args->{installer} = sub {
            my ($class, $name, $field) = @_;
            install_inherited_cb_accessor("${class}::${name}", $field, $PREFIX.$field, $args->{read_cb}, $args->{write_cb});
        };
    }

    $REGISTERED_TYPES->{$type} = $args;
}

#
#   Functions below are NOT part of the public API
#

sub _mk_inherited_accessor {
    my ($class, $name, $field) = @_;

    install_inherited_accessor("${class}::${name}", $field, $PREFIX.$field);
}

1;
__END__

=head1 NAME

Class::Accessor::Inherited::XS - Fast XS inherited accessors

=head1 SYNOPSIS

  #install accessors at compile time
  use Class::Accessor::Inherited::XS 
      inherited => [qw/foo bar/], # here key names are equal to accessor names
  ;
  
  use Class::Accessor::Inherited::XS { # optional braces
      inherited => {
        bar => 'bar_key',
        foo => 'foo_key',
      },
  };
  
  #or in the Class::Accessor::Grouped-like fashion
  use parent 'Class::Accessor::Inherited::XS';
  __PACKAGE__->mk_inherited_accessors('foo', ['bar', 'bar_key']);

=head1 DESCRIPTION

This module provides a very fast implementation for 'inherited' accessors, that were introduced
by the L<Class::Accessor::Grouped> module. They give you a capability to override values set in
a parent class with values set in childs or object instances. Generated accessors are compatible with
L<Class::Accessor::Grouped> generated ones.

Since this module focuses primary on speed, it provides no capability to have your own per-class
getters/setters logic (like overriding L<get_inherited>/L<set_inherited> in L<Class::Accessor::Grouped>),
but it gives you an ability to register a single get/set callback for you own accessor types.

=head1 UTF-8

Starting with the perl 5.16.0, this module provides full support for UTF-8 method names and hash 
keys. Before that, you can't distinguish UTF-8 strings from bytes string in method names, only in 
hash keys. You have been warned.

=head1 THREADS

Though highly discouraged, perl threads are supported by L<Class::Accessor::Inherited::XS>. You may
have accessors with same names pointing to different keys in different threads, etc. There are
no known conceptual leaks.

=head1 PERFORMANCE

L<Class::Accessor::Inherited::XS> is at least 10x times faster than L<Class::Accessor::Grouped>, depending
on your usage pattern. Accessing data from a parent in a large inheritance chain is still the worst case,
but even there L<Class::Accessor::Inherited::XS> beats L<Class::Accessor::Grouped> best-case.

Here are results from a benchmark run on perl 5.20.1 (see bench folder):

                          Rate pkg_gparent_cag pkg_cag obj_cag pkg_set_cag pkg_gparent_caixs pkg_caix pkg_set_caix obj_cxa obj_caix obj_direct
  pkg_gparent_cag     237444/s              --    -77%    -79%        -82%              -92%     -97%         -97%    -99%     -99%       -99%
  pkg_cag            1013067/s            327%      --    -11%        -21%              -66%     -88%         -89%    -94%     -95%       -96%
  obj_cag            1137400/s            379%     12%      --        -12%              -62%     -87%         -87%    -93%     -94%       -95%
  pkg_set_cag        1286220/s            442%     27%     13%          --              -57%     -85%         -86%    -92%     -93%       -95%
  pkg_gparent_caixs  2995865/s           1162%    196%    163%        133%                --     -65%         -66%    -82%     -84%       -88%
  pkg_caix           8602691/s           3523%    749%    656%        569%              187%       --          -3%    -49%     -54%       -65%
  pkg_set_caix       8907800/s           3652%    779%    683%        593%              197%       4%           --    -47%     -52%       -64%
  obj_cxa           16781840/s           6968%   1557%   1375%       1205%              460%      95%          88%      --     -10%       -32%
  obj_caix          18642286/s           7751%   1740%   1539%       1349%              522%     117%         109%     11%       --       -25%
  obj_direct        24807382/s          10348%   2349%   2081%       1829%              728%     188%         178%     48%      33%         --

=head1 EXTENDING

    package MyAccessor;
    # 'register_type' isn't exported
    Class::Accessor::Inherited::XS::register_type(
        inherited_cb => {on_read => sub {}, on_write => sub{}},
    );

    package MyClass;
    use MyAccessor;
    use Class::Accessor::Inherited::XS {
        inherited    => ['foo'],
        inherited_cb => ['bar'],
    };

You can register new inherited accessor types with associated read/write callbacks. They're still
'inherited', but you can modify return values. Those new types can be installed using
the L<Class::Accessor::Inherited::XS> import() call. Unlike L<Class::Accessor::Grouped>,
here's a single callback per accessor type, without any inheritance lookups for get_*/set_* functions.

B<on_read> callback gets a single argument - from a normal 'inherited' accessor. It's return value is a new
accessor's return value (and is not stored anywhere).

B<on_write> callback gets two arguments - original args from the accessor call. It's return value is saved
instead of the user's supplied one.

=head1 PROFILING WITH Devel::NYTProf

To perform it's task, L<Devel::NYTProf> hooks into the perl interpreter by replacing default behaviour for calling subroutines
on the opcode level. To squeeze last bits of performance, L<Class::Accessor::Inherited::XS> does the same, but separately
on each call site of its accessors. It turns out into CAIX favor - L<Devel::NYTProf> sees only first call to CAIX
accessor, but all subsequent ones become invisible to the subs profiler.

Note that statement profiler still correctly accounts time spent on a line, you just don't see time spent in accessors'
calls separately. That's sometimes OK, sometimes not - you get profile with all possible optimizations on, but it's hard for understanding.

Since it's hard to detect L<Devel::NYTProf> (and any other module doing such magic) in a portable way (all hail Win32), there's
an %ENV switch available - you can set CAIXS_DISABLE_ENTERSUB to a true value to disable call site optimization and get full subs profile.

=head1 SEE ALSO

=over

=item * L<Class::Accessor::Grouped>

=item * L<Class::XSAccessor>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Vladimir Timofeev

Copyright (C) 2014 by Sergey Aleynikov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut
