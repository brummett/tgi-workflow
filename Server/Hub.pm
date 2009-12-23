
package Workflow::Server::Hub;

use strict;
use base 'Workflow::Server';
use POE qw(Component::IKC::Server Wheel::FollowTail);

our $port_number = 13424;

use Workflow ();
use Sys::Hostname;
use Text::CSV;

my %JOB_STAT = (
    NULL => 0x00,
    PEND => 0x01,
    PSUSP => 0x02,
    RUN => 0x04,
    SSUSP => 0x08,
    USUSP => 0x10,
    EXIT => 0x20,
    DONE => 0x40,
    PDONE => 0x80,
    PERR => 0x100,
    WAIT => 0x200,
    UNKWN => 0x10000
);

BEGIN {
    if (defined $ENV{WF_TRACE_HUB}) {
        eval 'sub evTRACE () { 1 }';
    } else {
        eval 'sub evTRACE () { 0 }';
    }
};

sub setup {
    my $class = shift;
    my %args = @_;
    
    our $server = POE::Component::IKC::Server->spawn(
        port => $port_number, name => 'Hub'
    );

    our $printer = POE::Session->create(
        inline_states => {
            _start => sub { 
                my ($kernel) = @_[KERNEL];
                $kernel->alias_set("printer");
                $kernel->call('IKC','publish','printer',[qw(stdout stderr)]);
            },
            stdout => sub {
                my ($arg) = @_[ARG0];
                
                print "$arg\n";
            },
            stderr => sub {
                my ($arg) = @_[ARG0];
                
                print STDERR "$arg\n";
            }
        }
    );
    
    our $watchdog = POE::Session->create(
        heap => {
            watchlist => POE::Queue::Array->new()
        },
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "watchdog _start\n";

                $kernel->alias_set("watchdog");
                $kernel->call('IKC','publish','watchdog',[qw(create delete)]);
            },
            _stop => sub {
                evTRACE and print "watchdog _stop\n";
            },
            create => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id,$duration) = @$arg;
                
                evTRACE and print "watchdog create $dispatch_id $duration\n";
                
                my $start_time = time;
                $heap->{watchlist}->enqueue($start_time + $duration, $dispatch_id);
                
                $heap->{alarm_id} = $kernel->alarm(check => $heap->{watchlist}->get_next_priority);
                return 1;
            },
            delete => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id) = @$arg;

                evTRACE and print "watchdog delete $dispatch_id\n";
            
                $heap->{watchlist}->remove_items(sub {
                    shift == $dispatch_id
                });
                
                if ($heap->{watchlist}->get_item_count) {
                    $heap->{alarm_id} = $kernel->alarm(check => $heap->{watchlist}->get_next_priority);
                } else {
                    $kernel->alarm_remove_all();
                }
                return 1;
            },
            check => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "watchdog check\n";
                
                while ($heap->{watchlist}->get_next_priority && $heap->{watchlist}->get_next_priority <= time) {
                    my ($priority, $id, $dispatch_id) = $heap->{watchlist}->dequeue_next;
                    
                    $kernel->yield('kill_job',$dispatch_id);
                }

                if ($heap->{watchlist}->get_item_count) {
                    $heap->{alarm_id} = $kernel->alarm(check => $heap->{watchlist}->get_next_priority);
                }
            },
            kill_job => sub {
                my ($kernel,$heap,$dispatch_id) = @_[KERNEL, HEAP, ARG0];
                evTRACE and print "watchdog kill_job $dispatch_id\n";
                
                system('bkill ' . $dispatch_id);
            }
        }
    );

    our $lsftail = POE::Session->create(
        inline_states => {
            _start => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];

                $kernel->alias_set("lsftail");
                $kernel->call('IKC','publish','lsftail',[qw(add_watcher delete_watcher quit)]);

                $heap->{monitor} = POE::Wheel::FollowTail->new(
                    Filename => "/usr/local/lsf/work/gsccluster1/logdir/lsb.acct",
                    InputEvent => 'handle_input',
                    ResetEvent => 'handle_reset',
                    ErrorEvent => 'handle_error'
                );
                $heap->{csv} = Text::CSV->new({
                    sep_char => ' ',
                });
                
                $heap->{watchers} = {};
                $heap->{alarms} = {};
            },
            add_watcher => sub {
                my ($heap,$kernel,$params) = @_[HEAP,KERNEL,ARG0];
                my ($job_id,$action) = ($params->{job_id},$params->{action});
                
                my $id = $kernel->delay_set('skip_it',180,$job_id);

                $heap->{watchers}{$job_id} = $action;
                $heap->{alarms}{$job_id} = $id;
            },
            delete_watcher => sub {
                my ($kernel, $heap,$params) = @_[KERNEL,HEAP,ARG0];
                my $job_id = $params->{job_id};
            
                delete $heap->{watchers}{$job_id};
                my $aid = delete $heap->{alarms}{$job_id};
                
                if ($aid) {
                    $kernel->alarm_remove($aid);
                }
            },
            quit => sub {
                my ($heap) = $_[HEAP];
                
                delete $heap->{monitor};
            },
            handle_input => sub {
                my ($kernel, $heap, $line) = @_[KERNEL,HEAP,ARG0];
#                print "Log: $line\n";

                $heap->{csv}->parse($line);
                my @fields = $heap->{csv}->fields();

                $kernel->yield('event_' . $fields[0], $line, \@fields);
            },
            handle_reset => sub {
                print "Log rolled over.\n";
            },
            handle_error => sub {
                my ($heap, $operation, $errnum, $errstr, $wheel_id) = @_[HEAP, ARG0..ARG3];
                warn "Wheel $wheel_id: $operation error $errnum: $errstr\n";
                delete $heap->{monitor};
            },
            skip_it => sub {
                my ($kernel, $heap, $job_id) = @_[KERNEL,HEAP,ARG1];
                
                return unless exists $heap->{watchers}{$job_id};
                
                $heap->{watchers}{$job_id}->();
                
                $kernel->call('delete_watcher',{job_id => $job_id});
            },
            event_JOB_FINISH => sub {
                my ($kernel,$heap, $line,$fields) = @_[KERNEL,HEAP, ARG0,ARG1];

                my $job_id = $fields->[3];

                if (exists $heap->{watchers}{$job_id}) {

                    my $offset = $fields->[22];
                    $offset += $fields->[$offset+23];
                    my $job_stat_code = $fields->[$offset + 24];

                    my $job_status;
                    while (my ($k,$v) = each(%JOB_STAT)) {
                        if ($job_stat_code & $v) {
                            if (!defined $job_status ||
                                $JOB_STAT{$job_status} < $v) {
                                $job_status = $k;
                            }
                        }
                    }

#                    print sprintf("%10s %5s %5s ",$job_id, $job_status, $job_stat_code) . 
#                        join(',',@{ $fields }[$offset+28,$offset+29,$offset+54,$offset+55]) . "\n";
                    
                    
                    $heap->{watchers}{$job_id}->(
                        $job_id, $job_status, $job_stat_code,
                        @{ $fields }[$offset+28,$offset+29,$offset+54,$offset+55]
                    );
                    
                    $kernel->yield('delete_watcher',{job_id => $job_id});
                }

            },
        }
    );
    
    our $dispatch = POE::Session->create(
        heap => {
            periodic_check_time => 300,
            job_limit           => 500,
            job_count           => 0,
            fork_limit          => 5,
            fork_count          => 0,
            dispatched          => {}, # keyed on lsf job id
            claimed             => {}, # keyed on remote kernel name
            failed              => {}, # keyed on instance id
            cleaning_up         => {}, # keyed on remote kernel name
            queue               => POE::Queue::Array->new()
        },
        inline_states => {
            _start => sub { 
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch _start\n";

                $kernel->alias_set("dispatch");
                $kernel->call('IKC','publish','dispatch',[qw(add_work get_work end_work quit)]);

                $kernel->post('IKC','monitor','*'=>{register=>'conn',unregister=>'disc'});
                
                $kernel->sig('USR1','sig_USR1');
                $kernel->sig('USR2','sig_USR2');
                $kernel->sig('CHLD','sig_CHLD');
                
                $kernel->yield('unlock_me');
                
                $kernel->delay('periodic_check', $heap->{periodic_check_time});
            },
            _stop => sub {
                evTRACE and print "dispatch _stop\n";
            },
            sig_USR1 => sub {
                my ($kernel) = @_[KERNEL];
                
                $kernel->yield('check_jobs');
                $kernel->sig_handled();
            },
            sig_USR2 => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                
                $kernel->delay('start_jobs',0);

                my @entire_queue = $heap->{queue}->peek_items(sub { 1 });
                print STDERR Data::Dumper->new([$heap,\@entire_queue],['heap','queue'])->Dump . "\n";

                $kernel->sig_handled();
            },
            sig_CHLD => sub {
                my ($heap, $kernel, $pid, $child_error) = @_[HEAP, KERNEL, ARG1, ARG2];
                $heap->{fork_count}--;

                evTRACE and print "dispatch sig_CHLD $pid $child_error\n";
            },
            unlock_me => sub {
                Workflow::Server->unlock('Hub');
            },
            quit => sub {
                my ($kernel) = @_[KERNEL];
                evTRACE and print "dispatch quit\n";

                $kernel->post('lsftail','quit');
                $kernel->yield('quit_stage_2');

                return 1; # must return something here so IKC forwards the reply
            },
            quit_stage_2 => sub {
                my ($kernel) = @_[KERNEL];
                evTRACE and print "dispatch quit_stage_2\n";

                $kernel->alarm_remove_all;
                $kernel->alias_remove('dispatch');
                $kernel->post('IKC','shutdown');
            },
            conn => sub {
                my ($name,$real) = @_[ARG1,ARG2];
                evTRACE and print "dispatch conn ", ($real ? '' : 'alias '), "$name\n";
            },
            disc => sub {
                my ($kernel,$session,$heap,$remote_kernel,$real) = @_[KERNEL,SESSION,HEAP,ARG1,ARG2];
                evTRACE and print "dispatch disc ", ($real ? '' : 'alias '), "$remote_kernel\n";
                
                if (delete $heap->{cleaning_up}->{$remote_kernel} || exists $heap->{claimed}->{$remote_kernel}) {
                    $heap->{job_count}--;
                    
                    $kernel->delay('start_jobs',0);
                }
                
                if (exists $heap->{claimed}->{$remote_kernel}) {
                    my $payload = delete $heap->{claimed}->{$remote_kernel};
#                    my ($instance, $type, $input, $sc) = @$payload;
                    my $instance = $payload->{instance};
                    my $sc = $payload->{shortcut_flag};
                    
                    warn 'Blade failed on ' . $instance->id . ' ' . $instance->name . "\n";

                    if ($sc) {
                        $payload->[3] = 0;
                    } else {
                        $heap->{failed}->{$instance->id}++;
                    }

                    if ($heap->{failed}->{$instance->id} <= 5) {
                        $heap->{queue}->enqueue(200,$payload);
                    } else {
                        $kernel->yield('end_work',[-666,$remote_kernel,$instance->id,'crashed',{}]);
                    }
                }                
            },
            add_work => sub {
                my ($kernel, $heap, $params) = @_[KERNEL, HEAP, ARG0];
                my $instance = $params->{instance};
                evTRACE and print "dispatch add_work " . $instance->id . "\n";

                $heap->{failed}->{$instance->id} = 0;
                $heap->{queue}->enqueue(100,$params);
                
                $kernel->delay('start_jobs',0);                
            },
            get_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id, $remote_kernel, $where) = @$arg;
                evTRACE and print "dispatch get_work $dispatch_id $where\n";

                if ($heap->{dispatched}->{$dispatch_id}) {
                    my $payload = delete $heap->{dispatched}->{$dispatch_id};
                    my ($instance, $type, $input, $sc) = @{ $payload }{qw/instance operation_type input shortcut_flag/};

                    $heap->{claimed}->{$remote_kernel} = $payload;

                    $kernel->post('IKC','post','poe://UR/workflow/begin_instance',[ $instance->id, $dispatch_id ]);
                    $kernel->post('IKC','post',$where,[$instance, $type, $input, $sc]);
                } else {
                    warn "dispatch get_work: unknown id $dispatch_id\n";
                }
            },
            end_work => sub {
                my ($kernel, $heap, $arg) = @_[KERNEL, HEAP, ARG0];
                my ($dispatch_id, $remote_kernel, $id, $status, $output, $error_string) = @$arg;
                evTRACE and print "dispatch end_work $dispatch_id $id\n";

                delete $heap->{failed}->{$id};

                my $was_shortcutting = 0;

                if ($remote_kernel) {
                    my $payload = delete $heap->{claimed}->{$remote_kernel};
                    if ($payload) {
#                        my ($instance,$type,$input,$sc) = @$payload;
                        my $sc = $payload->{shortcut_flag};
                        if ($sc && !defined $output) {
                            $was_shortcutting = 1;
                            $payload->{shortcut_flag} = 1;
                            $kernel->yield('add_work',$payload);
                        }
                    }
                    
                    $heap->{cleaning_up}->{$remote_kernel} = 1;
                }

                $kernel->post('IKC','post','poe://UR/workflow/end_instance',[ $id, $status, $output, $error_string ])
                    unless $was_shortcutting;
                    
                $kernel->yield('finalize_work',[$id]) unless $remote_kernel;
            },
            finalize_work => sub {
                my ($kernel,$create_arg,$called_arg) = @_[KERNEL,ARG0,ARG1];
                my ($id) = @$create_arg;
                evTRACE and print "dispatch finalize_work $id\n";

                if (@{ $called_arg }) {
                    my ($user_sec,$sys_sec,$mem,$swap) = @{ $called_arg }[3,4,5,6];
                    
                    $kernel->post('IKC','post','poe://UR/workflow/finalize_instance',[ $id, ($user_sec+$sys_sec), $mem, $swap ]);
                } else {
                    $kernel->post('IKC','post','poe://UR/workflow/finalize_instance',[ $id ]);
                }
            },
            start_jobs => sub {
                my ($kernel, $session, $heap) = @_[KERNEL, SESSION, HEAP];
                evTRACE and print "dispatch start_jobs " . $heap->{job_count} . ' ' . $heap->{job_limit} . "\n";
                
                my @requeue = ();
                while ($heap->{job_count} < $heap->{job_limit}) {
                    my ($priority, $queue_id, $payload) = $heap->{queue}->dequeue_next();
                    if (defined $priority) {
#                        my ($instance, $type, $input, $sc) = @$payload;

                        my $lsf_job_id;
                        if ($payload->{shortcut_flag}) {
                            if ($heap->{fork_count} >= $heap->{fork_limit}) {
                                push @requeue, $payload;
                                next;
                            }
                            
                            $lsf_job_id = $kernel->call($_[SESSION],'fork_worker',
                                $payload->{operation_type}->command_class_name
                            );
                            $heap->{fork_count}++;
                            $heap->{job_count}++;
                        } else {
                            $lsf_job_id = $kernel->call($_[SESSION],'lsf_bsub',
                                $payload->{operation_type}->lsf_queue,
                                $payload->{operation_type}->lsf_resource,
                                $payload->{operation_type}->command_class_name,
                                $payload->{out_log},
                                $payload->{err_log},
                                $payload->{instance}->name
                            );
                            $heap->{job_count}++;
                            
                            my $cb = $session->postback(
                                'finalize_work', $payload->{instance}->id
                            );

                            $kernel->post('lsftail','add_watcher',{job_id => $lsf_job_id, action => $cb});                

                        }

                        $heap->{dispatched}->{$lsf_job_id} = $payload;

                        $kernel->post('IKC','post','poe://UR/workflow/schedule_instance',[$payload->{instance}->id,$lsf_job_id]);

                        evTRACE and print "dispatch start_jobs submitted $lsf_job_id " . $payload->{shortcut_flag} . "\n";
                    } else {
                        last;
                    }
                }
                
                foreach my $payload (@requeue) {
                    $heap->{queue}->enqueue(125,$payload);
                }
            },
            fork_worker => sub {
                my ($kernel, $command_class) = @_[KERNEL, ARG0];
                evTRACE and print "dispatch fork_worker\n";

                my $hostname = hostname;
                my $port = $port_number;

                my $namespace = (split(/::/,$command_class))[0];

                my @libs = UR::Util::used_libs();
                my $libstring = '';
                foreach my $lib (@libs) {
                    $libstring .= 'use lib "' . $lib . '"; ';
                }

                my @cmd = (
                    'perl',
                    '-e',
                    $libstring . 'use ' . $namespace . '; use ' . $command_class . '; use Workflow::Server::Worker; Workflow::Server::Worker->start("' . $hostname . '",' . $port . ',1)'
                );

                my $pid;
                {
                    if ($pid = fork()) {
                        # parent
                        evTRACE and print "dispatch fork_worker " . join(' ', @cmd) . "\n";

                        return 'P' . $pid;
                    } elsif (defined $pid) {
                        # child
                        evTRACE and print "dispatch fork_worker started $$\n";

                        exec @cmd;
                    } else {
                    
                    }
                }
            },
            lsf_bsub => sub {
                my ($kernel, $queue, $rusage, $command_class, $stdout_file, $stderr_file, $name) = @_[KERNEL, ARG0, ARG1, ARG2, ARG3, ARG4, ARG5];
                evTRACE and print "dispatch lsf_cmd $queue $rusage $stdout_file $stderr_file $name\n";

                $queue ||= 'long';
                $rusage ||= 'rusage[tmp=100]';
                $name ||= 'worker';

                my $lsf_opts;

                $rusage =~ s/^\s+//;
                if ($rusage =~ /^-/) {
                    $lsf_opts = $rusage;
                    if ($lsf_opts !~ /-o/i) {
                        $lsf_opts .= ' -o ' . $stdout_file;
                    }
                    if ($lsf_opts !~ /-e/i) {
                        $lsf_opts .= ' -e ' . $stderr_file;
                    }
                } else {
                    $lsf_opts = '-R "' . $rusage . '"';
                    if ($stdout_file) {
                        $lsf_opts .= ' -o ' . $stdout_file;
                    }
                    if ($stderr_file) {
                        $lsf_opts .= ' -e ' . $stderr_file;
                    }
                }

                my $hostname = hostname;
                my $port = $port_number;

                my $namespace = (split(/::/,$command_class))[0];

                my @libs = UR::Util::used_libs();
                my $libstring = '';
                foreach my $lib (@libs) {
                    $libstring .= 'use lib "' . $lib . '"; ';
                }

                my $cmd = 'bsub -q ' . $queue . ' -m blades ' . $lsf_opts .
                    ' -J "' . $name . '" perl -e \'' . $libstring . 'use ' . $namespace . '; use ' . $command_class . '; use Workflow::Server::Worker; Workflow::Server::Worker->start("' . $hostname . '",' . $port . ')\'';

                evTRACE and print "dispatch lsf_cmd $cmd\n";

                my $bsub_output = `$cmd`;

                evTRACE and print "dispatch lsf_cmd $bsub_output";

                # Job <8833909> is submitted to queue <long>.
                $bsub_output =~ /^Job <(\d+)> is submitted to queue <(\w+)>\./;
                
                my $lsf_job_id = $1;
                
                return $lsf_job_id;
            },
            periodic_check => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch periodic_check\n";
                
                if (scalar keys %{ $heap->{dispatched} } > 0) {
                    $kernel->yield('check_jobs');
                }
                
                $kernel->delay('periodic_check', $heap->{periodic_check_time});                
            },
            check_jobs => sub {
                my ($kernel, $heap) = @_[KERNEL, HEAP];
                evTRACE and print "dispatch check_jobs\n";
                
                my $number_restarted = 0;
                foreach my $lsf_job_id (keys %{ $heap->{dispatched} }) {
                    next if ($lsf_job_id =~ /^P/);
                    my $restart = 0;
                
                    if (my ($info,$events) = lsf_state($lsf_job_id)) {
                        $restart = 1 if ($info->{'Status'} eq 'EXIT');
                        
                        evTRACE and print "dispatch check_jobs <$lsf_job_id> suspended by user\n" 
                            if ($info->{'Status'} eq 'PSUSP');
                    } else {
                        $restart = 1;
                    }
                    
                    if ($restart) {
                        my $payload = delete $heap->{dispatched}->{$lsf_job_id};
#                        my ($instance, $type, $input) = @$payload;
                        my $instance = $payload->{instance};

                        evTRACE and print 'dispatch check_jobs ' . $instance->id . ' ' . $instance->name . " vanished\n";
                        $heap->{job_count}--;
                        $heap->{failed}->{$instance->id}++;

                        if ($heap->{failed}->{$instance->id} <= 5) {
                            $heap->{queue}->enqueue(150,$payload);
                            
                            $number_restarted++;
                        } else {
                            $kernel->yield('end_work',[$lsf_job_id,undef,$instance->id,'crashed',{}]);
                        }
                    }
                }
                
                $kernel->delay('start_jobs',0) if ($number_restarted > 0);
            }
        }
    );

    $Storable::forgive_me=1;
}

