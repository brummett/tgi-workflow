
package Cord::Executor;

use strict;

class Cord::Executor {
    is => 'UR::Singleton',
    is_transactional => 0,
    is_abstract => 1
};

sub exception {
    my ($self,$instance,$message) = @_;
    
    
    die ($message);
}

sub wait {
    1;
}

1;
