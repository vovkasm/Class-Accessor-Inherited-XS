package Class::Accessor::Inherited::XS;
use 5.010001;
use strict;
use warnings;

use Carp ();

our $VERSION = '0.11';
our $PREFIX  = '__cag_';

require XSLoader;
XSLoader::load('Class::Accessor::Inherited::XS', $VERSION);

my $REGISTERED_TYPES = {};
register_types(
    inherited => {installer => \&_mk_inherited_accessor},
    class     => {installer => \&_mk_class_accessor},
    varclass  => {installer => \&_mk_varclass_accessor},
);

sub import {
    my $pkg = shift;
    return unless scalar @_;

    my $class = caller;
    my %opts = ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;

    for my $type (keys %opts) {
        my $accessors = $opts{$type};
        my $installer = _type_installer($type);

        if (ref($accessors) eq 'HASH') {
            $installer->($class, $_, $accessors->{$_}) for keys %$accessors;

        } elsif (ref($accessors) eq 'ARRAY') {
            $installer->($class, $_, $_) for @$accessors;

        } else {
            Carp::confess("Can't understand format for '$type' accessors initializer");
        }
    }
}

sub mk_inherited_accessors {
    my $class = shift;
    mk_type_accessors($class, 'inherited', @_);
}

sub mk_class_accessors {
    my $class = shift;
    mk_type_accessors($class, 'class', @_);
}

sub mk_varclass_accessors {
    my $class = shift;
    mk_type_accessors($class, 'varclass', @_);
}

sub mk_type_accessors {
    my ($class, $type) = (shift, shift);

    my $installer = _type_installer($type);
    for my $entry (@_) {
        if (ref($entry) eq 'ARRAY') {
            $installer->($class, @$entry);
        } else {
            $installer->($class, $entry, $entry);
        }
    }
}

sub register_types {
    register_type(shift, shift) while scalar @_;
}

sub is_type_registered { exists $REGISTERED_TYPES->{$_[0]} }

