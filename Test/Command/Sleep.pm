package Workflow::Test::Command::Sleep;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::Sleep {
    is => ['Workflow::Test::Command'],
    has => [
        seconds => { is => 'Integer', is_optional => 1, doc => 'length in seconds to sleep' },
    ],
};

operation_io Workflow::Test::Command::Sleep {
    input  => [ 'seconds' ],
    output => [],
    lsf_queue => 'short',
    lsf_resource => 'rusage[mem=4000] span[hosts=1]',
};

sub sub_command_sort_position { 10 }

sub help_brief {
    "Sleeps for the specified number of seconds";
}

sub help_synopsis {
    return <<"EOS"
    workflow-test sleep --seconds=5 
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

    1;
}
 
1;
