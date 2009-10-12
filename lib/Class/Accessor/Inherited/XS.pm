package Class::Accessor::Inherited::XS;

use 5.010001;
use strict;
use warnings;

use Carp ();
use Scalar::Util ();
use mro;

our $VERSION = '0.01';

sub pp_get_inherited {
    my $class;

    if (Scalar::Util::blessed $_[0]) {
        my $reftype = Scalar::Util::reftype $_[0];
        $class = ref $_[0];

        if ($reftype eq 'HASH' && exists $_[0]->{$_[1]}) {
            return $_[0]->{$_[1]};
        } elsif ($reftype ne 'HASH') {
            Carp::croak('Cannot get inherited value on an object instance that is not hash-based');
        };
    } else {
        $class = $_[0];
    };

    no strict 'refs';
    no warnings qw/uninitialized/;
    return ${$class.'::__cag_'.$_[1]} if defined(${$class.'::__cag_'.$_[1]});

    # we need to be smarter about recalculation, as @ISA (thus supers) can very well change in-flight
    my $pkg_gen = mro::get_pkg_gen ($class);
    if ( ${$class.'::__cag_pkg_gen'} != $pkg_gen ) {
        @{$class.'::__cag_supers'} = $_[0]->get_super_paths;
        ${$class.'::__cag_pkg_gen'} = $pkg_gen;
    };

    foreach (@{$class.'::__cag_supers'}) {
        return ${$_.'::__cag_'.$_[1]} if defined(${$_.'::__cag_'.$_[1]});
    };

    return undef;
}

sub set_inherited {
    if (Scalar::Util::blessed $_[0]) {
        if (Scalar::Util::reftype $_[0] eq 'HASH') {
            return $_[0]->{$_[1]} = $_[2];
        } else {
            Carp::croak('Cannot set inherited value on an object instance that is not hash-based');
        };
    } else {
        no strict 'refs';

        return ${$_[0].'::__cag_'.$_[1]} = $_[2];
    };
}

sub get_super_paths {
    my $class = Scalar::Util::blessed $_[0] || $_[0];

    return @{mro::get_linear_isa($class)};
}

require XSLoader;
XSLoader::load('Class::Accessor::Inherited::XS', $VERSION);

# Preloaded methods go here.

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Class::Accessor::Inherited::XS - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Class::Accessor::Inherited::XS;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Class::Accessor::Inherited::XS, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Vladimir Timofeev, E<lt>vovkasm@homeE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2009 by Vladimir Timofeev

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
