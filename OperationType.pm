
package Workflow::OperationType;

use strict;
use warnings;

class Workflow::OperationType {
    is_abstract => 1,
    has => [
        stay_in_process => { 
            is => 'Boolean',
            is_optional => 1,
            is_class_wide => 1,
            is_constant => 1,
            is_abstract => 1,
            doc => 'Forces serial executor'
        },
        input_properties => { 
            is => 'ARRAY', 
            doc => 'list of input properties' 
        },
        output_properties => { 
            is => 'ARRAY', 
            doc => 'list of output properties' 
        }
    ]
};

sub create_from_xml_simple_structure {
    my ($my_class, $struct) = @_;

    # delegate to the right one

    my $self;
    my $class = delete $struct->{typeClass};
    if (defined $class && $my_class ne $class && $class->can('create_from_xml_simple_structure')) {

        $self = $class->create_from_xml_simple_structure($struct);

        unless ($self->input_properties) {
            $self->input_properties($struct->{inputproperty});
        }
        unless ($self->output_properties) {
            $self->output_properties([@{$struct->{outputproperty}},'result']);
        }
    } else {
        $self = $my_class->create(
            input_properties => $struct->{inputproperty},
            output_properties => $struct->{outputproperty}
        );
    }
    return $self;
}

sub as_xml_simple_structure {
    my $self = shift;

    my $struct = {};

    if (ref($self) ne __PACKAGE__) {
        $struct->{typeClass} = ref($self);
    }

    $struct->{inputproperty} = $self->input_properties;
    $struct->{outputproperty} = $self->output_properties;

    return $struct;
}

# successful noop by default, should be overridden
sub execute {

    {};
}

1;
