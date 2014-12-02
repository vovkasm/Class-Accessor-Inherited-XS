package Class::Accessor::Inherited::XS;
use 5.010001;
use strict;
use warnings;

our $VERSION = '0.03';

require XSLoader;
XSLoader::load('Class::Accessor::Inherited::XS', $VERSION);

{
    no strict 'refs';
    
    sub import {
        my $pkg = shift;
        return unless scalar @_;

        my $class = caller;
        my %opts = ref($_[0]) eq 'HASH' ? %{ $_[0] } : @_;

        if (my $inherited = $opts{inherited}) {
            if (ref($inherited) eq 'HASH') {
                mk_inherited_accessor($class, $_, $inherited->{$_}) for keys %$inherited;

            } elsif (ref($inherited) eq 'ARRAY') {
                mk_inherited_accessor($class, $_, $_) for @$inherited;

            } else {
                warn "Can't understand format for inherited accessors initializer for class $class";
            }
        }
    }

    sub mk_inherited_accessors {
        my $class = shift;

        for my $entry (@_) {
            if (ref($entry) eq 'ARRAY') {
                mk_inherited_accessor($class, @$entry);
            } else {
                mk_inherited_accessor($class, $entry, $entry);
            }
        }
    }

    sub mk_inherited_accessor {
        my($class, $name, $field) = @_;

        Class::Accessor::Inherited::XS::install_inherited_accessor("${class}::${name}", $field);
    }
}

1;
__END__

=head1 NAME

Class::Accessor::Inherited::XS - fast XS inherited accessors

=head1 SYNOPSIS

  #install accessors at compile time
  use Class::Accessor::Inherited::XS 
      inherited => [qw/foo bar/], # here key names are equal to accessor names
  ;
  
  use Class::Accessor::Inherited::XS {
      inherited => {
        bar => 'bar_key',
        foo => 'foo_key',
      },
  };
  
  #or in a Class::Accessor::Grouped-like fashion
  use parent 'Class::Accessor::Inherited::XS';
  __PACKAGE__->mk_inherited_accessors('foo', ['bar', 'bar_key']);

=head1 DESCRIPTION

This module provides very fast implementation for 'inherited' accessors, that were introduced 
in L<Class::Accessor::Grouped>. They give you capability to override values set in a parent
class with values set in childs or object instances. Generated accessors are compatible with
L<Class::Accessor::Grouped> generated ones.

Since this module focuses primary on speed, it provides no capability to have your own per-class
getters/setters logic (like overriding L<get_inherited>/L<set_inherited> in L<Class::Accessor::Grouped>).

=head1 UTF-8

Starting with perl 5.16.0, this module provides full support for UTF-8 method names and hash 
keys. Before that, you can't distinguish UTF-8 strings from bytes string in method names, only in 
hash keys. You have been warned.

=head1 THREADS

Though highly discouraged, perl threads are supported by L<Class::Accessor::Inherited::XS>. You may
have accessors with the same names pointing to differents keys in different threads, etc. There are 
no known conceptual leaks.

=head1 PERFORMANCE

L<Class::Accessor::Inherited::XS> is 5-12x times faster than L<Class::Accessor::Grouped>, depending
on your usage pattern. Accessing data from a parent in large inheritance chain is still the worst case,
but even there L<Class::Accessor::Inherited::XS> beats L<Class::Accessor::Grouped> best-case.

Here are results from the benchmark run on perl 5.20.1 (see bench folder):

                          Rate pkg_gparent_cag pkg_cag obj_cag pkg_set_cag pkg_gparent_caixs pkg_caix pkg_set_caix obj_caix obj_cxa obj_direct
  pkg_gparent_cag     238597/s              --    -76%    -80%        -82%              -91%     -97%         -97%     -98%    -99%       -99%
  pkg_cag             998731/s            319%      --    -18%        -25%              -64%     -86%         -86%     -92%    -94%       -95%
  obj_cag            1223277/s            413%     22%      --         -8%              -56%     -83%         -83%     -91%    -93%       -94%
  pkg_set_cag        1323322/s            455%     33%      8%          --              -52%     -82%         -82%     -90%    -92%       -93%
  pkg_gparent_caixs  2752510/s           1054%    176%    125%        108%                --     -62%         -63%     -79%    -84%       -86%
  pkg_caix           7281773/s           2952%    629%    495%        450%              165%       --          -1%     -44%    -56%       -64%
  pkg_set_caix       7349827/s           2980%    636%    501%        455%              167%       1%           --     -44%    -56%       -64%
  obj_caix          13008746/s           5352%   1203%    963%        883%              373%      79%          77%       --    -22%       -36%
  obj_cxa           16733631/s           6913%   1575%   1268%       1165%              508%     130%         128%      29%      --       -17%
  obj_direct        20201922/s           8367%   1923%   1551%       1427%              634%     177%         175%      55%     21%         --

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
