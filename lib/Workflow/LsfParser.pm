package Workflow::LsfParser;

use strict;
use warnings;

class Workflow::LsfParser {
    has => [
        resource => { is => 'Workflow::Resource' },
        queue => { is => 'String' },
    ],
};

sub get_resource_from_lsf_resource {
    my $lsf_resource = shift;
    my $resource = Workflow::Resource->create();
    # parse mem limit -M ###kb
    my ($mem_limit) = ($lsf_resource =~ /-M\s(\d+)/);
    if (defined $mem_limit) {
        $mem_limit = $mem_limit / 1024;
        $resource->mem_limit($mem_limit);
    }
    # parse cpucs -n cpus
    my ($min_proc) = ($lsf_resource =~ /-n\s(\d+)/);
    if (defined $min_proc) {
        $resource->min_proc($min_proc);
    }
    # handle rusage section
    my ($rusage) = ($lsf_resource =~ /rusage\[([^\]]*)/);
    # parse mem request rusage[mem=###mb, ...]
    my ($mem_request) = ($rusage =~ /mem=(\d+)/); 
    if (defined $mem_request) {
        $resource->mem_request($mem_request);
    }
    # parse tmp request rusage[gtmp=###gb ...]
    my ($gtmp) = ($rusage =~ /gtmp=(\d+)/);
    if (defined $gtmp) {
        $resource->tmp_space($gtmp);
        $resource->use_gtmp(1);
    }
    # if gtmp didnt do it, there should be info in
    # tmp. gtmp is genome center specific and avoids
    # a problem with lsfs tmp disk allocation sys
    my ($tmp) = ($rusage =~ /tmp=(\d+)/);
    if (defined $tmp) {
        $tmp = $tmp / 1024;
        $resource->tmp_space($tmp);
    }
}