sub register_type {
    my ($type, $args) = @_;

    if (exists $REGISTERED_TYPES->{$type}) {
        Carp::confess("Type '$type' has already been registered");
    }

    if (!exists $args->{installer}) {
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

sub _type_installer {
    my $type = shift;

    my $type_info = $REGISTERED_TYPES->{$type} or Carp::confess("Don't know how to install '$type' accessors");
    return $type_info->{installer};
}

sub _mk_inherited_accessor {
    my ($class, $name, $field) = @_;

    install_inherited_accessor("${class}::${name}", $field, $PREFIX.$field);
}

sub _mk_class_accessor {
    my ($class, $name) = @_;

    install_class_accessor("${class}::${name}", 0);
}

sub _mk_varclass_accessor {
    my ($class, $name) = @_;

    install_class_accessor("${class}::${name}", 1);
}

1;
__END__

=head1 NAME

Class::Accessor::Inherited::XS - Fast XS inherited and class accessors

=head1 SYNOPSIS

  #install accessors at compile time
  use Class::Accessor::Inherited::XS 
      inherited => [qw/foo bar/], # inherited accessors with key names equal to accessor names
      class     => [qw/baz/],     # an anonymous non-inherited accessor for __PACKAGE__
      varclass  => [qw/boo/],     # non-inherited accessor for __PACKAGE__,  aliased with 'our $boo' variable
  ;
  
  use Class::Accessor::Inherited::XS { # optional braces
      inherited => {
        bar => 'bar_key',
        foo => 'foo_key',
      },
      class     => ['baz'],
      varclass  => ['boo'],
  };
  
  #or in a Class::Accessor::Grouped-like fashion
  use parent 'Class::Accessor::Inherited::XS';
  
  __PACKAGE__->mk_inherited_accessors('foo', ['bar', 'bar_key']);
  __PACKAGE__->mk_class_accessors('baz');
  __PACKAGE__->mk_varclass_accessors('boo');

=head1 DESCRIPTION

This module provides a very fast implementation for 'inherited' accessors, that were introduced
by the L<Class::Accessor::Grouped> module. They give you a capability to override values set in
a parent class with values set in childs or object instances. Generated accessors are compatible with
L<Class::Accessor::Grouped> generated ones.

Since this module focuses primary on speed, it provides no means to have your own per-class
getters/setters logic (like overriding L<get_inherited>/L<set_inherited> in L<Class::Accessor::Grouped>),
but it allows you to register a single get/set callback per accessor type.

It also provides two types of non-inherited accessors, 'class' and 'varclass', which give you values
from a package they were defined in, even when called on objects. The difference between them is that
the 'varclass' internal storage is a package variable with the same name, while 'class' stores it's value
in an anonymous variable.

=head1 UTF-8

Starting with the perl 5.16.0, this module provides full support for UTF-8 (and binary) method names and hash
keys. But in previous perls you can't distinguish UTF-8 strings from bytes string in method names, so accessors
with UTF-8 names can end up getting a wrong value. You have been warned.

=head1 THREADS

Though highly discouraged, perl threads are supported by L<Class::Accessor::Inherited::XS>. You may
have accessors with same names pointing to different keys in different threads, etc. There are
no known conceptual leaks.

=head1 PERFORMANCE

L<Class::Accessor::Inherited::XS> is at least 10x times faster than L<Class::Accessor::Grouped>, depending
on your usage pattern. Accessing data from a parent in a large inheritance chain is still the worst case,
but even there L<Class::Accessor::Inherited::XS> beats L<Class::Accessor::Grouped> best-case.

Accessors with just an empty sub callback are ~3x times slower then normal ones, so use them only when you definitely need them.

Here are results from a benchmark run on perl 5.20.1 (see bench folder):

                        Rate pkg_gparent_cag pkg_cag obj_cag pkg_set_cag pkg_gparent_caixs obj_caix_cb pkg_caix pkg_set_caix obj_cxa obj_caix obj_direct
pkg_gparent_cag     228862/s              --    -76%    -80%        -82%              -92%        -96%     -97%         -98%    -99%     -99%       -99%
pkg_cag             942636/s            312%      --    -19%        -27%              -68%        -85%     -88%         -90%    -94%     -95%       -97%
obj_cag            1158463/s            406%     23%      --        -10%              -61%        -81%     -86%         -87%    -93%     -94%       -96%
pkg_set_cag        1287939/s            463%     37%     11%          --              -56%        -79%     -84%         -86%    -92%     -93%       -95%
pkg_gparent_caixs  2958598/s           1193%    214%    155%        130%                --        -52%     -64%         -68%    -82%     -84%       -89%
obj_caix_cb        6138858/s           2582%    551%    430%        377%              107%          --     -25%         -33%    -63%     -67%       -77%
pkg_caix           8159797/s           3465%    766%    604%        534%              176%         33%       --         -11%    -51%     -56%       -70%
pkg_set_caix       9162566/s           3904%    872%    691%        611%              210%         49%      12%           --    -45%     -51%       -66%
obj_cxa           16699964/s           7197%   1672%   1342%       1197%              464%        172%     105%          82%      --     -10%       -39%
obj_caix          18616018/s           8034%   1875%   1507%       1345%              529%        203%     128%         103%     11%       --       -32%
obj_direct        27185300/s          11778%   2784%   2247%       2011%              819%        343%     233%         197%     63%      46%         --

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

B<on_read> callback gets a single argument - from a normal 'inherited' accessor. It's return value is the new
accessor's return value (and is not stored anywhere).

B<on_write> callback gets two arguments - original args from the accessor's call. It's return value is saved
instead of the user's supplied one. Exceptions thrown from this callback will cancel store and leave the old value unchanged.

=head1 PROFILING WITH Devel::NYTProf

To perform it's task, L<Devel::NYTProf> hooks into the perl interpreter by replacing default behaviour for calling subroutines
on the opcode level. To squeeze last bits of performance, L<Class::Accessor::Inherited::XS> does the same, but separately
on each call site of its accessors. It turns out into CAIX favor - L<Devel::NYTProf> sees only first call to CAIX
accessor, but all subsequent ones become invisible to the subs profiler.

Note that the statement profiler still correctly accounts for the time spent on each line, you just don't see time spent in accessors'
calls separately. That's sometimes OK, sometimes not - you get profile with all possible optimizations on, but it's not easy to comprehend.

Since it's hard to detect L<Devel::NYTProf> (and any other module doing such magic) in a portable way (all hail Win32), there's
an %ENV switch available - you can set CAIXS_DISABLE_ENTERSUB to a true value to disable opcode optimization and get a full subs profile.

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
