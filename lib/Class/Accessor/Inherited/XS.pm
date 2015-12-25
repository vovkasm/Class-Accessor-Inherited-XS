package Class::Accessor::Inherited::XS;
use 5.010001;
use strict;
use warnings;

use Carp ();

our $VERSION = '0.19';
our $PREFIX  = '__cag_';

require XSLoader;
XSLoader::load('Class::Accessor::Inherited::XS', $VERSION);

my $REGISTERED_TYPES = {};
register_types(
    inherited   => {installer => \&_mk_inherited_accessor},
    class       => {installer => \&_mk_class_accessor},
    varclass    => {installer => \&_mk_varclass_accessor},
    object      => {installer => \&_mk_object_accessor},
    constructor => {installer => \&_mk_constructor},
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

        } elsif (!ref($accessors)) {
            $installer->($class, $accessors, $accessors);

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

sub mk_object_accessors {
    my $class = shift;
    mk_type_accessors($class, 'object', @_);
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

sub _mk_object_accessor {
    my ($class, $name, $field) = @_;

    install_object_accessor("${class}::${name}", $field);
}

sub _mk_constructor {
    my ($class, $name) = @_;

    install_constructor("${class}::${name}");
}

1;
__END__

=head1 NAME

Class::Accessor::Inherited::XS - Fast XS inherited, object and class accessors

=head1 SYNOPSIS

  #install accessors at compile time
  use Class::Accessor::Inherited::XS 
      inherited => [qw/foo bar/], # inherited accessors with key names equal to accessor names
      object    => 'fuz',         # non-inherited object accessor with key name equal to accessor name
      varclass  => 'boo',         # non-inherited accessor for __PACKAGE__,  aliased with '$__PACKAGE__::boo' variable
      class     => 'baz',         # non-inherited anonymous accessor for __PACKAGE__
      constructor => 'new',       # object constructor
  ;
  
  use Class::Accessor::Inherited::XS { # optional braces
      inherited => {
        bar => 'bar_key',
        foo => 'foo_key',
      },
      object    => {fuz => 'fuz_key'},
      class     => ['baz'],
      varclass  => ['boo'],
  };

  #or in a Class::Accessor::Grouped-like fashion
  use parent 'Class::Accessor::Inherited::XS';

  __PACKAGE__->mk_inherited_accessors('foo', ['bar', 'bar_key']);
  __PACKAGE__->mk_class_accessors('baz');
  __PACKAGE__->mk_varclass_accessors('boo');
  __PACKAGE__->mk_object_accessors('fuz');

=head1 DESCRIPTION

This module provides a very fast implementation for a wide range of accessor types.

B<inherited> accessors were introduced in the L<Class::Accessor::Grouped> module. They allow you to override
values set in a parent class with values set in childs or object instances. Generated accessors are compatible with
the L<Class::Accessor::Grouped> generated ones.

Since this module focuses primary on speed, it provides no means to have your own per-class
getters/setters logic (like overriding L<Class::Accessor::Grouped/get_inherited> / L<Class::Accessor::Grouped/set_inherited>),
but it allows you to create new inherited accesor types with an attached callback.

B<class> and B<varclass> accessors are non-inherited package accessors - they return values from the class
they were defined in, even when called on objects or child classes. The difference between them is that
the B<varclass> internal storage is a package variable with the same name, while B<class> stores it's value
in an anonymous variable.

B<object> accessors provides plain simple hash key access.

B<constructor> can create objects either from a list or from a single hashref. Note that if you pass
a hash reference, it becomes blessed too. If that's not what you want, pass a dereferenced copy.

    __PACKAGE__->new(foo => 1, bar => 2); # values are copied
    __PACKAGE__->new(\%args);             # values are not copied, much faster
    $obj->new(foo => 1, bar => 2);        # values are copied, but nothing is taken from $obj
    $obj->new(\%args);                    # values are not copied, and nothing is taken from $obj

=head1 UTF-8 AND BINARY SAFETY

Starting with the perl 5.16.0, this module provides full support for UTF-8 method names and hash keys.
But on older perls you can't distinguish UTF-8 strings from bytes string in method names, so accessors
with UTF-8 names can end up getting a wrong value. You have been warned.

Also, starting from 5.16.0 accessor installation is binary safe, except for the Windows platform.
This module croaks on attempts to install binary accessors on unsupported platforms.

=head1 THREADS

Though highly discouraged, perl threads are supported by L<Class::Accessor::Inherited::XS>. You can
have accessors with same names pointing to different keys in different threads, etc. There are
no known conceptual leaks.

=head1 PERFORMANCE

L<Class::Accessor::Inherited::XS> is at least 10x times faster than L<Class::Accessor::Grouped>, depending
on your usage pattern. Accessing data from a parent in a large inheritance chain is still the worst case,
but even there L<Class::Accessor::Inherited::XS> beats L<Class::Accessor::Grouped> best-case. Object accessors
are event faster than L<Class::XSAccessor> ones.

Accessors with just an empty sub callback are ~3x times slower then normal ones, so use them only when absolutely necessary.

Here are results from a benchmark run on perl 5.20.1 (see bench folder):

                       Rate pkg_gparent_cag pkg_cag obj_cag pkg_gparent_caix obj_caix_cb pkg_set_caix pkg_caix obj_cxa obj_caix obj_direct class_caix
pkg_gparent_cag    255778/s              --    -77%    -82%             -92%        -97%         -97%     -98%    -98%     -99%       -99%       -99%
pkg_cag           1092262/s            327%      --    -22%             -68%        -85%         -89%     -89%    -94%     -95%       -96%       -97%
obj_cag           1409030/s            451%     29%      --             -59%        -81%         -86%     -86%    -92%     -93%       -95%       -96%
pkg_gparent_caix  3401161/s           1230%    211%    141%               --        -54%         -65%     -67%    -80%     -83%       -88%       -90%
obj_caix_cb       7384333/s           2787%    576%    424%             117%          --         -24%     -29%    -57%     -63%       -73%       -78%
pkg_set_caix      9771705/s           3720%    795%    594%             187%         32%           --      -6%    -43%     -52%       -65%       -72%
pkg_caix         10386837/s           3961%    851%    637%             205%         41%           6%       --    -39%     -49%       -62%       -70%
obj_cxa          17049394/s           6566%   1461%   1110%             401%        131%          74%      64%      --     -16%       -38%       -50%
obj_caix         20176934/s           7788%   1747%   1332%             493%        173%         106%      94%     18%       --       -27%       -41%
obj_direct       27568192/s          10678%   2424%   1857%             711%        273%         182%     165%     62%      37%         --       -20%
class_caix       34345065/s          13328%   3044%   2337%             910%        365%         251%     231%    101%      70%        25%         --


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

    #or in a Class::Accessor::Grouped-like fashion
    __PACKAGE__->mk_type_accessors(inherited_cb => 'foo', 'bar');

You can register new inherited accessor types with associated read/write callbacks. Unlike
L<Class::Accessor::Grouped>, only a single callback can be set for a type, without per-class
B<get_$type>/B<set_$type> lookups.

B<on_read> callback receives a single argument - return value from the underlying B<inherited> accessor. It's result
is the new accessor's return value (and it isn't stored anywhere).

B<on_write> callback receives original accessor's arguments, and it's return value is stored as usual.
Exceptions thrown from this callback will cancel store and will leave the old value unchanged.

=head1 PROFILING WITH Devel::NYTProf

To perform it's task, L<Devel::NYTProf> hooks into the perl interpreter by replacing default behaviour for subroutine calls
at the opcode level. To squeeze last bits of performance, L<Class::Accessor::Inherited::XS> does the same, but separately
on each call site of its accessors. It turns out into CAIX favor - L<Devel::NYTProf> sees only the first call to CAIX
accessor, but all subsequent ones become invisible to the subs profiler.

Note that the statement profiler still correctly accounts for the time spent on each line, you just don't see time spent in accessors'
calls separately. That's sometimes OK, sometimes not - you get profile with all possible optimizations on, but it's not easy to comprehend.

Since it's hard to detect L<Devel::NYTProf> (and any other module doing such magic) in a portable way (all hail Win32), there's
an %ENV switch available - you can set CAIXS_DISABLE_ENTERSUB to a true value to disable opcode optimizations and get a full subs profile.

=head1 CAVEATS

When using B<varclass> accessors, do not clear or alias C<*__PACKAGE__::accessor> glob - that will break aliasing between accessor storage
and $__PACKAGE__::accessor variable. While the stored value is still accessible through accessor, it effectively becomes a B<class> one.

=head1 SEE ALSO

=over

=item * L<Class::Accessor::Grouped>

=item * L<Class::XSAccessor>

=back

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Vladimir Timofeev

Copyright (C) 2014-2015 by Sergey Aleynikov

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.

=cut
