#!/gsc/bin/perl

use strict;
use POE;
use POE::Component::IKC::Client;

our $session = POE::Component::IKC::Client->spawn( 
#    ip=>'linusop15.gsc.wustl.edu', 
    port=>13425,
    name=>'Controller',
    on_connect=>\&__build
);

POE::Kernel->run();

sub __build {
    our $controller = POE::Session->create(
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                $kernel->alias_set("controller");
                $kernel->post('IKC','publish','controller',
                    [qw(got_plan_id got_instance_id complete error)]
                );
                
                $kernel->post(
                    'IKC','call',
                    'poe://UR/workflow/load', ['/gscuser/eclark/svn/perl_modules/Workflow/t/xml.d/00_basic.xml'],
                    'poe:got_plan_id'
                );
                print "Sent Load\n";
            },
            got_plan_id => sub {
                my ($kernel, $id) = @_[KERNEL, ARG0];
                print "Plan: $id\n";
exit;
                $_[KERNEL]->post(
                    'IKC','call',
                    'poe://UR/workflow/execute',
                    [ 
                        $id,
                        {
                            'model input string' => 'baz',
                            'sleep time' => 30 
                        },
                        'poe://Controller/controller/complete',
                        'poe://Controller/controller/error'
                    ],
                    'poe:got_instance_id'
                );  
            },
            got_instance_id => sub {
                my ($kernel, $id) = @_[KERNEL, ARG0];
                print "Instance: $id\n";
#                $kernel->post('IKC'=>'shutdown');
            },
            complete => sub {
                my ($kernel, $arg) = @_[KERNEL, ARG0];
                my ($id, $instance, $execution) = @$arg;

                print "Complete: $id\n";
                $kernel->post('IKC'=>'shutdown');
            },
            error => sub {
                my ($kernel, $arg) = @_[KERNEL, ARG0];
                my ($id, $instance, $execution) = @$arg;

                print "Error: $id\n";
                $kernel->post('IKC'=>'shutdown');
            }
        }
    );
}
