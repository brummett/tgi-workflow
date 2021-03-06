package Workflow::Test::Command::Sleep;

use strict;
use warnings;

use Workflow;
use Command; 

class Workflow::Test::Command::Sleep {
    is => ['Workflow::Test::Command'],
    has_input => [
        seconds => { 
            is => 'Integer', 
            is_optional => 1, 
            doc => 'length in seconds to sleep'
        },
    ],
    has_param => [
        lsf_queue => {
            default_value => $ENV{WF_TEST_QUEUE},
        },
        lsf_resource => {
            default_value => 'rusage[mem=100] span[hosts=1]',
        }
    ]
};

sub resolve_resource_requirements {
    my ($class,$params) = @_;
    'rusage[mem=200] span[hosts=1]'
}

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

    return $self->seconds;
}
 
1;
