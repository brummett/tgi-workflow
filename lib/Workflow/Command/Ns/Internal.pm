package Cord::Command::Ns::Internal;

use strict;
use warnings;

use Cord;
use Command;

class Cord::Command::Ns::Internal {
    is => 'Command',
    doc => 'Internal commands for running serverless workflows'
};

sub sub_command_sort_position { 99 }

1;
