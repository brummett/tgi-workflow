
package Workflow::Server::Worker;

use strict;
use POE;
use POE::Component::IKC::Client;
use Workflow ();

sub start {
    my ($class, $host, $port) = @_;

    $host ||= 'localhost';
    $port ||= 13424;

    our $client = POE::Component::IKC::Client->spawn( 
        ip=>$host, 
        port=>$port,
        name=>'Worker',
        on_connect=>\&__build
    );

    $Storable::forgive_me=1;
    
    POE::Kernel->run();
}

sub __build {
    our $worker = POE::Session->create(
        inline_states => {
            _start => sub { 
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                $kernel->alias_set("worker");
                $kernel->call('IKC','publish','worker',[qw(execute)]);

                $kernel->yield('get_work');
            },
            execute => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($instance, $type, $input) = @$arg;
                
                $kernel->alarm_remove_all;

                my $status = 'done';
                my $output;
                my $error_string;
                eval {
                    $output = $type->execute(%{ $instance->input }, %$input);
                };
                if ($@) {
                    print STDERR "Command module died.\n";
                    print STDERR $@;
                    $error_string = $@;
                    $status = 'crashed';
                }

                my $kernel_name = $kernel->ID;

                $kernel->post('IKC','post','poe://Hub/dispatch/end_work',[ $kernel_name, $instance->id, $status, $output, $error_string ]);
                $kernel->yield('disconnect');
            },
            disconnect => sub {
                $_[KERNEL]->post('IKC','shutdown');
            },
            get_work => sub {
                my ($kernel) = @_[KERNEL];

                my $kernel_name = $kernel->ID;

                $kernel->post(
                    'IKC','post','poe://Hub/dispatch/get_work',["poe://$kernel_name/worker/execute", $kernel_name]
                );
            }
        }
    );
}

1;