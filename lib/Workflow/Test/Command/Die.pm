package Workflow::Test::Command::Die;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::Die {
    is => ['Workflow::Test::Command'],
    has_input => [
        seconds => { 
            is => 'Integer', 
            is_optional => 1, 
            doc => 'length in seconds to sleep before dying'
        }
    ],
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "dies after the specified number of seconds";
}

sub help_synopsis {
    return <<"EOS"
    workflow-test die --seconds=5 
EOS
}

sub help_detail {
    return <<"EOS"
This command is used for testing purposes.
EOS
}

sub execute {
    my $self = shift;
   
    if ($self->seconds) {
        sleep $self->seconds;
    }
   
    if (defined $::DONT_DIE) {
        warn "death overridden by global\n"; 
    } else {
        die "death by test case";
    }

    1;
}
 
1;