sub lsf_state {
    my ($lsf_job_id) = @_;

    my $spool = `bjobs -l $lsf_job_id 2>&1`;
    return if ($spool =~ /Job <$lsf_job_id> is not found/);

    # this regex nukes the indentation and line feed
    $spool =~ s/\s{22}//gm; 

    my @eventlines = split(/\n/, $spool);
    shift @eventlines unless ($eventlines[0] =~ m/\S/);  # first line is white space
    
    my $jobinfoline = shift @eventlines;
    # sometimes the prior regex nukes the white space between Key <Value>
    $jobinfoline =~ s/(?<!\s{1})</ </g;

    my %jobinfo = ();
    # parse out a line such as
    # Key <Value>, Key <Value>, Key <Value>
    while ($jobinfoline =~ /(?:^|(?<=,\s{1}))(.+?)(?:\s+<(.*?)>)?(?=(?:$|;|,))/g) {
        $jobinfo{$1} = $2;
    }

    my @events = ();
    foreach my $el (@eventlines) {
        $el =~ s/(?<!\s{1})</ </g;

        my $time = substr($el,0,21,'');
        substr($time,-2,2,'');

        # see if we really got the time string
        if ($time !~ /\w{3}\s+\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}/) {
            # there's stuff we dont care about at the bottom, just skip it
            next;
        }

        my @entry = (
            $time,
            {}
        );

        while ($el =~ /(?:^|(?<=,\s{1}))(.+?)(?:\s+<(.*?)>)?(?=(?:$|;|,))/g) {
            $entry[1]->{$1} = $2;
        }
        push @events, \@entry;
    }


    return (\%jobinfo, \@events);
}

1;
