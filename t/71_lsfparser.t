#!/usr/bin/env perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT}=1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS}=1;
}

use strict;
use warnings;

use Test::More tests => 14;

use above 'Workflow';
use Workflow;

require_ok('Workflow');
require_ok('Workflow::LsfParser');

# test 1
my $lsfresource1 = "-R 'select[model!=Opteron250 && type==LINUX64 && tmp>90000 && mem>10000] span[hosts=1] rusage[tmp=90000, mem=10000]' -M 10000000 -n 4 -o /gscmnt/sata919/info/model_data/2857040877/build102360021/logs/solexa/100218_HWUSI-EAS1554_101141827_617AD/102360046.out -e /gscmnt/sata919/info/model_data/2857040877/build102360021/logs/solexa/100218_HWUSI-EAS1554_101141827_617AD/102360046.err";
my $resource1 = Workflow::LsfParser::get_resource_from_lsf_resource($lsfresource1);
ok($resource1->mem_limit == 10000000, "mem_limit parsed successfully (1)");
ok($resource1->mem_request == 10000, "mem_request parsed successfully (1)");
ok($resource1->min_proc == 4, "min_proc parsed successfully (1)");
ok($resource1->tmp_space == 88, "tmp_space parsed successfully (1)");

# test 2
my $lsfresource2 = "-R 'select[model!=Opteron250 && type==LINUX64] span[hosts=1] rusage[mem=12000]' -M 1610612736 -o /gscmnt/sata919/info/model_data/2857040877/build102360021/logs/all_sequences/102360057.out -e /gscmnt/sata919/info/model_data/2857040877/build102360021/logs/all_sequences/102360057.err";
my $resource2 = Workflow::LsfParser::get_resource_from_lsf_resource($lsfresource2);
ok($resource2->mem_limit == 1610612736, "mem_limit parsed successfully (2)");
ok($resource2->mem_request == 12000, "mem_request parsed successfully (2)");
ok(!defined $resource2->min_proc, "min_proc is undefined (2)");
ok(!defined $resource2->tmp_space, "tmp_space is undefined (2)");

# test 3
my $lsfresource3 = "-R 'select[model!=Opteron250 && type==LINUX64] span[hosts=1] rusage[tmp=90000:mem=16000]' -M 16000000 -o /gscmnt/sata897/info/model_data/2860752101/build104181182/logs//104181190.out -e /gscmnt/sata897/info/model_data/2860752101/build104181182/logs//104181190.err";
my $resource3 = Workflow::LsfParser::get_resource_from_lsf_resource($lsfresource3);
ok($resource3->mem_limit == 16000000, "mem_limit parsed successfully (3)");
ok($resource3->mem_request == 16000, "mem_request parsed successfully (3)");
ok(!defined $resource3->min_proc, "min_proc is undefined (3)");
ok($resource3->tmp_space == 88, "tmp_space parsed successfully (3)");
