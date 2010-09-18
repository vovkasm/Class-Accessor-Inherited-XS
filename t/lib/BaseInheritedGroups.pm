package BaseInheritedGroups;
use strict;
use warnings;
use base 'AccessorInstaller';

__PACKAGE__->mk_group_accessors(inherited => 'basefield', 'undefined', ['refacc','reffield']);

sub new {
    return bless {}, shift;
};

1;
